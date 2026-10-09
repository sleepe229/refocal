"""Compare every backend's outputs against the PyTorch fp32 reference of the ORIGINAL model.

Metrics on 8-bit RGB (as the app would save): PSNR (dB), max |diff|, LPIPS (AlexNet).
Thresholds from the spec (NFR-QLT-001): PSNR >= 40 dB (fp32), >= 35 dB (fp16), LPIPS <= 0.02.
Also writes a visual montage: input | reference | ncnn Vulkan fp16 (static) for a few faces.
"""
import json
from pathlib import Path

import cv2
import numpy as np
import torch

HERE = Path(__file__).resolve().parent
RESULTS = HERE / "out" / "results"
REF = "gfpgan14__torch_fp32"


def to_u8(x: np.ndarray) -> np.ndarray:
    """(N,3,H,W) in [-1,1] -> (N,H,W,3) uint8."""
    return np.clip((x.transpose(0, 2, 3, 1) + 1) * 127.5 + 0.5, 0, 255).astype(np.uint8)


def psnr(a: np.ndarray, b: np.ndarray) -> float:
    mse = np.mean((a.astype(np.float64) - b.astype(np.float64)) ** 2)
    return float("inf") if mse == 0 else 10 * np.log10(255.0 ** 2 / mse)


def main() -> None:
    import lpips
    lp = lpips.LPIPS(net="alex", verbose=False)

    ref = np.load(RESULTS / f"{REF}.npy")
    ref_u8 = to_u8(ref)
    rows = []
    for npy in sorted(RESULTS.glob("*.npy")):
        tag = npy.stem
        if tag == REF:
            continue
        out = np.load(npy)
        out_u8 = to_u8(np.nan_to_num(out))
        psnrs = [psnr(a, b) for a, b in zip(out_u8, ref_u8)]
        with torch.no_grad():
            d = lp(torch.from_numpy(np.nan_to_num(out)).clamp(-1, 1), torch.from_numpy(ref).clamp(-1, 1))
        stats = json.loads((RESULTS / f"{tag}.json").read_text())
        fp16 = tag.endswith("fp16")
        min_psnr, max_lpips = min(psnrs), float(d.max())
        ok = min_psnr >= (35 if fp16 else 40) and max_lpips <= 0.02 and stats["nan_or_inf"] == 0
        rows.append({
            "tag": tag, "psnr_min": round(min_psnr, 2), "psnr_mean": round(float(np.mean(psnrs)), 2),
            "maxabs_u8": int(np.abs(out_u8.astype(int) - ref_u8.astype(int)).max()),
            "lpips_max": round(max_lpips, 4), "median_s": stats["median_s"],
            "peak_rss_mb": stats["peak_rss_mb"], "nan": stats["nan_or_inf"], "pass": bool(ok),
        })

    hdr = f"{'model__backend':34} {'PSNRmin':>8} {'PSNRavg':>8} {'max|d|':>6} {'LPIPS':>7} {'sec':>7} {'RSS MB':>7} {'NaN':>4}  gate"
    print(hdr)
    for r in rows:
        print(f"{r['tag']:34} {r['psnr_min']:8.2f} {r['psnr_mean']:8.2f} {r['maxabs_u8']:6d} {r['lpips_max']:7.4f} "
              f"{r['median_s']:7.3f} {r['peak_rss_mb']:7.0f} {r['nan']:4d}  {'PASS' if r['pass'] else 'FAIL'}")
    (RESULTS / "summary.json").write_text(json.dumps(rows, indent=2))

    # Visual montage: input | reference | static ncnn Vulkan fp16
    faces = json.loads((RESULTS / f"{REF}.json").read_text())["faces"]
    cand = RESULTS / "gfpgan14s__ncnn_vk0_fp16.npy"
    if cand.exists():
        alt = to_u8(np.load(cand))
        pick = [i for i, f in enumerate(faces) if f.endswith("_lq.png")][:6]
        tiles = []
        for i in pick:
            inp = cv2.imread(str(HERE / "data" / "faces" / faces[i]))
            row = [inp, cv2.cvtColor(ref_u8[i], cv2.COLOR_RGB2BGR), cv2.cvtColor(alt[i], cv2.COLOR_RGB2BGR)]
            tiles.append(np.hstack([cv2.resize(t, (256, 256)) for t in row]))
        cv2.imwrite(str(HERE / "out" / "compare_montage.jpg"), np.vstack(tiles), [cv2.IMWRITE_JPEG_QUALITY, 88])


if __name__ == "__main__":
    main()
