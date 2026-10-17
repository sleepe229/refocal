#!/usr/bin/env python3
"""The "old" golden category (S9, 04 §7.2): how much scratch removal (old.scratch +
old.inpaint-migan) adds to the plain pipeline on aged prints.

  python3 tools/ml/old_eval.py --cli BUILD/refocal-cli --models MODELS_DIR WORK_DIR [--no-iqa]

Data: the Kodak photos of jpeg_eval.py, aged the same seeded way each: sepia-toned grey, a
little blur and film grain (the reference: the aged print without damage), then scratches
(bright and dark, 1-3 px, slightly bent) and dust. Each goes through refocal-cli at scale 1
twice: plain, and with --scratch-model old.scratch. Both are compared with the undamaged aged
print by PSNR / SSIM (luma) over the whole photo and PSNR inside the damage, and scored
without a reference by MUSIQ (pyiqa; --no-iqa skips it). Exit: NR-IQA of the scratch removal
>= the plain pipeline (S9).

Writes WORK_DIR/old.json and prints a Markdown table. Needs numpy, pillow (pyiqa, torch).
"""
import argparse, json, pathlib, sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from jpeg_eval import IMAGES, fetch, luma, psnr, run, ssim


def age(src: pathlib.Path, seed: int) -> tuple[Image.Image, Image.Image, np.ndarray]:
    """(aged print, the same with scratches and dust, the damage mask)."""
    rng = np.random.default_rng(seed)
    grey = np.asarray(Image.open(src).convert("L").filter(ImageFilter.GaussianBlur(0.8)),
                      np.float32) / 255
    grey = np.clip(0.08 + 0.84 * grey + rng.normal(0, 0.025, grey.shape), 0, 1)
    tone = np.array([1.0, 0.86, 0.68], np.float32)  # sepia
    aged = Image.fromarray((np.clip(grey[..., None] * tone + [0.04, 0.03, 0.02], 0, 1) * 255)
                           .astype(np.uint8))
    h, w = grey.shape
    damaged = aged.copy()
    mask = Image.new("L", (w, h), 0)
    dd, dm = ImageDraw.Draw(damaged), ImageDraw.Draw(mask)
    for i in range(12):
        pts = [(int(rng.integers(0, w)), int(rng.integers(0, h)))]
        for _ in range(3):
            pts.append((int(np.clip(pts[-1][0] + rng.integers(-150, 150), 0, w - 1)),
                        int(np.clip(pts[-1][1] + rng.integers(-150, 150), 0, h - 1))))
        width = int(rng.integers(1, 4))
        colour = (235, 230, 220) if i % 3 else (30, 25, 20)
        dd.line(pts, fill=colour, width=width)
        dm.line(pts, fill=255, width=width)
    for _ in range(40):  # dust
        x, y, r = int(rng.integers(0, w)), int(rng.integers(0, h)), int(rng.integers(1, 4))
        dd.ellipse((x - r, y - r, x + r, y + r), fill=(240, 236, 228))
        dm.ellipse((x - r, y - r, x + r, y + r), fill=255)
    return aged, damaged, np.asarray(mask) > 0


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("work")
    ap.add_argument("--cli", required=True)
    ap.add_argument("--models", required=True)
    ap.add_argument("--no-iqa", action="store_true")
    a = ap.parse_args()
    work = pathlib.Path(a.work)
    for d in ("src", "aged", "out", "jobs"):
        (work / d).mkdir(parents=True, exist_ok=True)
    iqa = None
    if not a.no_iqa:
        import pyiqa, torch
        iqa = pyiqa.create_metric("musiq", device=torch.device("cpu"))

    rows = []
    for k, (name, sha) in enumerate(IMAGES.items()):
        src = fetch(name, sha, work / "src" / f"kodim{name}.png")
        aged, damaged, mask = age(src, 20261017 + k)
        ref_p = work / "aged" / f"kodim{name}_ref.png"
        dmg_p = work / "aged" / f"kodim{name}_damaged.png"
        aged.save(ref_p)
        damaged.save(dmg_p)
        ref = luma(ref_p)
        row = {"image": name, "damage": float(mask.mean())}
        for kind, path, extra in [
                ("input", dmg_p, None),
                ("plain", work / "out" / f"kodim{name}_plain.png", []),
                ("scratches", work / "out" / f"kodim{name}_scratches.png",
                 ["--scratch-model", "old.scratch"])]:
            if extra is not None:
                row[f"{kind}_s"] = run(a.cli, a.models, work, dmg_p, path, extra)
            y = luma(path)
            row[f"{kind}_psnr"], row[f"{kind}_ssim"] = psnr(ref, y), ssim(ref, y)
            row[f"{kind}_psnr_damage"] = psnr(ref[mask], y[mask])
            if iqa is not None:
                row[f"{kind}_musiq"] = float(iqa(str(path)).item())
        rows.append(row)
        print(json.dumps(row), flush=True)

    (work / "old.json").write_text(json.dumps(rows, indent=1))
    kinds = ["input", "plain", "scratches"]
    metrics = ["psnr", "psnr_damage", "ssim"] + ([] if iqa is None else ["musiq"])
    mean = lambda key: sum(r[key] for r in rows) / len(rows)
    print("\n| Metric | " + " | ".join(kinds) + " |")
    print("|---" * (1 + len(kinds)) + "|")
    for m in metrics:
        fmt = "{:.3f}" if m == "ssim" else "{:.2f}"
        print(f"| {m} | " + " | ".join(fmt.format(mean(f"{k}_{m}")) for k in kinds) + " |")
    print(f"| s | - | {mean('plain_s'):.1f} | {mean('scratches_s'):.1f} |")
    print(f"\ndamage: {100 * mean('damage'):.2f}% of the photo")
    if iqa is not None and mean("scratches_musiq") < mean("plain_musiq"):
        sys.exit("NR-IQA of the scratch removal is below the plain pipeline")


if __name__ == "__main__":
    main()
