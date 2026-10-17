#!/usr/bin/env python3
"""Spike S9 (1.1, old photos): converts MI-GAN 512 Places2 (Picsart-AI-Research/MI-GAN, MIT;
weights MIT, LICENSE-WEIGHTS) to ncnn fp16, the inpainting step after scratch detection.

  <venv>/bin/python tools/models/convert_migan.py OUT_DIR [--pnnx PATH]

Upstream publishes the weights as ONNX pipelines only (Hugging Face andraniksargsyan/migan:
uint8 image and mask of any size, crop and blend inside). The core crops and blends itself, so
the generator is cut out of migan.onnx: input (1, 4, 512, 512) = [mask - 0.5, image * mask]
with mask 1 known / 0 hole and image in [-1, 1]; output (1, 3, 512, 512) in [-1, 1]
(scripts/create_onnx_pipeline.py: preprocess / postprocess). Writes
OUT_DIR/old.inpaint-migan/{model.ncnn.param,model.ncnn.bin,model.json}, a golden pair (onnxruntime
fp32), and hole_report.json: PSNR inside and outside the holes on a seeded synthetic photo.
Needs onnx, onnxruntime, pnnx, numpy and Pillow (spikes/s1-gfpgan/requirements.lock).
"""
import argparse, hashlib, json, pathlib, subprocess, sys, urllib.request

import numpy as np
import onnx
import onnx.utils
import onnxruntime as ort
from PIL import Image, ImageDraw

REV = "406830d0fa60666da0071c342ad2fbc8f30c5c64"
ONNX_URL = f"https://huggingface.co/andraniksargsyan/migan/resolve/{REV}/migan.onnx"
ONNX_SHA = "593eba0b7e04730f1b61c0a3cbca68d97d8d6a7ff5c6a44a7b9d7fcd880fc5ae"
# Tensor names of the generator in that file: the concat of preprocess, and the last torgb add
# before postprocess's "* 0.5 + 0.5".
GEN_IN, GEN_OUT = "222", "1299"
RES = 512


def sha256(p: pathlib.Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fetch(url: str, dst: pathlib.Path, want: str) -> None:
    if not dst.exists():
        print(f"downloading {url}", flush=True)
        urllib.request.urlretrieve(url, dst)
    got = sha256(dst)
    print(f"  {dst.name} sha256 {got}")
    if got != want:
        sys.exit(f"{dst.name}: sha256 {got}, want {want}")


def photo_and_holes() -> tuple[np.ndarray, np.ndarray]:
    """A seeded synthetic photo in [0, 1] (RES x RES x 3) and a hole mask (1 known, 0 hole):
    thin strokes as dilated scratches would leave, and one blob."""
    rng = np.random.default_rng(20261017)
    y, x = np.mgrid[0:RES, 0:RES] / RES
    img = np.stack([0.5 + 0.3 * np.sin(6 * x + 2 * y), 0.35 + 0.4 * y, 0.6 - 0.4 * x], -1)
    img = np.clip(img + rng.normal(0, 0.02, img.shape), 0, 1)
    mask = Image.new("L", (RES, RES), 255)
    d = ImageDraw.Draw(mask)
    for _ in range(8):
        pts = [tuple(int(v) for v in rng.integers(0, RES, 2)) for _ in range(3)]
        d.line(pts, fill=0, width=int(rng.integers(4, 10)))
    d.ellipse((300, 300, 360, 350), fill=0)
    return img.astype(np.float32), (np.asarray(mask) > 127).astype(np.float32)


def gen_input(img: np.ndarray, mask: np.ndarray) -> np.ndarray:
    m = mask[None, None]
    x = img.transpose(2, 0, 1)[None] * 2 - 1
    return np.concatenate([m - 0.5, x * m], 1).astype(np.float32)


def psnr(a: np.ndarray, b: np.ndarray) -> float:
    mse = float(np.mean((a - b) ** 2))
    return 99.0 if mse == 0 else 10 * np.log10(1 / mse)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--pnnx", default="pnnx")
    a = ap.parse_args()
    out = pathlib.Path(a.out).resolve()
    dst = out / "old.inpaint-migan"
    work = out / "work"
    dst.mkdir(parents=True, exist_ok=True)
    work.mkdir(parents=True, exist_ok=True)

    full = work / "migan.onnx"
    fetch(ONNX_URL, full, ONNX_SHA)
    gen = work / "generator.onnx"
    onnx.utils.extract_model(str(full), str(gen), [GEN_IN], [GEN_OUT])
    sess = ort.InferenceSession(str(gen), providers=["CPUExecutionProvider"])
    run = lambda x: sess.run(None, {GEN_IN: x})[0]

    img, mask = photo_and_holes()
    x = gen_input(img, mask)
    y = run(x)
    assert y.shape == (1, 3, RES, RES), y.shape
    res = np.clip(y[0].transpose(1, 2, 0) * 0.5 + 0.5, 0, 1)
    hole = mask < 0.5
    report = {"hole_fraction": float(hole.mean()),
              "psnr_hole": psnr(res[hole], img[hole]),
              "psnr_known": psnr(res[~hole], img[~hole]),
              "psnr_hole_mean_fill": psnr(np.broadcast_to(img[~hole].mean(0), img[hole].shape),
                                          img[hole])}
    print("holes:", " ".join(f"{k} {v:.3f}" for k, v in report.items()))
    (dst / "hole_report.json").write_text(json.dumps(report, indent=2) + "\n")
    Image.fromarray((res * 255).astype(np.uint8)).save(dst / "hole_result.png")
    x.tofile(dst / f"golden_in_4x{RES}x{RES}.f32")
    y.astype(np.float32).tofile(dst / f"golden_out_3x{RES}x{RES}.f32")

    subprocess.run(
        [a.pnnx, str(gen), f"inputshape=[1,4,{RES},{RES}]", "fp16=1",
         f"ncnnparam={dst / 'model.ncnn.param'}", f"ncnnbin={dst / 'model.ncnn.bin'}",
         f"pnnxparam={work / 'gen.pnnx.param'}", f"pnnxbin={work / 'gen.pnnx.bin'}",
         f"pnnxpy={work / 'gen_pnnx.py'}", f"pnnxonnx={work / 'gen.pnnx.onnx'}",
         f"ncnnpy={work / 'gen_ncnn.py'}"],
        check=True, cwd=work, stdout=subprocess.DEVNULL)
    (dst / "model.json").write_text(json.dumps({"scale": 1, "size": RES}) + "\n")
    for f in sorted(dst.iterdir()):
        print(f"  old.inpaint-migan/{f.name} {f.stat().st_size} {sha256(f)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
