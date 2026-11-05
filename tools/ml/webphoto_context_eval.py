#!/usr/bin/env python3
"""Offline WebPhoto GroupNorm context experiment (13 §1.2, NFR-QLT-003).

Compare shared normalization statistics from a reduced image with an oracle that
uses a full-image forward pass. This isolates normalization from the native SR
pipeline; it neither exports a modified pack nor qualifies one for distribution.

Requires the converter's torch, numpy, Pillow and spandrel==0.4.1 environment.
"""

import argparse
import contextlib
import hashlib
import json
import pathlib

import numpy as np
import torch
from PIL import Image
from sr_eval import luma, psnr

CHECKPOINT_SHA = "a9db66c9b674c6a5025b6ef3bee71a57c33b8605d8a2de0980470f89002efbbe"
SIDE, PAD, SCALE = 384, 64, 4


class FrozenGroupNorm(torch.nn.Module):
    """Apply one image's group statistics as a channel-wise affine transform."""

    def __init__(self, norm, context):
        super().__init__()
        if context.shape[0] != 1 or not torch.isfinite(context).all():
            raise ValueError("context must be one finite image")
        var, mean = torch.var_mean(context.reshape(1, norm.num_groups, -1), dim=-1, correction=0)
        channels = norm.num_channels // norm.num_groups
        scale = torch.rsqrt(var + norm.eps).repeat_interleave(channels, dim=1)
        mean = mean.repeat_interleave(channels, dim=1)
        scale = scale.reshape(1, -1, 1, 1) * norm.weight[None, :, None, None]
        bias = norm.bias[None, :, None, None] - mean.reshape(1, -1, 1, 1) * scale
        self.register_buffer("scale", scale)
        self.register_buffer("bias", bias)

    def forward(self, image):
        return image * self.scale + self.bias


def capture(model, image):
    """Record each GroupNorm's input statistics during an unchanged forward pass."""
    frozen, handles = {}, []
    for name, module in model.named_modules():
        if isinstance(module, torch.nn.GroupNorm):
            handles.append(
                module.register_forward_pre_hook(
                    lambda norm, args, name=name: frozen.__setitem__(
                        name, FrozenGroupNorm(norm, args[0])
                    )
                )
            )
    try:
        output = model(image)
    finally:
        for handle in handles:
            handle.remove()
    if not frozen:
        raise ValueError("model has no GroupNorm layers")
    return output, frozen


@contextlib.contextmanager
def shared_stats(model, stats):
    original = {name: model.get_submodule(name) for name in stats}
    try:
        for name, module in stats.items():
            model.set_submodule(name, module)
        yield
    finally:
        for name, module in original.items():
            model.set_submodule(name, module)


def rendered(output):
    if not torch.isfinite(output).all():
        raise ValueError("non-finite model output")
    pixels = output[0].clamp(0, 1).permute(1, 2, 0).numpy()
    return Image.fromarray((pixels * 255).round().astype(np.uint8))


def padded(image):
    return torch.nn.functional.pad(image, (PAD, PAD, PAD, PAD), mode="reflect")


def whole(model, image):
    margin = PAD * SCALE
    return model(padded(image))[:, :, margin:-margin, margin:-margin]


def tiled(model, image, tile):
    """Mirror the native fixed-size tiles, reflected halo and last-tile ownership."""
    output = torch.empty(1, 3, SIDE * SCALE, SIDE * SCALE)
    source = padded(image)
    origins = list(range(0, SIDE - tile, tile)) + [SIDE - tile]
    for iy, y in enumerate(origins):
        for ix, x in enumerate(origins):
            result = model(source[:, :, y : y + tile + 2 * PAD, x : x + tile + 2 * PAD])
            y0 = 0 if iy == 0 else origins[iy - 1] + tile - y
            x0 = 0 if ix == 0 else origins[ix - 1] + tile - x
            output[
                :, :, (y + y0) * SCALE : (y + tile) * SCALE, (x + x0) * SCALE : (x + tile) * SCALE
            ] = result[
                :,
                :,
                (PAD + y0) * SCALE : (PAD + tile) * SCALE,
                (PAD + x0) * SCALE : (PAD + tile) * SCALE,
            ]
    return output


def main():
    from spandrel import ModelLoader

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkpoint", type=pathlib.Path)
    parser.add_argument("image", type=pathlib.Path, help="a Kodak reference image")
    parser.add_argument("out", type=pathlib.Path)
    args = parser.parse_args()
    if hashlib.sha256(args.checkpoint.read_bytes()).hexdigest() != CHECKPOINT_SHA:
        parser.error("WebPhoto checkpoint SHA-256 mismatch")
    torch.set_num_threads(4)
    model = ModelLoader(device="cpu").load_from_file(str(args.checkpoint)).model.eval()
    with Image.open(args.image) as source:
        if min(source.size) < SIDE:
            parser.error("image must be at least 384 pixels on each side")
        pixels = np.asarray(source.convert("RGB").crop((0, 0, SIDE, SIDE))).copy()
    image = torch.from_numpy(pixels).permute(2, 0, 1)[None].float() / 255
    args.out.mkdir(parents=True, exist_ok=True)
    evidence = {
        "checkpoint_sha256": CHECKPOINT_SHA,
        "image_sha256": hashlib.sha256(args.image.read_bytes()).hexdigest(),
        "torch": torch.__version__,
        "scope": "PyTorch normalization experiment; no sharpening; not pack qualification",
        "rows": [],
    }
    with torch.inference_mode():
        reference, full_stats = capture(model, padded(image))
        margin = PAD * SCALE
        reference = rendered(reference[:, :, margin:-margin, margin:-margin])
        for side in (192, SIDE):
            if side == SIDE:
                stats = full_stats  # Oracle: requires the expensive full-image pass.
            else:
                context = torch.nn.functional.interpolate(image, size=(side, side), mode="area")
                _, stats = capture(model, padded(context))
            with shared_stats(model, stats):
                context_whole = rendered(whole(model, image))
                for tile in (128, 256):
                    result = rendered(tiled(model, image, tile))
                    row = {
                        "context_side": side,
                        "tile": tile,
                        "pad": PAD,
                        "psnr_vs_upstream": psnr(luma(reference), luma(result)),
                        "psnr_vs_context_whole": psnr(luma(context_whole), luma(result)),
                        "context_whole_vs_upstream": psnr(luma(reference), luma(context_whole)),
                    }
                    evidence["rows"].append(row)
                    (args.out / "context.json").write_text(json.dumps(evidence, indent=2) + "\n")
                    print(json.dumps(row), flush=True)


if __name__ == "__main__":
    main()
