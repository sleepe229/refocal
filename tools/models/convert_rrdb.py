#!/usr/bin/env python3
"""Converts the Real-ESRGAN RRDBNet models (04-ml-models: sr.x4plus, sr.x4plus-anime6b) to ncnn
fp16 packs, and checks each against its PyTorch fp32 output.

  <venv>/bin/python tools/models/convert_rrdb.py OUT_DIR [--pnnx PATH]

For each model: downloads the upstream weights (SHA-256 pinned below), traces RRDBNet
(re-implemented from BasicSR/Real-ESRGAN, BSD-3-Clause, xinntao), converts with pnnx
(fp16 weights), writes OUT_DIR/<id>/{model.ncnn.param, model.ncnn.bin, model.json} and the
golden pair OUT_DIR/<id>/golden_{in_3x96x96,out_3x384x384}.f32 (a fixed tile and its fp32
output) for test_golden. The ncnn side is checked there, with the core (TEST-ML-001).
Needs torch and pnnx (spikes/s1-gfpgan/requirements.lock).
"""
import argparse, hashlib, json, pathlib, subprocess, sys, urllib.request

import numpy as np
import torch
from torch import nn
from torch.nn import functional as F

MODELS = {
    "sr.x4plus": {
        "url": "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth",
        "sha256": "4fa0d38905f75ac06eb49a7951b426670021be3018265fd191d2125df9d682f1",
        "blocks": 23,
        "pad": 24,  # 04 §4: x4plus needs a wider context than the compact model
    },
    "sr.x4plus-anime6b": {
        "url": "https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.2.4/RealESRGAN_x4plus_anime_6B.pth",
        "sha256": "f872d837d3c90ed2e05227bed711af5671a6fd1c9f7d7e91c911a61f155e99da",
        "blocks": 6,
        "pad": 16,
    },
}
GOLDEN_IN = 96  # a tile big enough to need the pad on every side, small enough for CI


class ResidualDenseBlock(nn.Module):
    def __init__(self, nf=64, gc=32):
        super().__init__()
        self.conv1 = nn.Conv2d(nf, gc, 3, 1, 1)
        self.conv2 = nn.Conv2d(nf + gc, gc, 3, 1, 1)
        self.conv3 = nn.Conv2d(nf + 2 * gc, gc, 3, 1, 1)
        self.conv4 = nn.Conv2d(nf + 3 * gc, gc, 3, 1, 1)
        self.conv5 = nn.Conv2d(nf + 4 * gc, nf, 3, 1, 1)
        self.lrelu = nn.LeakyReLU(negative_slope=0.2, inplace=True)

    def forward(self, x):
        x1 = self.lrelu(self.conv1(x))
        x2 = self.lrelu(self.conv2(torch.cat((x, x1), 1)))
        x3 = self.lrelu(self.conv3(torch.cat((x, x1, x2), 1)))
        x4 = self.lrelu(self.conv4(torch.cat((x, x1, x2, x3), 1)))
        x5 = self.conv5(torch.cat((x, x1, x2, x3, x4), 1))
        return x5 * 0.2 + x


class RRDB(nn.Module):
    def __init__(self, nf, gc=32):
        super().__init__()
        self.rdb1 = ResidualDenseBlock(nf, gc)
        self.rdb2 = ResidualDenseBlock(nf, gc)
        self.rdb3 = ResidualDenseBlock(nf, gc)

    def forward(self, x):
        out = self.rdb3(self.rdb2(self.rdb1(x)))
        return out * 0.2 + x


class RRDBNet(nn.Module):
    """x4 RRDBNet as in BasicSR (scale 4: no pixel unshuffle)."""

    def __init__(self, num_block, nf=64, gc=32):
        super().__init__()
        self.conv_first = nn.Conv2d(3, nf, 3, 1, 1)
        self.body = nn.Sequential(*[RRDB(nf, gc) for _ in range(num_block)])
        self.conv_body = nn.Conv2d(nf, nf, 3, 1, 1)
        self.conv_up1 = nn.Conv2d(nf, nf, 3, 1, 1)
        self.conv_up2 = nn.Conv2d(nf, nf, 3, 1, 1)
        self.conv_hr = nn.Conv2d(nf, nf, 3, 1, 1)
        self.conv_last = nn.Conv2d(nf, 3, 3, 1, 1)
        self.lrelu = nn.LeakyReLU(negative_slope=0.2, inplace=True)

    def forward(self, x):
        feat = self.conv_first(x)
        feat = feat + self.conv_body(self.body(feat))
        feat = self.lrelu(self.conv_up1(F.interpolate(feat, scale_factor=2, mode="nearest")))
        feat = self.lrelu(self.conv_up2(F.interpolate(feat, scale_factor=2, mode="nearest")))
        return self.conv_last(self.lrelu(self.conv_hr(feat)))


def sha256(p: pathlib.Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fetch(url: str, dst: pathlib.Path, want: str) -> None:
    if not dst.exists() or sha256(dst) != want:
        print(f"downloading {url}")
        urllib.request.urlretrieve(url, dst)
    got = sha256(dst)
    if got != want:
        sys.exit(f"{dst.name}: sha256 {got}, want {want}")


def golden_tile() -> np.ndarray:
    """A fixed natural-looking tile: smooth gradients, edges and fine texture, seeded."""
    rng = np.random.default_rng(20261016)
    y, x = np.mgrid[0:GOLDEN_IN, 0:GOLDEN_IN] / GOLDEN_IN
    base = np.stack([0.5 + 0.4 * np.sin(6 * x + 2 * y), 0.4 + 0.3 * y, 0.6 - 0.4 * x])
    base[:, 40:56, :] = base[:, 40:56, :] * 0.3  # a dark band: hard edges
    base += rng.normal(0, 0.03, base.shape)
    return np.clip(base, 0, 1).astype(np.float32)


def convert(mid: str, spec: dict, out: pathlib.Path, pnnx: str, work: pathlib.Path) -> None:
    dst = out / mid
    dst.mkdir(parents=True, exist_ok=True)
    pth = work / pathlib.Path(spec["url"]).name
    fetch(spec["url"], pth, spec["sha256"])
    state = torch.load(pth, map_location="cpu", weights_only=True)
    state = state.get("params_ema", state.get("params", state))
    m = RRDBNet(spec["blocks"])
    m.load_state_dict(state, strict=True)
    m.eval()

    tile = golden_tile()
    with torch.no_grad():
        ref = m(torch.from_numpy(tile)[None])[0].numpy()
    tile.tofile(dst / f"golden_in_3x{GOLDEN_IN}x{GOLDEN_IN}.f32")
    ref.astype(np.float32).tofile(dst / f"golden_out_3x{4 * GOLDEN_IN}x{4 * GOLDEN_IN}.f32")

    ts = work / f"{mid}.pt"
    with torch.no_grad():
        torch.jit.trace(m, torch.rand(1, 3, 128, 128)).save(str(ts))
    # Dynamic spatial size (tiles of any size), fp16 weights for the pack (04 §6).
    subprocess.run(
        [pnnx, str(ts), "inputshape=[1,3,128,128]", "inputshape2=[1,3,192,192]", "fp16=1",
         f"ncnnparam={dst / 'model.ncnn.param'}", f"ncnnbin={dst / 'model.ncnn.bin'}",
         f"pnnxparam={work / (mid + '.pnnx.param')}", f"pnnxbin={work / (mid + '.pnnx.bin')}",
         f"pnnxpy={work / (mid + '_pnnx.py')}", f"pnnxonnx={work / (mid + '.pnnx.onnx')}",
         f"ncnnpy={work / (mid + '_ncnn.py')}"],
        check=True, cwd=work, stdout=subprocess.DEVNULL)
    param = (dst / "model.ncnn.param").read_text()
    if " in0 " not in param or " out0" not in param:
        sys.exit(f"{mid}: unexpected blob names in the ncnn graph")
    (dst / "model.json").write_text(json.dumps({"scale": 4, "pad": spec["pad"]}) + "\n")
    for f in sorted(dst.iterdir()):
        print(f"  {mid}/{f.name} {f.stat().st_size} {sha256(f)}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--pnnx", default="pnnx")
    ap.add_argument("--only", choices=sorted(MODELS))
    a = ap.parse_args()
    out = pathlib.Path(a.out).resolve()
    work = out / "_work"
    work.mkdir(parents=True, exist_ok=True)
    for mid, spec in MODELS.items():
        if a.only and a.only != mid:
            continue
        convert(mid, spec, out, a.pnnx, work)
    return 0


if __name__ == "__main__":
    sys.exit(main())
