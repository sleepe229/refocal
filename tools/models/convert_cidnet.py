#!/usr/bin/env python3
"""Spike S9 (1.1, old photos / low light): converts HVI-CIDNet (Fediory/HVI-CIDNet, MIT; the
"Generalization" weights on Hugging Face, MIT) to ncnn fp16, and measures whether it can run on a
downscaled photo.

  <venv>/bin/python tools/models/convert_cidnet.py OUT_DIR [--pnnx PATH]

CIDNet works in its HVI colour space: RGB -> HVI (a per-pixel transform with a learnt density
k), the network adds a correction, HVI -> RGB. The transforms index with boolean masks, which
ncnn has no layer for, so the graph is the network alone: HVI in, corrected HVI out (always
384 x 384, see SIZE: the photo reflect-padded); the core does both transforms (k is in
model.json). Its attention is over channels with the whole image as the sequence, so tiles
would each see other statistics and
the seams would show: the core runs it once on the photo scaled to at most 384 px and adds the
correction, upsampled, to the full-size HVI. low_report.json measures that against the
network on the full image, on a seeded synthetic dark photo. Writes
OUT_DIR/old.lowlight-cidnet/{model.ncnn.param,model.ncnn.bin,model.json} and a golden pair.
Needs torch, pnnx, numpy and Pillow (spikes/s1-gfpgan/requirements.lock).
"""

import argparse
import hashlib
import json
import pathlib
import subprocess
import sys
import urllib.request

import numpy as np
import torch
import torch.nn.functional as F

COMMIT = "eb43d7d91e9a336c66856824ff9e4603ae41f408"
RAW = f"https://raw.githubusercontent.com/Fediory/HVI-CIDNet/{COMMIT}/net"
HF_REV = "51481ef2546f870060c43eb6d6525399f5b3d2d3"
WEIGHTS = (
    f"https://huggingface.co/Fediory/HVI-CIDNet-Generalization/resolve/{HF_REV}/pytorch_model.bin"
)
SRC_SHA = {
    "CIDNet.py": "dc9b9232f225f5760417175d25f8efc146f51c0acd1ee014df6b9f0a6b2e8d84",
    "HVI_transform.py": "8be0fea6e61c51d6290722f0cf81be1f334b1b998dbfd409435343d9d4bd5bb2",
    "LCA.py": "271f487091bd13ed211a8b0c9cb07036957ba535f5dd3aedc131498500979d26",
    "transformer_utils.py": "7bfb2659e97289f0e8005935e15edbe0af3ae5ef05c50863a074fd745617b13f",
}
WEIGHTS_SHA = "9fba75147e0275fa031bdf9905e2f1f8db49c861fc289d3520a509d5cba316aa"
GOLDEN = 384  # the graph's fixed input (see SIZE)
MAX_SIDE = 384  # run 39065558081: 256 px 32.9 dB, 384 px 31.9, 512 px 25.9 vs the full image
# The attention's reshape back to (h, w) is a constant in ncnn: the graph has one input size, and
# the downscale is reflect-padded to it.
SIZE = 384

# The two rearrange patterns of LCA.py, as reshapes (einops is not in the lock).
EINOPS = """
def rearrange(t, pattern, head, h=None, w=None):
    b, c = t.shape[0], t.shape[1]
    if pattern == "b (head c) h w -> b head c (h w)":
        return t.reshape(b, head, c // head, t.shape[2] * t.shape[3])
    if pattern == "b head c (h w) -> b (head c) h w":
        return t.reshape(b, head * t.shape[2], h, w)
    raise NotImplementedError(pattern)
"""
HUB = "class PyTorchModelHubMixin:\n    pass\n"


def sha256(p: pathlib.Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fetch(url: str, dst: pathlib.Path, want: str | None) -> None:
    if not dst.exists():
        print(f"downloading {url}", flush=True)
        urllib.request.urlretrieve(url, dst)
    got = sha256(dst)
    print(f"  {dst.name} sha256 {got}")
    if want is not None and got != want:
        sys.exit(f"{dst.name}: sha256 {got}, want {want}")


class Core(torch.nn.Module):
    """HVI -> corrected HVI: CIDNet.forward between its two colour transforms (upstream code)."""

    def __init__(self, n):
        super().__init__()
        self.n = n

    def forward(self, hvi):
        n = self.n
        i = hvi[:, 2, :, :].unsqueeze(1)
        i_enc0 = n.IE_block0(i)
        i_enc1 = n.IE_block1(i_enc0)
        hv_0 = n.HVE_block0(hvi)
        hv_1 = n.HVE_block1(hv_0)
        i_jump0, hv_jump0 = i_enc0, hv_0
        i_enc2 = n.I_LCA1(i_enc1, hv_1)
        hv_2 = n.HV_LCA1(hv_1, i_enc1)
        v_jump1, hv_jump1 = i_enc2, hv_2
        i_enc2 = n.IE_block2(i_enc2)
        hv_2 = n.HVE_block2(hv_2)
        i_enc3 = n.I_LCA2(i_enc2, hv_2)
        hv_3 = n.HV_LCA2(hv_2, i_enc2)
        v_jump2, hv_jump2 = i_enc3, hv_3
        i_enc3 = n.IE_block3(i_enc2)
        hv_3 = n.HVE_block3(hv_2)
        i_enc4 = n.I_LCA3(i_enc3, hv_3)
        hv_4 = n.HV_LCA3(hv_3, i_enc3)
        i_dec4 = n.I_LCA4(i_enc4, hv_4)
        hv_4 = n.HV_LCA4(hv_4, i_enc4)
        hv_3 = n.HVD_block3(hv_4, hv_jump2)
        i_dec3 = n.ID_block3(i_dec4, v_jump2)
        i_dec2 = n.I_LCA5(i_dec3, hv_3)
        hv_2 = n.HV_LCA5(hv_3, i_dec3)
        hv_2 = n.HVD_block2(hv_2, hv_jump1)
        i_dec2 = n.ID_block2(i_dec3, v_jump1)
        i_dec1 = n.I_LCA6(i_dec2, hv_2)
        hv_1 = n.HV_LCA6(hv_2, i_dec2)
        i_dec1 = n.ID_block1(i_dec1, i_jump0)
        i_dec0 = n.ID_block0(i_dec1)
        hv_1 = n.HVD_block1(hv_1, hv_jump0)
        hv_0 = n.HVD_block0(hv_1)
        return torch.cat([hv_0, i_dec0], dim=1) + hvi


def dark_photo() -> np.ndarray:
    """A seeded synthetic photo (768x512, edges, gradients, texture) taken in poor light."""
    rng = np.random.default_rng(20261017)
    h, w = 512, 768
    y, x = np.mgrid[0:h, 0:w] / max(h, w)
    img = np.stack([0.5 + 0.4 * np.sin(9 * x + 3 * y), 0.4 + 0.4 * y, 0.6 - 0.5 * x], -1)
    for _ in range(12):
        y0, x0 = rng.integers(0, h - 64), rng.integers(0, w - 64)
        img[y0 : y0 + rng.integers(16, 64), x0 : x0 + rng.integers(16, 64)] = rng.random(3)
    img = np.clip(img, 0, 1) ** 2.2 * 0.12  # under-exposed, linear-ish
    img = img + rng.normal(0, 0.006, img.shape)  # sensor noise
    return np.clip(img, 0, 1).astype(np.float32)


def pad8(t: torch.Tensor) -> tuple[torch.Tensor, int, int]:
    h, w = t.shape[2], t.shape[3]
    ph, pw = (-h) % 8, (-w) % 8
    return F.pad(t, (0, pw, 0, ph), mode="reflect"), h, w


def pad_to(t: torch.Tensor, n: int) -> torch.Tensor:
    """Reflect-padded to n x n at the right and bottom (repeated when the side is short)."""
    while t.shape[2] < n or t.shape[3] < n:
        ph, pw = min(n - t.shape[2], t.shape[2] - 1), min(n - t.shape[3], t.shape[3] - 1)
        t = F.pad(t, (0, pw, 0, ph), mode="reflect")
    return t


def low_report(net, core) -> dict:
    """The network on the full image against once on a downscale with the correction upsampled."""
    x = torch.from_numpy(dark_photo()).permute(2, 0, 1)[None]
    out = {}
    with torch.no_grad():
        hvi = net.trans.HVIT(x)
        k = net.trans.this_k
        full_in, h, w = pad8(hvi)
        full = core(full_in)[:, :, :h, :w]
        ref = net.trans.PHVIT(full).clamp(0, 1)
        out["mean_in"] = float(x.mean())
        out["mean_out"] = float(ref.mean())
        for side in (256, 384, 512):
            s = side / max(h, w)
            sh, sw = max(8, round(h * s)), max(8, round(w * s))
            small = F.interpolate(hvi, size=(sh, sw), mode="area")
            small_in = pad_to(small, max(SIZE, side))
            delta = core(small_in)[:, :, :sh, :sw] - small
            up = hvi + F.interpolate(delta, size=(h, w), mode="bilinear", align_corners=False)
            net.trans.this_k = k
            res = net.trans.PHVIT(up).clamp(0, 1)
            mse = float(((res - ref) ** 2).mean())
            out[str(side)] = {"psnr_vs_full": 10 * np.log10(1 / max(mse, 1e-12))}
            print(f"  long side {side}: {out[str(side)]['psnr_vs_full']:.2f} dB vs full")
    print(f"  mean {out['mean_in']:.3f} -> {out['mean_out']:.3f}")
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--pnnx", default="pnnx")
    a = ap.parse_args()
    out = pathlib.Path(a.out).resolve()
    dst = out / "old.lowlight-cidnet"
    work = out / "work"
    pkg = work / "net"
    pkg.mkdir(parents=True, exist_ok=True)
    dst.mkdir(parents=True, exist_ok=True)
    for name, sha in SRC_SHA.items():
        fetch(f"{RAW}/{name}", pkg / name, sha)
    (pkg / "__init__.py").write_text("")
    (work / "einops.py").write_text(EINOPS)
    (work / "huggingface_hub.py").write_text(HUB)
    pth = work / "pytorch_model.bin"
    fetch(WEIGHTS, pth, WEIGHTS_SHA)
    sys.path.insert(0, str(work))
    from net.CIDNet import CIDNet  # noqa: E402  (upstream code, pinned above)

    # LCA.py's F.normalize over the last axis becomes an ncnn Normalize layer without its scale
    # data, which ncnn refuses to load: the same maths, x / max(|x|, eps), as plain layers.
    def normalize(x, p=2.0, dim=1, eps=1e-12):
        return x / torch.sqrt((x * x).sum(dim=dim, keepdim=True)).clamp(min=eps)

    torch.nn.functional.normalize = normalize

    net = CIDNet(channels=[36, 36, 72, 144], heads=[1, 2, 4, 8], norm=False)
    net.load_state_dict(torch.load(pth, map_location="cpu", weights_only=True), strict=True)
    net.eval()
    k = float(net.trans.density_k.item())
    net.trans.this_k = k
    core = Core(net).eval()
    print(f"density k {k:.6f}")

    print("downscaled correction vs the full image:")
    (dst / "low_report.json").write_text(json.dumps(low_report(net, core), indent=2) + "\n")

    with torch.no_grad():
        x = torch.from_numpy(dark_photo()).permute(2, 0, 1)[None][:, :, :GOLDEN, :GOLDEN]
        assert x.shape[2:] == (GOLDEN, GOLDEN)
        hvi = net.trans.HVIT(x).contiguous()
        y = core(hvi)
    hvi.numpy().astype(np.float32).tofile(dst / f"golden_in_3x{GOLDEN}x{GOLDEN}.f32")
    y.numpy().astype(np.float32).tofile(dst / f"golden_out_3x{GOLDEN}x{GOLDEN}.f32")
    x.numpy().astype(np.float32).tofile(dst / f"golden_rgb_3x{GOLDEN}x{GOLDEN}.f32")

    with torch.no_grad():
        torch.jit.trace(core, torch.rand(1, 3, SIZE, SIZE)).save(str(work / "core.pt"))
    subprocess.run(
        [
            a.pnnx,
            str(work / "core.pt"),
            f"inputshape=[1,3,{SIZE},{SIZE}]",
            "fp16=1",
            f"ncnnparam={dst / 'model.ncnn.param'}",
            f"ncnnbin={dst / 'model.ncnn.bin'}",
            f"pnnxparam={work / 'core.pnnx.param'}",
            f"pnnxbin={work / 'core.pnnx.bin'}",
            f"pnnxpy={work / 'core_pnnx.py'}",
            f"pnnxonnx={work / 'core.pnnx.onnx'}",
            f"ncnnpy={work / 'core_ncnn.py'}",
        ],
        check=True,
        cwd=work,
        stdout=subprocess.DEVNULL,
    )
    (dst / "model.json").write_text(
        json.dumps({"scale": 1, "size": SIZE, "max_side": MAX_SIDE, "density_k": k}) + "\n"
    )
    for f in sorted(dst.iterdir()):
        print(f"  old.lowlight-cidnet/{f.name} {f.stat().st_size} {sha256(f)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
