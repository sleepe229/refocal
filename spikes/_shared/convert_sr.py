"""Convert Real-ESRGAN realesr-general-x4v3 (SRVGGNetCompact) to ONNX + ncnn, with DNI denoise levels.

Denoise levels (ADR-0015) are baked offline by interpolating weights between
realesr-general-x4v3 (strong denoise, level 1.0) and realesr-general-wdn-x4v3 (no denoise, level 0):
    W(level) = level * W_x4v3 + (1 - level) * W_wdn
Outputs (spikes/_shared/models/): sr_compact_dn{000,050,100}.{onnx,ncnn.param,ncnn.bin}

Architecture re-implemented from Real-ESRGAN (BSD-3-Clause, xinntao), realesrgan/archs/srvgg_arch.py.
Run with the S1 venv:  ../s1-gfpgan/.venv/bin/python convert_sr.py
"""
import subprocess
from pathlib import Path

import numpy as np
import torch
from torch import nn
from torch.nn import functional as F

HERE = Path(__file__).resolve().parent
W = HERE / "weights"
OUT = HERE / "models"
PNNX = HERE.parent / "s1-gfpgan" / ".venv" / "bin" / "pnnx"


class SRVGGNetCompact(nn.Module):
    def __init__(self, num_in_ch=3, num_out_ch=3, num_feat=64, num_conv=32, upscale=4):
        super().__init__()
        self.upscale = upscale
        body = [nn.Conv2d(num_in_ch, num_feat, 3, 1, 1), nn.PReLU(num_parameters=num_feat)]
        for _ in range(num_conv):
            body += [nn.Conv2d(num_feat, num_feat, 3, 1, 1), nn.PReLU(num_parameters=num_feat)]
        body.append(nn.Conv2d(num_feat, num_out_ch * upscale * upscale, 3, 1, 1))
        self.body = nn.ModuleList(body)
        self.upsampler = nn.PixelShuffle(upscale)

    def forward(self, x):
        out = x
        for layer in self.body:
            out = layer(out)
        out = self.upsampler(out)
        return out + F.interpolate(x, scale_factor=self.upscale, mode="nearest")


def load(level: float) -> SRVGGNetCompact:
    a = torch.load(W / "realesr-general-x4v3.pth", map_location="cpu", weights_only=True)["params"]
    b = torch.load(W / "realesr-general-wdn-x4v3.pth", map_location="cpu", weights_only=True)["params"]
    state = {k: level * a[k] + (1 - level) * b[k] for k in a}
    m = SRVGGNetCompact()
    m.load_state_dict(state, strict=True)
    return m.eval()


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for level in (0.0, 0.5, 1.0):
        name = f"sr_compact_dn{int(level * 100):03d}"
        m = load(level)
        x = torch.rand(1, 3, 288, 288)
        onnx_path = OUT / f"{name}.onnx"
        torch.onnx.export(m, (x,), str(onnx_path), input_names=["input"], output_names=["output"],
                          opset_version=17, dynamo=False,
                          dynamic_axes={"input": {2: "h", 3: "w"}, "output": {2: "h4", 3: "w4"}})
        subprocess.run([str(PNNX), onnx_path.name, "inputshape=[1,3,288,288]", "fp16=1"],
                       cwd=OUT, check=True, capture_output=True)
        for junk in OUT.glob(f"{name}.pnnx*"):
            junk.unlink()
        for junk in OUT.glob(f"{name}_*.py"):
            junk.unlink()
        n = sum(p.numel() for p in m.parameters())
        print(f"{name}: {n / 1e6:.3f}M params, ncnn bin {(OUT / f'{name}.ncnn.bin').stat().st_size / 1e6:.2f} MB")

    # Golden reference tile for S3 correctness checks: deterministic 160x160 input -> torch fp32 output.
    rng = np.random.default_rng(20261009)
    base = rng.random((3, 20, 20), dtype=np.float32)
    tile = F.interpolate(torch.from_numpy(base)[None], size=(160, 160), mode="bicubic", align_corners=False)
    tile = (tile + 0.03 * torch.randn(tile.shape, generator=torch.Generator().manual_seed(7))).clamp(0, 1)
    with torch.no_grad():
        ref = load(0.5)(tile).clamp(0, 1)
    tile.numpy().astype(np.float32).tofile(OUT / "golden_in_3x160x160.f32")
    ref.numpy().astype(np.float32).tofile(OUT / "golden_out_dn050_3x640x640.f32")
    print("golden tile written: golden_in_3x160x160.f32 -> golden_out_dn050_3x640x640.f32")


if __name__ == "__main__":
    main()
