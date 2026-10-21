#!/usr/bin/env python3
"""SR packs against the bundled model on the golden set (1.1, 04 §7.2, ADR-0026): whether a
candidate SR pack is no worse than sr.general-x4v3 in a golden category, the condition for
Auto to take it there.

  python3 tools/ml/sr_eval.py WORK --cli BUILD/refocal-cli --models MODELS_DIR
         [--model sr.lsdir-compact] [--baseline sr.general-x4v3] [--no-iqa] [--quick]

Two parts, each through refocal-cli on the CPU, the candidate and the baseline with the same
request, without and with the effective resolution of ADR-0025 (pre_down as Auto chooses it,
tools/ml/effscale.py; the unsharp mask of every Auto recipe in both):

- Synthetic, with a reference: the 24 photos of the Kodak test suite (released by Eastman Kodak
  for unrestricted usage, pinned by SHA-256) area-downscaled by the model's scale and degraded
  per category (clean; blur: Gaussian 0.8 px; noise: Gaussian 6/255 then JPEG 90; jpeg: JPEG
  35), then upscaled back: PSNR / SSIM on luma against the original.
- Real photos of ml/golden/golden.lock (tools/ml/golden_fetch.py), at 2x: MUSIQ, CLIP-IQA and
  MANIQA (pyiqa) of the result scaled to a long side of 1024 px.

Seams (NFR-QLT-003): four Kodak inputs at tiles 128 and 256 against one tile, PSNR.

Exit per category (13 §1.1): the candidate is not below the baseline on 2 of the 3 NR metrics
(real photos), loses at most 0.3 dB of PSNR (synthetic), and has no seams (>= 45 dB). Writes
WORK/sr.json and prints Markdown tables. Needs numpy, scipy, pillow (pyiqa, torch).
"""

import argparse
import hashlib
import io
import json
import pathlib
import subprocess
import sys
import urllib.request

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from effscale import eff_scale  # noqa: E402
from golden_fetch import fetch_all  # noqa: E402

NR_METRICS = ["musiq", "clipiqa", "maniqa"]
KODAK = "https://r0k.us/graphics/kodak/kodak/kodim{:02d}.png"
KODAK_SHA = {
    1: "a56e27cbf5f843c048b6af1d6e090760e9c92fadba88b7dee0205918a37523bd",
    2: "4f4b74a79237e311d72cad958237b5f7088d8bce1c82305ebefe1a70e3022dfd",
    3: "e25ca1ff2f0c0cb5fdfd5f9b0a0bb21ac4c3de3c84a67f35b09a85d3306249db",
    4: "e3b946107c5d3441c022f678d0c3caf1e224d81b1604ba840a4f88e562de61aa",
    5: "10349e963c5c813d327852f82c1795fa4148d69fedffc4c589bee458e3ac3d53",
    6: "363510303b715d4cbc384e1ce227e466b613a09e1b71ae985882bf8e7fbd9b18",
    7: "b77d3f006f42414bb242222e0482e750c0fb9e5ee8d4bed2f6f11c5605fe54a4",
    8: "ba23983c76b4832ee0e8af0592664756841a16779acd69f792e268fb6d13d6e7",
    9: "6a4361c2fc194feb4edaa9f9a4a0620fb9943e460ac7fdf037fb0f6dd6607a7d",
    10: "9dfb70f5867c29ff9ed6313683f19b3d867849e40fbc0c4c54a4a89df341cf23",
    11: "7936814b58b5387fce2e4e2488b4ec830dadd95fa9520f358ddb30990b50f2b6",
    12: "d78c37c2f04f23761ed2367dd77e2db584ddd4c3950833fecf89f199a8126980",
    13: "bc34a3ce58dea09dce1704c997171602de90cb34d0c8503a988b77f473d39b08",
    14: "55a94550ff18f3246c4074fd32b77b0c74447c26b6ad274d564d999c0450ba6e",
    15: "7538cbb80cb9103606c48b806eae57d56c885c7f90b9b3be70a41160f9cbb683",
    16: "a89c7268ccd4718ba424a99fc4643c572cf692ca6eae887185ceb4e9f11d2e54",
    17: "37afcc89fbdcb76d9518e04b2fc011027e2f4cd14b3b2f83cefd721641a47c5b",
    18: "1a9258c365988961d87a0598725b609139c303ad48a5aad6c503c3b1a87849aa",
    19: "b7450b264b1b0a411390d8931b112c27905a992520fc90569dc4b920aa32bbdc",
    20: "3b46c71e3b92a563820ba32936be8330c586c41f938efd94be938386aae4328a",
    21: "ac958597c82073f6bb65129c68f72b651db5b9efd82e11547d07350214bc268b",
    22: "1cee58eb1f2d9c7ebb254d208a03c783ce6cf2c4d8c2cf45e235dd23b4ce1b29",
    23: "e3111a2fd4da24af15d6459ef9eacfe54106b38e27b4a21821b75c3f5d2d5baf",
    24: "1071c68372cc5a01435c2c225a5cf7d4bb803846ec08bb6b3d6721b156d7cb96",
}
SYNTHETIC = ["clean", "blur", "noise", "jpeg"]
# ADR-0025, refocal_core auto.dart: below 0.9 SR runs at the effective resolution, not below 0.4;
# every Auto recipe sharpens at 1.0.
BLUR_BELOW, MIN_PRE_DOWN, SHARPEN = 0.9, 0.4, 1.0
REAL_SCALE = 2
IQA_SIDE = 1024
MAX_PSNR_LOSS, MIN_SEAM_DB = 0.3, 45.0


def kodak(i: int, dst: pathlib.Path) -> pathlib.Path:
    if not dst.exists():
        urllib.request.urlretrieve(KODAK.format(i), dst)
    got = hashlib.sha256(dst.read_bytes()).hexdigest()
    if got != KODAK_SHA[i]:
        dst.unlink()
        sys.exit(f"kodim{i:02d}: sha256 {got}, expected {KODAK_SHA[i]}")
    return dst


def degrade(hr: Image.Image, scale: int, kind: str) -> Image.Image:
    lr = hr.resize((hr.width // scale, hr.height // scale), Image.Resampling.BOX)
    if kind == "blur":
        lr = lr.filter(ImageFilter.GaussianBlur(0.8))
    if kind == "noise":
        rng = np.random.default_rng(20261021)
        a = np.asarray(lr, np.float32) + rng.normal(0, 6, (lr.height, lr.width, 1))
        lr = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    if kind in ("noise", "jpeg"):
        buf = io.BytesIO()
        lr.save(buf, "JPEG", quality=90 if kind == "noise" else 35)
        lr = Image.open(io.BytesIO(buf.getvalue())).convert("RGB")
    return lr


def luma(img: Image.Image) -> np.ndarray:
    a = np.asarray(img.convert("RGB"), np.float64)
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


def pre_down(img: Image.Image) -> float:
    """Auto's pre_down for [img] at 2x or 4x (refocal_core Auto.preDownFor)."""
    e = eff_scale(np.asarray(img.convert("RGB")))
    if e >= BLUR_BELOW:
        return 1.0
    return round(max(MIN_PRE_DOWN, e), 2)


def job_id(stem: str) -> str:
    """A job id the core takes ([A-Za-z0-9_-]{1,64}) for an output name."""
    safe = "".join(c if c.isalnum() or c in "_-" else "_" for c in stem)
    return (
        safe if len(safe) <= 64 else safe[:47] + "_" + hashlib.sha1(stem.encode()).hexdigest()[:16]
    )


class Cli:
    def __init__(self, cli: str, models: str, work: pathlib.Path):
        self.cli, self.models, self.jobs = cli, models, work / "jobs"

    def run(
        self,
        src: pathlib.Path,
        out: pathlib.Path,
        model: str,
        scale: int,
        pre: float,
        tile: int = 0,
    ) -> float:
        cmd = [
            self.cli,
            "run",
            "--models",
            self.models,
            "--work",
            str(self.jobs),
            "--input",
            str(src),
            "--out",
            str(out),
            "--model",
            model,
            "--scale",
            str(scale),
            "--backend",
            "cpu",
            "--job-id",
            job_id(out.stem),
            "--sharpen",
            str(SHARPEN),
            "--no-ai-marker",
        ]
        if pre < 1:
            cmd += ["--pre-down", str(pre)]
        if tile:
            cmd += ["--tile", str(tile)]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode != 0:
            sys.exit(f"{' '.join(cmd)}\n{r.stderr}")
        return json.loads(r.stdout)["wall_s"]


def iqa_metrics():
    import pyiqa
    import torch

    return {m: pyiqa.create_metric(m, device=torch.device("cpu")) for m in NR_METRICS}


def scored(iqa, path: pathlib.Path, tmp: pathlib.Path) -> dict:
    img = Image.open(path).convert("RGB")
    img.thumbnail((IQA_SIDE, IQA_SIDE), Image.Resampling.LANCZOS)
    img.save(tmp)
    return {m: float(f(str(tmp)).item()) for m, f in iqa.items()}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("work")
    ap.add_argument("--cli", required=True)
    ap.add_argument("--models", required=True)
    ap.add_argument("--model", default="sr.general-x4v3")
    ap.add_argument("--baseline", default="sr.general-x4v3")
    ap.add_argument("--scale", type=int, default=4, help="the candidate's own scale")
    ap.add_argument("--golden", default=str(pathlib.Path(__file__).parents[2] / "ml/golden"))
    ap.add_argument("--no-iqa", action="store_true")
    ap.add_argument("--quick", action="store_true", help="4 Kodak photos, 2 real per category")
    a = ap.parse_args()
    work = pathlib.Path(a.work)
    for d in ("src", "lr", "out", "jobs", "real"):
        (work / d).mkdir(parents=True, exist_ok=True)
    cli = Cli(a.cli, a.models, work)
    models = [a.baseline] if a.model == a.baseline else [a.baseline, a.model]
    rows: list[dict] = []

    # ---- synthetic, with a reference ----
    ids = [1, 3, 5, 23] if a.quick else sorted(KODAK_SHA)
    for i in ids:
        hr = Image.open(kodak(i, work / "src" / f"kodim{i:02d}.png")).convert("RGB")
        for kind in SYNTHETIC:
            lr_path = work / "lr" / f"kodim{i:02d}_{kind}.png"
            lr = degrade(hr, a.scale, kind)
            lr.save(lr_path)
            for eff in (False, True):
                pre = pre_down(lr) if eff else 1.0
                if eff and pre == 1.0:
                    continue  # the same request as without
                for m in models:
                    out = work / "out" / f"kodim{i:02d}_{kind}_{m}_{'eff' if eff else 'plain'}.png"
                    s = cli.run(lr_path, out, m, a.scale, pre)
                    y = Image.open(out).convert("RGB").resize(hr.size, Image.Resampling.LANCZOS)
                    row = {
                        "part": "synthetic",
                        "category": kind,
                        "image": f"kodim{i:02d}",
                        "model": m,
                        "eff": eff,
                        "pre_down": pre,
                        "s": s,
                        "psnr": psnr(luma(hr), luma(y)),
                        "ssim": ssim(luma(hr), luma(y)),
                    }
                    rows.append(row)
                    print(json.dumps(row), flush=True)

    # ---- real photos, no reference ----
    iqa = None if a.no_iqa else iqa_metrics()
    photos = fetch_all(pathlib.Path(a.golden) / "golden.lock", work / "real")
    if a.quick:
        seen: dict[str, int] = {}
        photos = [
            p
            for p in photos
            if seen.setdefault(p["category"], 0) < 2
            and not seen.update({p["category"]: seen[p["category"]] + 1})
        ]
    for p in photos:
        img = Image.open(p["path"]).convert("RGB")
        for eff in (False, True):
            pre = pre_down(img) if eff else 1.0
            if eff and pre == 1.0:
                continue
            for m in models:
                out = work / "out" / f"{p['name']}_{m}_{'eff' if eff else 'plain'}.png"
                s = cli.run(pathlib.Path(p["path"]), out, m, REAL_SCALE, pre)
                row = {
                    "part": "real",
                    "category": p["category"],
                    "image": p["name"],
                    "model": m,
                    "eff": eff,
                    "pre_down": pre,
                    "s": s,
                }
                if iqa is not None:
                    row |= scored(iqa, out, work / "iqa.png")
                rows.append(row)
                print(json.dumps(row), flush=True)

    # ---- seams ----
    seams = []
    for i in ids[:4]:
        src = work / "lr" / f"kodim{i:02d}_clean.png"
        for m in models:
            whole = work / "out" / f"seam_{i:02d}_{m}_whole.png"
            cli.run(src, whole, m, a.scale, 1.0, tile=1024)
            for t in (128, 256):
                out = work / "out" / f"seam_{i:02d}_{m}_{t}.png"
                cli.run(src, out, m, a.scale, 1.0, tile=t)
                seams.append(
                    {
                        "image": f"kodim{i:02d}",
                        "model": m,
                        "tile": t,
                        "psnr": psnr(luma(Image.open(whole)), luma(Image.open(out))),
                    }
                )

    (work / "sr.json").write_text(json.dumps({"rows": rows, "seams": seams}, indent=1))
    return report(rows, seams, a.baseline, a.model, iqa is not None)


def report(rows, seams, base, cand, nr: bool) -> int:
    def mean(sel, key):
        v = [r[key] for r in rows if all(r[k] == x for k, x in sel.items())]
        return sum(v) / len(v) if v else float("nan")

    ok = True
    print("\n### Synthetic (Kodak, PSNR / SSIM on luma)\n")
    print(
        "| Category | Effective resolution | "
        + " | ".join(f"{m} PSNR | {m} SSIM" for m in dict.fromkeys([base, cand]))
        + " |"
    )
    print("|---|---|" + "---|---|" * len(dict.fromkeys([base, cand])))
    for c in SYNTHETIC:
        for eff in (False, True):
            sel = {"part": "synthetic", "category": c, "eff": eff}
            if not any(all(r[k] == x for k, x in sel.items()) for r in rows):
                continue
            cells = [
                f"{mean(sel | {'model': m}, 'psnr'):.2f} | {mean(sel | {'model': m}, 'ssim'):.3f}"
                for m in dict.fromkeys([base, cand])
            ]
            print(f"| {c} | {'yes' if eff else 'no'} | " + " | ".join(cells) + " |")
            if (
                cand != base
                and mean(sel | {"model": cand}, "psnr")
                < mean(sel | {"model": base}, "psnr") - MAX_PSNR_LOSS
            ):
                ok = False
                print(f"  {c}: {cand} loses more than {MAX_PSNR_LOSS} dB")
    if nr:
        print("\n### Real photos (NR-IQA at a long side of 1024 px)\n")
        print(
            "| Category | Effective resolution | "
            + " | ".join(
                f"{m} {k.upper()}" for m in dict.fromkeys([base, cand]) for k in NR_METRICS
            )
            + " | Verdict |"
        )
        print("|---|---|" + "---|" * (len(NR_METRICS) * len(dict.fromkeys([base, cand])) + 1))
        for c in sorted({r["category"] for r in rows if r["part"] == "real"}):
            for eff in (False, True):
                sel = {"part": "real", "category": c, "eff": eff}
                if not any(all(r[k] == x for k, x in sel.items()) for r in rows):
                    continue
                cells = [
                    f"{mean(sel | {'model': m}, k):.3f}"
                    for m in dict.fromkeys([base, cand])
                    for k in NR_METRICS
                ]
                wins = sum(
                    mean(sel | {"model": cand}, k) >= mean(sel | {"model": base}, k)
                    for k in NR_METRICS
                )
                verdict = "—" if cand == base else ("no worse" if wins >= 2 else "worse")
                print(
                    f"| {c} | {'yes' if eff else 'no'} | " + " | ".join(cells) + f" | {verdict} |"
                )
    print("\n### Seams (tile vs one tile, PSNR on luma)\n")
    for m in dict.fromkeys([base, cand]):
        for t in (128, 256):
            v = [s["psnr"] for s in seams if s["model"] == m and s["tile"] == t]
            lo = min(v) if v else float("nan")
            print(f"- {m}, tile {t}: min {lo:.1f} dB")
            if lo < MIN_SEAM_DB:
                ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
