#!/usr/bin/env python3
"""Effective resolution of a photo (ADR-0025): the reference of the core's estimate_eff_scale
(native/core/src/policy/analyze.cpp), on the whole image (the core measures the 16 tiles of
most contrast and takes its percentiles from histograms).

  python3 tools/ml/effscale.py PHOTO...       # eff_scale of each photo
  python3 tools/ml/effscale.py --test-scene   # the references of test_eff_scale (test_pipeline)

An edge blurred over b px has |grad| / local range ~ 1/b; an area downscale by f narrows it to
max(b f, ~1) px, so the steepness rises as f falls and levels off once the edge is about 1 px
wide. For f in FACTORS: the median steepness (|Sobel| / 8 over the 5x5 max - min, where that
range > MIN_RANGE) of the top EDGE_FRAC of edges by gradient, isotropic and the worst of 4
gradient orientations; for each, the largest f whose steepness reaches its tau (interpolated in
log f); the result is the geometric mean of the two. tau: tools/ml/effscale_calibrate.py.

--test-scene builds the scene and the blur kernels of test_eff_scale as the C++ test does and
prints its reference table. Needs numpy, scipy, pillow.
"""

import argparse
import sys

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

FACTORS = (1.0, 0.7, 0.5, 0.35, 0.25)
MIN_RANGE = 0.06  # local contrast an edge needs (luma 0..1)
EDGE_FRAC = 0.02  # the strongest edges: top 2% by gradient
TAU_ISO, TAU_DIR = 0.30, 0.32  # effscale_calibrate.py (ADR-0025)


def luma01(rgb8: np.ndarray) -> np.ndarray:
    """BT.601 luma, 0..1 (image/ops.hpp luma01)."""
    a = rgb8.astype(np.float32)
    return (0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]) / 255


def area_taps(m: int, n: int) -> np.ndarray:
    """n x m weights of an area resample: each output pixel the mean of the source it covers."""
    w = np.zeros((n, m))
    s = m / n
    for i in range(n):
        a, b = i * s, (i + 1) * s
        for k in range(int(a), min(m, int(np.ceil(b)))):
            w[i, k] = max(0.0, min(b, k + 1) - max(a, k)) / s
    return w


def area(y: np.ndarray, f: float) -> np.ndarray:
    """Area downscale of a plane by f (sides rounded half up, at least 8 px)."""
    if f >= 1:
        return y
    h, w = y.shape
    nh, nw = max(8, int(np.floor(h * f + 0.5))), max(8, int(np.floor(w * f + 0.5)))
    return (area_taps(h, nh) @ y.astype(np.float64) @ area_taps(w, nw).T).astype(np.float32)


def steepness(y: np.ndarray) -> tuple[float, float]:
    """(isotropic, worst orientation) median steepness of the strongest edges; NaN if too few.
    Borders: half-sample symmetric reflection (scipy.ndimage mode "reflect")."""
    gx = ndi.sobel(y, 1, mode="reflect") / 8
    gy = ndi.sobel(y, 0, mode="reflect") / 8
    g = np.hypot(gx, gy)
    r = ndi.maximum_filter(y, 5, mode="reflect") - ndi.minimum_filter(y, 5, mode="reflect")
    m = r > MIN_RANGE
    if m.sum() < 200:
        return np.nan, np.nan
    gm, rm = g[m], r[m]

    def med_top(sel: np.ndarray) -> float:
        if sel.sum() < 50:
            return np.nan
        gg, rr = gm[sel], rm[sel]
        top = gg >= np.quantile(gg, 1 - EDGE_FRAC)
        return float(np.median(gg[top] / rr[top]))

    ang = np.mod(np.arctan2(gy[m], gx[m]), np.pi)
    b = np.floor((ang + np.pi / 8) / (np.pi / 4)).astype(int) % 4
    dirs = [v for v in (med_top(b == i) for i in range(4)) if not np.isnan(v)]
    return med_top(np.ones_like(gm, bool)), (min(dirs) if dirs else np.nan)


def profiles(rgb8: np.ndarray) -> tuple[list[float], list[float]]:
    """Isotropic and worst-orientation steepness at each of FACTORS."""
    y = luma01(rgb8)
    st = [steepness(area(y, f)) for f in FACTORS]
    return [s[0] for s in st], [s[1] for s in st]


def crossing(prof: list[float], tau: float) -> float:
    """The largest factor whose steepness reaches tau, interpolated in log f; 1 without edges."""
    if all(np.isnan(v) for v in prof):
        return 1.0
    for i, v in enumerate(prof):
        if np.isnan(v) or v < tau:
            continue
        if i == 0:
            return 1.0
        f0, v0 = FACTORS[i - 1], prof[i - 1]
        t = (tau - v0) / max(v - v0, 1e-6)
        return float(np.exp(np.log(f0) + t * (np.log(FACTORS[i]) - np.log(f0))))
    return FACTORS[-1]


def eff_scale(rgb8: np.ndarray, tau_iso: float = TAU_ISO, tau_dir: float = TAU_DIR) -> float:
    iso, wd = profiles(rgb8)
    return float(np.sqrt(crossing(iso, tau_iso) * crossing(wd, tau_dir)))


# ---- the scene and kernels of test_eff_scale (native/tests/test_pipeline.cpp) ----


def edge_scene(w: int, h: int, seed: int) -> np.ndarray:
    """Shaded background, rectangles, discs and thin bars (the C++ edge_scene, same LCG)."""
    img = np.zeros((h, w, 3), np.uint8)
    xs, ys = np.meshgrid(np.arange(w), np.arange(h))
    img[..., 0] = 60 + xs * 80 // w
    img[..., 1] = 70 + ys * 60 // h
    img[..., 2] = 90
    r = seed

    def rnd(n: int) -> int:
        nonlocal r
        r = (r * 1664525 + 1013904223) & 0xFFFFFFFF
        return (r >> 8) % n

    for _ in range(90):
        kind, cx, cy = rnd(3), rnd(w), rnd(h)
        a, b = 4 + rnd(w // 8), 4 + rnd(h // 8)
        c = (rnd(256), rnd(256), rnd(256))
        y0, y1, x0, x1 = max(0, cy - b), min(h, cy + b), max(0, cx - a), min(w, cx + a)
        if y0 >= y1 or x0 >= x1:
            continue
        dx = (xs[y0:y1, x0:x1] - cx) / a
        dy = (ys[y0:y1, x0:x1] - cy) / b
        inside = (
            np.ones_like(dx, bool)
            if kind == 0
            else (dx * dx + dy * dy <= 1 if kind == 1 else np.abs(dy) < 0.15)
        )
        img[y0:y1, x0:x1][inside] = c
    return img


def kernel(kind: str, p: float) -> np.ndarray:
    """Gaussian sigma ('g'), disk radius ('d', 8x supersampled), motion length at 20 degrees
    ('m', bilinear along the line): the kernels of the C++ test and of the calibration."""
    if kind == "g":
        rad = int(np.ceil(3 * p))
        x = np.arange(-rad, rad + 1)
        k = np.exp(-(x[None] ** 2 + x[:, None] ** 2) / (2 * p * p))
        return k / k.sum()
    rad = int(np.ceil(p if kind == "d" else p / 2)) + 1
    n = 2 * rad + 1
    k = np.zeros((n, n))
    if kind == "d":
        ss = 8
        f = (np.arange(n * ss) + 0.5) / ss - 0.5 - rad
        inside = (f[None] ** 2 + f[:, None] ** 2) <= p * p
        k = inside.reshape(n, ss, n, ss).sum((1, 3)).astype(np.float64)
    else:
        a = np.deg2rad(20)
        steps = int(p * 8) + 1
        for i in range(steps):
            t = -p / 2 + p * i / (steps - 1)
            x, y = rad + t * np.cos(a), rad + t * np.sin(a)
            x0, y0 = int(np.floor(x)), int(np.floor(y))
            fx, fy = x - x0, y - y0
            for d, wt in enumerate(((1 - fx) * (1 - fy), fx * (1 - fy), (1 - fx) * fy, fx * fy)):
                xx, yy = x0 + d % 2, y0 + d // 2
                if 0 <= xx < n and 0 <= yy < n:
                    k[yy, xx] += wt
    return k / k.sum()


def blurred(rgb8: np.ndarray, kind: str, p: float) -> np.ndarray:
    """RGB8 blurred by kernel(kind, p), reflected borders, rounded to 8 bits."""
    if p == 0:
        return rgb8
    k = kernel(kind, p)
    a = rgb8.astype(np.float64)
    out = np.stack([ndi.correlate(a[..., c], k, mode="reflect") for c in range(3)], -1)
    return np.floor(np.clip(out, 0, 255) + 0.5).astype(np.uint8)


TEST_CASES = [("g", 0), ("g", 1.5), ("g", 3), ("g", 5), ("d", 3), ("d", 6), ("d", 10)]
TEST_CASES += [("m", 5), ("m", 10), ("m", 20), ("m", 30)]


def test_scene_table() -> dict[str, float]:
    scene = edge_scene(512, 512, 2026)
    return {f"{k}{p:g}": eff_scale(blurred(scene, k, p)) for k, p in TEST_CASES}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("photos", nargs="*")
    ap.add_argument("--test-scene", action="store_true")
    a = ap.parse_args()
    if a.test_scene:
        for k, v in test_scene_table().items():
            print(f"{k:5s} {v:.3f}")
    elif a.photos:
        for p in a.photos:
            print(f"{p}: {eff_scale(np.asarray(Image.open(p).convert('RGB'))):.4f}")
    else:
        sys.exit(ap.format_usage())


if __name__ == "__main__":
    main()
