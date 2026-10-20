"""Seam metrics: PSNR vs whole-image pass and NFR-QLT-003 boundary-gradient ratio.

For each tiled output O (x4, uint8) and the whole-image reference R:
  * PSNR(O, R) and max |O - R| over the image and within +-2 px of seams.
  * Column gradient g(x) = mean_{rows,ch} |O[:, x] - O[:, x-1]| (and the same for rows).
    ratio_global = max over seams of g(seam) / mean of g over non-seam positions
    (NFR-QLT-003 literal: "max boundary gradient <= 1.5x mean inside").
    ratio_local  = max over seams of g(seam) / mean g in a +-8 px window around it.
  The same ratios are computed on R at the same positions (content baseline): a seam
  shows up as ratio(O) > ratio(R).
  * diff_ratio: seam gradient of the error image D = O - R relative to its interior mean
    (independent of content).
"""

import glob
import json
import os
import sys

import cv2
import numpy as np

d = sys.argv[1]
ref = cv2.imread(os.path.join(d, "whole.png"), cv2.IMREAD_UNCHANGED).astype(np.float64)


def grads(img, axis):
    # mean absolute difference across `axis` boundaries; g[i] = |img[i] - img[i-1]|
    diff = np.abs(np.diff(img, axis=axis))
    other = tuple(a for a in range(img.ndim) if a != axis)
    g = diff.mean(axis=other)
    return np.concatenate([[np.nan], g])  # index i = boundary between i-1 and i


def ratios(g, seams):
    if not seams:
        return float("nan"), float("nan")
    mask = np.ones(len(g), bool)
    mask[0] = False
    for s in seams:
        mask[max(0, s - 2) : s + 3] = False
    inside = np.nanmean(g[mask])
    rg = max(g[s] for s in seams) / inside
    rl = []
    for s in seams:
        win = [i for i in range(s - 8, s + 9) if 0 < i < len(g) and abs(i - s) > 2]
        rl.append(g[s] / np.mean(g[win]))
    return rg, max(rl)


print(
    f"{'run':16s} {'PSNR':>7s} {'PSNRin':>7s} {'maxdin':>6s} {'p999@s':>6s} {'maxd':>5s} "
    f"{'maxd@seam':>9s} {'rG(O)':>6s} {'rG(R)':>6s} "
    f"{'rL(O)':>6s} {'rL(R)':>6s} {'diffR':>7s}"
)
rows = []
for f in sorted(glob.glob(os.path.join(d, "t*.json"))):
    name = os.path.basename(f)[:-5]
    st = json.load(open(f))
    o = cv2.imread(os.path.join(d, name + ".png"), cv2.IMREAD_UNCHANGED).astype(np.float64)
    diff = o - ref
    mse = (diff**2).mean()
    psnr = 10 * np.log10(255**2 / mse) if mse > 0 else float("inf")
    sx, sy = st["seams_x"], st["seams_y"]
    near = np.zeros(o.shape[:2], bool)
    for s in sx:
        near[:, max(0, s - 2) : s + 2] = True
    for s in sy:
        near[max(0, s - 2) : s + 2, :] = True
    maxd = np.abs(diff).max()
    B = 128  # exclude image border (whole pass uses zero conv padding, tiles use reflect)
    di = diff[B:-B, B:-B]
    psnr_in = 10 * np.log10(255**2 / (di**2).mean())
    maxd_in = np.abs(di).max()
    p99_seam = 0.0
    maxd_seam = np.abs(diff)[near].max() if near.any() else 0
    p99_seam = np.percentile(np.abs(diff)[near], 99.9) if near.any() else 0
    res = {}
    for tag, img in (("O", o), ("R", ref)):
        gx, gy = grads(img, 1), grads(img, 0)
        rgx, rlx = ratios(gx, sx)
        rgy, rly = ratios(gy, sy)
        res[tag] = (max(rgx, rgy), max(rlx, rly))
    dx, dy = grads(diff, 1), grads(diff, 0)
    dr = max(ratios(dx, sx)[0], ratios(dy, sy)[0])
    rows.append(
        dict(
            run=name,
            psnr=psnr,
            psnr_interior=psnr_in,
            maxd_interior=maxd_in,
            p999_seam=p99_seam,
            maxd=maxd,
            maxd_seam=maxd_seam,
            rG_O=res["O"][0],
            rG_R=res["R"][0],
            rL_O=res["O"][1],
            rL_R=res["R"][1],
            diff_ratio=dr,
        )
    )
    print(
        f"{name:16s} {psnr:7.2f} {psnr_in:7.2f} {maxd_in:6.0f} {p99_seam:6.1f} {maxd:5.0f} "
        f"{maxd_seam:9.0f} {res['O'][0]:6.2f} {res['R'][0]:6.2f} "
        f"{res['O'][1]:6.2f} {res['R'][1]:6.2f} {dr:7.2f}"
    )
json.dump(rows, open(os.path.join(d, "summary.json"), "w"), indent=1)
