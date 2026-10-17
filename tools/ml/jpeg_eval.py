#!/usr/bin/env python3
"""The "jpeg" golden category (S9, 04 §7.2): how much the JPEG cleanup pack (jpeg.fbcnn) adds to
the plain pipeline on strongly compressed photos.

  python3 tools/ml/jpeg_eval.py --cli BUILD/refocal-cli --models MODELS_DIR WORK_DIR
         [--qualities 10,20,30,50] [--no-iqa]

Data: 8 photos of the Kodak test suite (768x512, released by Eastman Kodak for unrestricted
usage; pinned by SHA-256 below), saved by Pillow (IJG tables, 4:2:0) at each quality. Each JPEG
goes through refocal-cli at scale 1 (SR x4, area /4: the size stays) twice: the plain pipeline
and the same with --jpeg-model jpeg.fbcnn, the QF read from the file's own tables as in the app.
Both are compared with the original by PSNR / SSIM (Y) and scored without a reference by MUSIQ
(pyiqa; --no-iqa skips it). Exit: NR-IQA of the cleanup >= the plain pipeline (S9).

Writes WORK_DIR/jpeg.json and prints a Markdown table. Needs numpy, pillow (pyiqa, torch).
"""
import argparse, hashlib, json, pathlib, subprocess, sys, urllib.request

import numpy as np
from PIL import Image

KODAK = "https://r0k.us/graphics/kodak/kodak/kodim{}.png"
IMAGES = {
    "01": "a56e27cbf5f843c048b6af1d6e090760e9c92fadba88b7dee0205918a37523bd",
    "03": "e25ca1ff2f0c0cb5fdfd5f9b0a0bb21ac4c3de3c84a67f35b09a85d3306249db",
    "04": "e3b946107c5d3441c022f678d0c3caf1e224d81b1604ba840a4f88e562de61aa",
    "05": "10349e963c5c813d327852f82c1795fa4148d69fedffc4c589bee458e3ac3d53",
    "07": "b77d3f006f42414bb242222e0482e750c0fb9e5ee8d4bed2f6f11c5605fe54a4",
    "15": "7538cbb80cb9103606c48b806eae57d56c885c7f90b9b3be70a41160f9cbb683",
    "20": "3b46c71e3b92a563820ba32936be8330c586c41f938efd94be938386aae4328a",
    "23": "e3111a2fd4da24af15d6459ef9eacfe54106b38e27b4a21821b75c3f5d2d5baf",
}


def fetch(name: str, sha: str, dst: pathlib.Path) -> pathlib.Path:
    if not dst.exists():
        print("downloading", KODAK.format(name), flush=True)
        urllib.request.urlretrieve(KODAK.format(name), dst)
    got = hashlib.sha256(dst.read_bytes()).hexdigest()
    if got != sha:
        dst.unlink()
        sys.exit(f"{dst.name}: sha256 {got}, expected {sha}")
    return dst


def luma(path: pathlib.Path) -> np.ndarray:
    a = np.asarray(Image.open(path).convert("RGB"), np.float64)
    return 0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]


def psnr(a: np.ndarray, b: np.ndarray) -> float:
    mse = np.mean((a - b) ** 2)
    return 99.0 if mse == 0 else float(10 * np.log10(255**2 / mse))


def ssim(a: np.ndarray, b: np.ndarray) -> float:
    """SSIM of two luma planes (8x8 windows, no overlap; Wang et al. 2004 constants)."""
    h, w = (a.shape[0] // 8) * 8, (a.shape[1] // 8) * 8
    x = a[:h, :w].reshape(h // 8, 8, w // 8, 8)
    y = b[:h, :w].reshape(h // 8, 8, w // 8, 8)
    mx, my = x.mean((1, 3)), y.mean((1, 3))
    vx, vy = x.var((1, 3)), y.var((1, 3))
    cxy = ((x - mx[:, None, :, None]) * (y - my[:, None, :, None])).mean((1, 3))
    c1, c2 = (0.01 * 255) ** 2, (0.03 * 255) ** 2
    s = ((2 * mx * my + c1) * (2 * cxy + c2)) / ((mx**2 + my**2 + c1) * (vx + vy + c2))
    return float(s.mean())


def run(cli: str, models: str, work: pathlib.Path, src: pathlib.Path, out: pathlib.Path,
        jpeg: bool) -> float:
    cmd = [cli, "run", "--models", models, "--work", str(work / "jobs"), "--input", str(src),
           "--out", str(out), "--scale", "1", "--backend", "cpu", "--job-id", out.stem]
    if jpeg:
        cmd += ["--jpeg-model", "jpeg.fbcnn"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"{' '.join(cmd)}\n{r.stderr}")
    return json.loads(r.stdout)["wall_s"]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("work")
    ap.add_argument("--cli", required=True)
    ap.add_argument("--models", required=True)
    ap.add_argument("--qualities", default="10,20,30,50")
    ap.add_argument("--no-iqa", action="store_true")
    a = ap.parse_args()
    work = pathlib.Path(a.work)
    for d in ("src", "jpg", "out", "jobs"):
        (work / d).mkdir(parents=True, exist_ok=True)
    iqa = None
    if not a.no_iqa:
        import pyiqa, torch
        iqa = pyiqa.create_metric("musiq", device=torch.device("cpu"))

    rows = []
    for q in [int(v) for v in a.qualities.split(",")]:
        for name, sha in IMAGES.items():
            src = fetch(name, sha, work / "src" / f"kodim{name}.png")
            jpg = work / "jpg" / f"kodim{name}_q{q}.jpg"
            Image.open(src).convert("RGB").save(jpg, quality=q)
            ref = luma(src)
            row = {"image": name, "quality": q}
            for kind, path in [("input", jpg),
                               ("plain", work / "out" / f"kodim{name}_q{q}_plain.png"),
                               ("jpeg", work / "out" / f"kodim{name}_q{q}_jpeg.png")]:
                if kind != "input":
                    row[f"{kind}_s"] = run(a.cli, a.models, work, jpg, path, kind == "jpeg")
                y = luma(path)
                row[f"{kind}_psnr"], row[f"{kind}_ssim"] = psnr(ref, y), ssim(ref, y)
                if iqa is not None:
                    row[f"{kind}_musiq"] = float(iqa(str(path)).item())
            rows.append(row)
            print(json.dumps(row), flush=True)

    (work / "jpeg.json").write_text(json.dumps(rows, indent=1))
    kinds = ["input", "plain", "jpeg"]
    metrics = ["psnr", "ssim"] + ([] if iqa is None else ["musiq"])
    print("\n| Quality | " + " | ".join(f"{m.upper()} {k}" for m in metrics for k in kinds) +
          " | s plain | s jpeg |")
    print("|---" * (1 + len(metrics) * len(kinds) + 2) + "|")
    ok = True
    for q in sorted({r["quality"] for r in rows}):
        rs = [r for r in rows if r["quality"] == q]
        mean = lambda k: sum(r[k] for r in rs) / len(rs)
        cells = [f"{mean(f'{k}_{m}'):.3f}" if m == "ssim" else f"{mean(f'{k}_{m}'):.2f}"
                 for m in metrics for k in kinds]
        print(f"| {q} | " + " | ".join(cells) +
              f" | {mean('plain_s'):.1f} | {mean('jpeg_s'):.1f} |")
        if iqa is not None and mean("jpeg_musiq") < mean("plain_musiq"):
            ok = False
    if not ok:
        sys.exit("NR-IQA of the JPEG cleanup is below the plain pipeline")


if __name__ == "__main__":
    main()
