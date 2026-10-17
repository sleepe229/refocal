#!/usr/bin/env python3
"""Per-subgroup quality of the face packs (ML-BIAS-001, TEST-ML-008): how well a restored face
keeps the person's identity, by skin tone, age, gender and head pose.

  <venv>/bin/python tools/ml/bias_eval.py WORK_DIR [--per-group 100] [--packs face.gfpgan-1.4,face.codeformer]

Data: FairFace validation (CC BY 4.0, Kärkkäinen & Joo 2021) from Hugging Face, sampled evenly
over its 7 race groups (seeded). Each face (448 px crop, ~200 px face) is degraded as an old/small photo would be
(×4 down, Gaussian noise σ 6, JPEG q 50), brought back to the 512 px aligned crop the app feeds
the face model, restored with the **shipped ncnn packs** (ncnn CPU defaults, from the signed
manifest's URLs; one pack per run, results merged by face), and compared with the original by ArcFace cosine similarity (insightface w600k_r50 from
buffalo_l: research-only weights, used here for evaluation, never shipped).

Subgroups:
- skin tone: the Monk scale (MST 1..10) estimated from the individual typology angle (ITA) of
  cheek pixels of the original — a colorimetric proxy, not a human annotation;
- age (FairFace groups), gender (FairFace labels, binary as annotated);
- head pose: frontal / three-quarter / profile from the YuNet landmarks (nose offset).
Glasses are not annotated in FairFace and are not reported.

Writes WORK_DIR/bias.json and prints a Markdown table per pack.
Needs numpy, opencv (FaceDetectorYN), onnxruntime, ncnn, pyarrow, pillow.
"""
import argparse, hashlib, io, json, math, pathlib, sys, urllib.request, zipfile

import cv2
import numpy as np

ROOT = pathlib.Path(__file__).resolve().parents[2]
FAIRFACE = "https://huggingface.co/api/datasets/HuggingFaceM4/FairFace/parquet/1.25/validation/0.parquet"
ARCFACE_ZIP = "https://github.com/deepinsight/insightface/releases/download/v0.7/buffalo_l.zip"
YUNET = "https://github.com/opencv/opencv_zoo/raw/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx"
# Report order; the parquet's own class names map its integer labels (read from its metadata).
RACES = ["White", "Black", "Latino_Hispanic", "East Asian", "Southeast Asian", "Indian", "Middle Eastern"]
AGES = ["0-2", "3-9", "10-19", "20-29", "30-39", "40-49", "50-59", "60-69", "more than 70"]
# FFHQ-512 alignment template (5 points), as the core uses (pipeline/faces.cpp).
FFHQ = np.array([[192.98, 239.95], [318.90, 240.19], [256.63, 314.02], [201.26, 371.41],
                 [313.09, 371.15]], np.float32)
ARC = np.array([[38.2946, 51.6963], [73.5318, 51.5014], [56.0252, 71.7366], [41.5493, 92.3655],
                [70.7299, 92.2041]], np.float32)


def fetch(url: str, dst: pathlib.Path) -> pathlib.Path:
    if not dst.exists():
        print("downloading", url, flush=True)
        urllib.request.urlretrieve(url, dst)
    return dst


def ita_monk(img: np.ndarray, lm: np.ndarray) -> tuple[float, int]:
    """ITA (degrees) of cheek skin and the Monk tone it maps to (1 lightest .. 10 darkest)."""
    lab = cv2.cvtColor(img, cv2.COLOR_RGB2LAB).astype(np.float32)
    L = lab[..., 0] * 100 / 255
    b = lab[..., 2] - 128
    vals = []
    eye_y = (lm[0, 1] + lm[1, 1]) / 2
    for ex, _ in (lm[0], lm[1]):  # below each eye
        cx = int(ex)
        cy = int(eye_y + 0.45 * (lm[3, 1] - eye_y))
        r = max(2, int(0.08 * abs(lm[1, 0] - lm[0, 0])))
        patch = (slice(max(cy - r, 0), cy + r), slice(max(cx - r, 0), cx + r))
        vals.append((np.median(L[patch]), np.median(b[patch])))
    l, bb = np.mean(vals, axis=0)
    ita = math.degrees(math.atan2(l - 50, bb if abs(bb) > 1e-3 else 1e-3))
    # ITA bands (Chardon 1991) spread over MST 1..10: > 55 very light ... < -30 dark.
    edges = [55, 48, 41, 28, 19, 10, 0, -15, -30]
    return ita, 1 + sum(ita < e for e in edges)


def pose(lm: np.ndarray) -> str:
    eyes = lm[1, 0] - lm[0, 0]
    off = abs(lm[2, 0] - (lm[0, 0] + lm[1, 0]) / 2) / max(eyes, 1e-3)
    return "frontal" if off < 0.15 else ("three-quarter" if off < 0.35 else "profile")


def similarity(src, dst):
    """Least-squares similarity (Umeyama, no reflection) taking src points to dst, as the core's
    face_alignment does; cv2.estimateAffinePartial2D's robust modes can drop good points."""
    ms, md = src.mean(0), dst.mean(0)
    s, d = src - ms, dst - md
    u, sig, vt = np.linalg.svd(d.T @ s / len(src))
    e = np.eye(2)
    if np.linalg.det(u @ vt) < 0:
        e[1, 1] = -1
    r = u @ e @ vt
    scale = np.trace(np.diag(sig) @ e) / s.var(0).sum()
    m = np.zeros((2, 3), np.float32)
    m[:, :2] = scale * r
    m[:, 2] = md - scale * r @ ms
    return m


def warp(img, lm, tmpl, size):
    return cv2.warpAffine(img, similarity(lm, tmpl), (size, size), borderMode=cv2.BORDER_REFLECT_101)


class Arc:
    def __init__(self, work):
        import onnxruntime as ort
        z = fetch(ARCFACE_ZIP, work / "buffalo_l.zip")
        with zipfile.ZipFile(z) as f:
            name = next(n for n in f.namelist() if n.endswith("w600k_r50.onnx"))
            (work / "w600k_r50.onnx").write_bytes(f.read(name))
        self.s = ort.InferenceSession(str(work / "w600k_r50.onnx"), providers=["CPUExecutionProvider"])

    def emb(self, face112):
        x = (face112.astype(np.float32) - 127.5) / 127.5
        e = self.s.run(None, {self.s.get_inputs()[0].name: x.transpose(2, 0, 1)[None]})[0][0]
        return e / np.linalg.norm(e)


class Pack:
    """A face pack from the manifest, run with ncnn on the CPU in fp32 (ADR-0023/0024)."""

    def __init__(self, pid, work):
        import ncnn
        m = json.loads((ROOT / "tools/models/manifest.json").read_text(encoding="utf-8"))
        p = next(x for x in m["packs"] if x["id"] == pid)
        d = work / pid
        d.mkdir(exist_ok=True)
        for f in p["files"]:
            dst = fetch(f["urls"][0], d / f["path"])
            assert hashlib.sha256(dst.read_bytes()).hexdigest() == f["sha256"], f["path"]
        self.split = (d / "encoder.ncnn.param").exists()
        self.nets = []
        for name in (["encoder", "generator"] if self.split else ["model"]):
            n = ncnn.Net()
            n.opt.use_vulkan_compute = False
            n.load_param(str(d / f"{name}.ncnn.param"))
            n.load_model(str(d / f"{name}.ncnn.bin"))
            self.nets.append(n)
        if self.split:
            self.codebook = np.fromfile(d / "codebook.f32", np.float32).reshape(1024, 256)
        self.ncnn = ncnn

    def restore(self, face512, w=0.7):
        x = np.ascontiguousarray((face512.astype(np.float32) / 127.5 - 1).transpose(2, 0, 1))
        ex = self.nets[0].create_extractor()
        ex.input("in0", self.ncnn.Mat(x))
        if not self.split:
            out = np.array(ex.extract("out0")[1])
        else:
            outs = [np.array(ex.extract(f"out{i}")[1]) for i in range(5)]
            idx = outs[0].reshape(256, 1024).argmax(1)
            q = self.codebook[idx].reshape(16, 16, 256).transpose(2, 0, 1).copy()
            g = self.nets[1].create_extractor()
            for i, a in enumerate([q] + outs[1:] + [np.full((1, 1, 1), w, np.float32)]):
                g.input(f"in{i}", self.ncnn.Mat(np.ascontiguousarray(a)))
            out = np.array(g.extract("out0")[1])
        return np.clip((out.transpose(1, 2, 0) + 1) * 127.5 + 0.5, 0, 255).astype(np.uint8)


def degrade(img, rng):
    h, w = img.shape[:2]
    small = cv2.resize(img, (w // 4, h // 4), interpolation=cv2.INTER_AREA).astype(np.float32)
    small = np.clip(small + rng.normal(0, 6, small.shape), 0, 255).astype(np.uint8)
    ok, enc = cv2.imencode(".jpg", cv2.cvtColor(small, cv2.COLOR_RGB2BGR), [cv2.IMWRITE_JPEG_QUALITY, 50])
    lq = cv2.cvtColor(cv2.imdecode(enc, cv2.IMREAD_COLOR), cv2.COLOR_BGR2RGB)
    return cv2.resize(lq, (w, h), interpolation=cv2.INTER_CUBIC)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("work")
    ap.add_argument("--per-group", type=int, default=100)
    ap.add_argument("--packs", default="face.gfpgan-1.4,face.codeformer")
    a = ap.parse_args()
    work = pathlib.Path(a.work).resolve()
    work.mkdir(parents=True, exist_ok=True)
    import pyarrow.parquet as pq
    from PIL import Image

    t = pq.read_table(fetch(FAIRFACE, work / "fairface_val_1.25.parquet"))
    feats = json.loads(t.schema.metadata[b"huggingface"])["info"]["features"]
    names = {k: feats[k]["names"] for k in ("race", "age", "gender")}
    labels = t.select(["age", "gender", "race"]).to_pylist()  # images stay in Arrow until used
    images = t.column("image")
    rng = np.random.default_rng(20261017)
    by_race = {r: [] for r in RACES}
    for i, row in enumerate(labels):
        by_race[names["race"][row["race"]]].append(dict(row, index=i))
    det = cv2.FaceDetectorYN.create(str(fetch(YUNET, work / "yunet.onnx")), "", (0, 0), 0.7, 0.3)
    arc = Arc(work)
    packs = {p: Pack(p, work) for p in a.packs.split(",")}
    rows = []
    for race, items in by_race.items():
        for i in rng.permutation(len(items)):
            if sum(r["race"] == race for r in rows) >= a.per_group:
                break
            it = items[i]
            raw = images[it["index"]].as_py()["bytes"]
            img = np.asarray(Image.open(io.BytesIO(raw)).convert("RGB"))
            h, w = img.shape[:2]
            det.setInputSize((w, h))
            _, faces = det.detect(cv2.cvtColor(img, cv2.COLOR_RGB2BGR))
            if faces is None or len(faces) != 1:
                continue
            lm = faces[0][4:14].reshape(5, 2).astype(np.float32)
            ita, mst = ita_monk(img, lm)
            ref = arc.emb(warp(img, lm, ARC, 112))
            lq = degrade(img, rng)
            # Same geometry the app uses: the 512 aligned crop of the (degraded) photo, restored,
            # then compared in ArcFace's 112 crop of that 512 face.
            lq512 = warp(lq, lm, FFHQ, 512)
            # In the 512 crop the landmarks sit on the FFHQ template: FFHQ -> ArcFace 112.
            base = float(arc.emb(warp(lq512, FFHQ, ARC, 112)) @ ref)
            r = {"race": race, "age": names["age"][it["age"]], "gender": names["gender"][it["gender"]],
                 "ita": round(ita, 1), "mst": mst, "pose": pose(lm), "lq": round(base, 4)}
            for pid, pk in packs.items():
                out = pk.restore(lq512)
                r[pid] = round(float(arc.emb(warp(out, FFHQ, ARC, 112)) @ ref), 4)
                # What the app saves by default: half the restored face over the photo (0.5).
                mix = ((out.astype(np.float32) + lq512) / 2).round().astype(np.uint8)
                r[pid + "@0.5"] = round(float(arc.emb(warp(mix, FFHQ, ARC, 112)) @ ref), 4)
            rows.append(r)
            if len(rows) % 50 == 0:
                print(len(rows), "faces", flush=True)
    # One file per run; runs with other packs on the same seed see the same faces: merge them.
    (work / f"bias-{'+'.join(packs)}.json").write_text(json.dumps(rows, indent=1))
    merged = {}
    for f in sorted(work.glob("bias-*.json")):
        for i, r in enumerate(json.loads(f.read_text())):
            merged.setdefault(i, {}).update(r)
    allpacks = sorted({k for r in merged.values() for k in r if k.startswith("face.")},
                      key=lambda k: (k.split("@")[0], "@" in k))
    report([merged[i] for i in sorted(merged) if all(p in merged[i] for p in allpacks)], allpacks)
    return 0


def report(rows, packs):
    def group(key, order):
        out = []
        for g in order:
            sel = [r for r in rows if r[key] == g]
            if len(sel) < 10:
                continue
            cells = [f"{np.mean([r['lq'] for r in sel]):.3f}"]
            cells += [f"{np.mean([r[p] for r in sel]):.3f}" for p in packs]
            out.append(f"| {key}: {g} | {len(sel)} | " + " | ".join(cells) + " |")
        return out
    mst_bands = {r["mst"] for r in rows}
    lines = ["| Group | n | degraded input | " + " | ".join(packs) + " |",
             "|---|---|---|" + "---|" * len(packs)]
    lines += group("race", RACES)
    lines += group("mst", sorted(mst_bands))
    lines += group("age", AGES)
    lines += group("gender", ["Male", "Female"])
    lines += group("pose", ["frontal", "three-quarter", "profile"])
    allc = [f"{np.mean([r['lq'] for r in rows]):.3f}"] + [f"{np.mean([r[p] for r in rows]):.3f}" for p in packs]
    lines.append(f"| all | {len(rows)} | " + " | ".join(allc) + " |")
    print("\n".join(lines))


if __name__ == "__main__":
    sys.exit(main())
