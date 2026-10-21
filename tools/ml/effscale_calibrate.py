#!/usr/bin/env python3
"""Calibration of the effective-resolution thresholds tau_iso / tau_dir (ADR-0025).

  python3 tools/ml/effscale_calibrate.py --cli BUILD/refocal-cli --models MODELS_DIR WORK_DIR
         [--jobs 4]

Data: the 16 Kodak photos that jpeg_eval.py does not use (768x512, unrestricted usage; pinned
by SHA-256 below), each blurred 10 ways at full size (none; Gaussian sigma 1.5, 3, 5; disk
radius 3, 6, 10; motion 10, 20, 30 px at 20 degrees: effscale.kernel), area-downscaled by 2,
with Gaussian noise sigma 3 (seeded) and JPEG quality 70: the "photo". The oracle: each photo
goes through refocal-cli at 2x (the size of the original) with --pre-down f for f on a grid
from 1 to 0.25 (the built-in sr.general-x4v3); LPIPS against the original says which f gives
the best SR result. tau_iso / tau_dir are then the pair whose estimate (effscale.py on the
photo) has the lowest mean LPIPS, interpolated between the grid points.

Writes WORK_DIR/effscale_calibration.json and prints the fit and a table per blur. Needs numpy,
scipy, pillow, pyiqa and torch (LPIPS).
"""

import argparse
import io
import json
import pathlib
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from effscale import FACTORS, area, crossing, kernel, profiles
from jpeg_eval import fetch
from PIL import Image
from scipy import ndimage as ndi

CALIB = {
    "02": "4f4b74a79237e311d72cad958237b5f7088d8bce1c82305ebefe1a70e3022dfd",
    "06": "363510303b715d4cbc384e1ce227e466b613a09e1b71ae985882bf8e7fbd9b18",
    "08": "ba23983c76b4832ee0e8af0592664756841a16779acd69f792e268fb6d13d6e7",
    "09": "6a4361c2fc194feb4edaa9f9a4a0620fb9943e460ac7fdf037fb0f6dd6607a7d",
    "10": "9dfb70f5867c29ff9ed6313683f19b3d867849e40fbc0c4c54a4a89df341cf23",
    "11": "7936814b58b5387fce2e4e2488b4ec830dadd95fa9520f358ddb30990b50f2b6",
    "12": "d78c37c2f04f23761ed2367dd77e2db584ddd4c3950833fecf89f199a8126980",
    "13": "bc34a3ce58dea09dce1704c997171602de90cb34d0c8503a988b77f473d39b08",
    "14": "55a94550ff18f3246c4074fd32b77b0c74447c26b6ad274d564d999c0450ba6e",
    "16": "a89c7268ccd4718ba424a99fc4643c572cf692ca6eae887185ceb4e9f11d2e54",
    "17": "37afcc89fbdcb76d9518e04b2fc011027e2f4cd14b3b2f83cefd721641a47c5b",
    "18": "1a9258c365988961d87a0598725b609139c303ad48a5aad6c503c3b1a87849aa",
    "19": "b7450b264b1b0a411390d8931b112c27905a992520fc90569dc4b920aa32bbdc",
    "21": "ac958597c82073f6bb65129c68f72b651db5b9efd82e11547d07350214bc268b",
    "22": "1cee58eb1f2d9c7ebb254d208a03c783ce6cf2c4d8c2cf45e235dd23b4ce1b29",
    "24": "1071c68372cc5a01435c2c225a5cf7d4bb803846ec08bb6b3d6721b156d7cb96",
}
BLURS = [("none", 0), ("g", 1.5), ("g", 3), ("g", 5), ("d", 3), ("d", 6), ("d", 10)]
BLURS += [("m", 10), ("m", 20), ("m", 30)]
GRID = [1.0, 0.85, 0.7, 0.6, 0.5, 0.42, 0.35, 0.3, 0.25]


def degrade(src: pathlib.Path, kind: str, p: float, seed: int) -> np.ndarray:
    """The original blurred, area /2, noise sigma 3, JPEG 70 -> RGB8."""
    a = np.asarray(Image.open(src).convert("RGB"), np.float64)
    if kind != "none":
        k = kernel(kind, p)
        a = np.stack([ndi.correlate(a[..., c], k, mode="reflect") for c in range(3)], -1)
    a = np.stack([area(a[..., c], 0.5) for c in range(3)], -1)
    a = a + np.random.default_rng(seed).normal(0, 3, a.shape)
    b = io.BytesIO()
    Image.fromarray(np.floor(np.clip(a, 0, 255) + 0.5).astype(np.uint8)).save(b, "JPEG", quality=70)
    return np.asarray(Image.open(b).convert("RGB"))


def run(cli: str, models: str, work: pathlib.Path, src: pathlib.Path, f: float) -> pathlib.Path:
    out = work / "out" / f"{src.stem}_f{f:.2f}.png"
    if out.exists():
        return out
    cmd = [cli, "run", "--models", models, "--work", str(work / "jobs"), "--input", str(src)]
    cmd += ["--out", str(out), "--scale", "2", "--backend", "cpu", "--threads", "2"]
    cmd += ["--no-exif", "--no-ai-marker", "--job-id", out.stem.replace(".", "_")]
    if f < 1:
        cmd += ["--pre-down", f"{f}"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"{' '.join(cmd)}\n{r.stderr}")
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("work")
    ap.add_argument("--cli", required=True)
    ap.add_argument("--models", required=True)
    ap.add_argument("--jobs", type=int, default=4)
    a = ap.parse_args()
    work = pathlib.Path(a.work)
    for d in ("src", "lr", "out", "jobs"):
        (work / d).mkdir(parents=True, exist_ok=True)
    import pyiqa
    import torch

    dev = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    lpips = pyiqa.create_metric("lpips", device=dev)

    cases = []
    for name, sha in CALIB.items():
        src = fetch(name, sha, work / "src" / f"kodim{name}.png")
        for i, (kind, p) in enumerate(BLURS):
            lr = work / "lr" / f"k{name}_{kind}{p:g}.png"
            if not lr.exists():
                Image.fromarray(degrade(src, kind, p, int(name) * 31 + i)).save(lr)
            cases.append((name, f"{kind}{p:g}", src, lr))
    with ThreadPoolExecutor(a.jobs) as ex:
        outs = ex.map(
            lambda c: [run(a.cli, a.models, work, c[1], f) for f in GRID],
            [(c[0], c[3]) for c in cases],
        )
        outs = list(outs)
    rows = []
    for (name, blur, src, lr), paths in zip(cases, outs, strict=True):
        gt = str(src)
        scores = [float(lpips(str(p), gt).item()) for p in paths]
        iso, wd = profiles(np.asarray(Image.open(lr).convert("RGB")))
        rows.append({"image": name, "blur": blur, "lpips": scores, "iso": iso, "dir": wd})
        print(
            json.dumps({"image": name, "blur": blur, "oracle_f": GRID[int(np.argmin(scores))]}),
            flush=True,
        )

    def mean_lpips(ti: float, td: float, rs=rows) -> float:
        g = np.array(GRID[::-1])
        return float(
            np.mean(
                [
                    np.interp(
                        np.sqrt(crossing(r["iso"], ti) * crossing(r["dir"], td)),
                        g,
                        r["lpips"][::-1],
                    )
                    for r in rs
                ]
            )
        )

    fits = [
        (mean_lpips(ti, td), round(ti, 2), round(td, 2))
        for ti in np.arange(0.26, 0.405, 0.01)
        for td in np.arange(0.24, 0.365, 0.01)
    ]
    best, ti, td = min(fits)
    oracle = np.mean([min(r["lpips"]) for r in rows])
    plain = np.mean([r["lpips"][0] for r in rows])
    print(
        f"\ntau_iso {ti:.2f}, tau_dir {td:.2f}: LPIPS {best:.4f} (f = 1: {plain:.4f}, "
        f"oracle {oracle:.4f})"
    )
    print("\n| Blur | eff (median) | oracle f (median) | LPIPS f = 1 | at eff | oracle |")
    print("|---|---|---|---|---|---|")
    g = np.array(GRID[::-1])
    for blur in dict.fromkeys(r["blur"] for r in rows):
        rs = [r for r in rows if r["blur"] == blur]
        eff = [np.sqrt(crossing(r["iso"], ti) * crossing(r["dir"], td)) for r in rs]
        at = [np.interp(e, g, r["lpips"][::-1]) for e, r in zip(eff, rs, strict=True)]
        print(
            f"| {blur} | {np.median(eff):.2f} | "
            f"{np.median([GRID[int(np.argmin(r['lpips']))] for r in rs]):.2f} | "
            f"{np.mean([r['lpips'][0] for r in rs]):.3f} | {np.mean(at):.3f} | "
            f"{np.mean([min(r['lpips']) for r in rs]):.3f} |"
        )
    (work / "effscale_calibration.json").write_text(
        json.dumps(
            {"tau_iso": ti, "tau_dir": td, "grid": GRID, "factors": FACTORS, "rows": rows}, indent=1
        )
    )


if __name__ == "__main__":
    main()
