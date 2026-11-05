#!/usr/bin/env python3
"""Convert pinned community SR candidates with Spandrel's public model loader.

  python tools/models/convert_community_sr.py OUT --weights WEIGHTS --pnnx PATH

Requires torch, numpy, ncnn, spandrel==0.4.1 and pnnx (offline tools only). Download the
listed upstream .pth files into WEIGHTS as <id>.pth, or missing files are fetched.
Hashes are published by OpenModelDB or the upstream GitHub release. All candidates
are by Philip Hofmann (Helaman); the public-domain-trained x2 model is Apache-2.0,
the other candidates CC-BY-4.0 (ADR-0026).
Writes dynamic-size ncnn models and deterministic fp32 golden pairs. Compact uses
fp16 weights; SPAN needs fp32 weights after Conv3XC fusion, and HQ candidates also
use fp32 weights. No pack
is published by this script: quality, seams and conversion checks must pass first.
The 1.2 HQ candidates additionally need comparison with sr.x4plus on a T2 device.
"""

import argparse
import hashlib
import json
import pathlib
import subprocess
import time
import urllib.parse
import urllib.request

import ncnn
import numpy as np
import torch
from spandrel import ModelLoader

MODELS = {
    "sr.lsdir-compact": {
        "source": "https://openmodeldb.info/models/4x-LSDIRCompactR3",
        "url": "https://drive.google.com/file/d/1_UrO5UwADJyfOpKWp5y81USFCAgG-z3-",
        "sha256": "5b7d8bccfee8897fb72126f05de83e1bdf36e7dc2b17023b074fc1c97580e568",
        "scale": 4,
        "pad": 24,
        "fp16": True,
    },
    "sr.nomos-compact-x2": {
        "source": "https://openmodeldb.info/models/2x-NomosUni-compact-otf-medium",
        "url": "https://drive.google.com/file/d/1lUDklqGCq3fiGO0EBN8P5W-bSsldX1st",
        "sha256": "d9f767194d5163e5b1604ccd87f24f12f23562ed66245bba058eea1f4686ca5a",
        "scale": 2,
        "pad": 24,
        "fp16": True,
    },
    "sr.nomos-span-medium": {
        "source": "https://openmodeldb.info/models/4x-Nomos8k-span-otf-medium",
        "url": "https://drive.google.com/file/d/1M1bgiMOuOoZkArB-JkKoZiDNoHlpar2X",
        "sha256": "c1a4395b6d34ffa86b1c6e8a443d32ccaba7a53fabf600f7c17d804cc8156b46",
        "scale": 4,
        "pad": 48,
        "fp16": False,
    },
    "sr.nomos-span-strong": {
        "source": "https://openmodeldb.info/models/4x-Nomos8k-span-otf-strong",
        "url": "https://drive.google.com/file/d/1K_OUt9lwvDXn280OTfURm0tD3E0lVZ5b",
        "sha256": "b63dfd3f18da07b46c978f9fb480e6f43f9ece7550ef462c86d5151b93fa6040",
        "scale": 4,
        "pad": 48,
        "fp16": False,
    },
    "sr.webphoto-realplksr": {
        "source": "https://openmodeldb.info/models/4x-NomosWebPhoto-RealPLKSR",
        "url": "https://github.com/Phhofm/models/releases/download/4xNomosWebPhoto_RealPLKSR/4xNomosWebPhoto_RealPLKSR.pth",
        "sha256": "a9db66c9b674c6a5025b6ef3bee71a57c33b8605d8a2de0980470f89002efbbe",
        "scale": 4,
        "pad": 64,
        "fp16": False,
        # GroupNorm depends on the whole tile; an OOM split changes its statistics.
        "split_tiles": False,
    },
    "sr.public-realplksr-x2": {
        "source": "https://github.com/Phhofm/models/releases/tag/2xPublic_realplksr_dysample_layernorm_real",
        "url": "https://github.com/Phhofm/models/releases/download/2xPublic_realplksr_dysample_layernorm_real/2xPublic_realplksr_dysample_layernorm_real.pth",
        "sha256": "efda6ac7d2d89a265c66401680e2851116345eff157365ccf338ab87f46988b6",
        "scale": 2,
        "pad": 64,
        "fp16": False,
        "license": "Apache-2.0",
    },
}
GOLDEN_SIZE = 96


class DySampleExport(torch.nn.Module):
    """Keep dynamic coordinates and sample each group at batch one for ncnn."""

    def __init__(self, model):
        super().__init__()
        self.offset, self.scope = model.offset, model.scope
        self.end_conv = model.end_conv
        self.register_buffer("init_pos", model.init_pos)
        self.scale, self.groups = model.scale, model.groups
        self.channels = model.offset.in_channels // model.groups

    def forward(self, tile):
        offset = self.offset(tile) * self.scope(tile).sigmoid() * 0.5 + self.init_pos
        # arange/meshgrid on dynamic sizes do not lower to ncnn. CumulativeSum of ones
        # supplies exactly the same pixel centres without freezing the trace dimensions.
        ones = tile[:, :1] * 0 + 1
        # Negative axes survive ncnn's removal of the leading batch dimension.
        cx = torch.cumsum(ones, dim=-1) - 0.5
        cy = torch.cumsum(ones, dim=-2) - 0.5
        width = cx[:, :, :, -1:] + 0.5
        height = cy[:, :, -1:, :] + 0.5
        half = self.groups * self.scale * self.scale
        coords = torch.cat(
            [2 * (cx + offset[:, :half]) / width - 1, 2 * (cy + offset[:, half:]) / height - 1],
            dim=1,
        )
        coords = torch.nn.functional.pixel_shuffle(coords, self.scale)
        outputs = []
        for group in range(self.groups):
            grid = torch.cat(
                [
                    coords[:, group : group + 1],
                    coords[:, self.groups + group : self.groups + group + 1],
                ],
                dim=1,
            ).permute(0, 2, 3, 1)
            outputs.append(
                torch.nn.functional.grid_sample(
                    tile[:, group * self.channels : (group + 1) * self.channels],
                    grid,
                    mode="bilinear",
                    align_corners=False,
                    padding_mode="border",
                )
            )
        return self.end_conv(torch.cat(outputs, dim=1))


class RealPLKSRExport(torch.nn.Module):
    """pnnx cannot lower repeat_interleave; concatenate the same RGB planes exactly."""

    def __init__(self, model, scale: int):
        super().__init__()
        self.feats, self.to_img = model.feats, model.to_img
        if hasattr(model.to_img, "init_pos"):
            self.to_img = DySampleExport(model.to_img)
        self.repeats = scale * scale

    def forward(self, tile):
        skip = torch.cat(
            [tile[:, channel : channel + 1] for channel in range(3) for _ in range(self.repeats)],
            dim=1,
        )
        return self.to_img(self.feats(tile) + skip)


def sha256(path: pathlib.Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def download_url(url: str) -> str:
    """Resolve the legacy Drive links; GitHub assets already have a direct URL."""
    parsed = urllib.parse.urlsplit(url)
    if parsed.hostname == "drive.google.com":
        parts = parsed.path.strip("/").split("/")
        if len(parts) != 3 or parts[:2] != ["file", "d"] or not parts[2]:
            raise ValueError("unsupported Google Drive checkpoint URL")
        return "https://drive.usercontent.google.com/download?" + urllib.parse.urlencode(
            {"id": parts[2], "export": "download", "confirm": "t"}
        )
    if parsed.scheme != "https" or not parsed.hostname:
        raise ValueError("checkpoint URL must use HTTPS")
    return url


def check_conversion(model, dst: pathlib.Path, generator: torch.Generator) -> list[dict]:
    """Check actual exported weights, including a rectangular unseen input shape."""
    scores = []
    with ncnn.Net() as net:
        net.opt.num_threads = 4
        if (
            net.load_param(str(dst / "model.ncnn.param")) != 0
            or net.load_model(str(dst / "model.ncnn.bin")) != 0
        ):
            raise ValueError(f"{dst.name}: cannot load ncnn model")
        for height, width in [(GOLDEN_SIZE, GOLDEN_SIZE), (71, 103)]:
            tile = torch.rand(1, 3, height, width, generator=generator)
            with torch.inference_mode():
                reference = model(tile)[0].numpy()
            with net.create_extractor() as extractor:
                if extractor.input("in0", ncnn.Mat(tile[0].numpy()).clone()) != 0:
                    raise ValueError(f"{dst.name}: ncnn input failed")
                status, raw = extractor.extract("out0")
                if status != 0:
                    raise ValueError(f"{dst.name}: ncnn inference failed")
                output = np.asarray(raw)
                if (
                    output.shape != reference.shape
                    or not np.isfinite(output).all()
                    or not np.isfinite(reference).all()
                ):
                    raise ValueError(f"{dst.name}: invalid ncnn output")
                output = output.clip(0, 1)
                reference = reference.clip(0, 1)
                mse = np.mean((output.astype(np.float64) - reference) ** 2)
                db = float(-10 * np.log10(mse)) if mse > 0 else 99.0
            if db < 40:
                raise ValueError(f"{dst.name}: TEST-ML-001 failed: {db:.2f} dB < 40")
            scores.append({"height": height, "width": width, "psnr_vs_fp32": db})
    return scores


def convert(mid: str, spec: dict, weights: pathlib.Path, out: pathlib.Path, pnnx: str):
    weights.mkdir(parents=True, exist_ok=True)
    checkpoint = weights / f"{mid}.pth"
    if not checkpoint.exists():
        temporary = checkpoint.with_suffix(".pth.part")
        url = download_url(spec["url"])
        for attempt in range(4):
            try:
                with urllib.request.urlopen(url, timeout=90) as response, temporary.open("wb") as f:
                    while chunk := response.read(1 << 20):
                        f.write(chunk)
                break
            except OSError:
                if attempt == 3:
                    raise
                time.sleep(2 * (attempt + 1))
        if sha256(temporary) != spec["sha256"]:
            raise ValueError(f"{temporary}: upstream SHA-256 mismatch")
        temporary.replace(checkpoint)
    if sha256(checkpoint) != spec["sha256"]:
        raise ValueError(f"{checkpoint}: upstream SHA-256 mismatch")
    descriptor = ModelLoader(device="cpu").load_from_file(str(checkpoint))
    if descriptor.scale != spec["scale"]:
        raise ValueError(f"{mid}: unexpected scale {descriptor.scale}")
    model = descriptor.model.eval()
    export_model = model
    if mid in ("sr.webphoto-realplksr", "sr.public-realplksr-x2"):
        export_model = RealPLKSRExport(model, spec["scale"]).eval()
    dst = out / mid
    dst.mkdir(parents=True, exist_ok=True)
    work = out / "_work"
    work.mkdir(exist_ok=True)
    generator = torch.Generator().manual_seed(20261030)
    tile = torch.rand(1, 3, GOLDEN_SIZE, GOLDEN_SIZE, generator=generator)
    with torch.inference_mode():
        reference = model(tile).clamp(0, 1)
        if export_model is not model:
            # Check before tracing: the adapter must preserve the upstream model's output.
            torch.testing.assert_close(export_model(tile), model(tile), rtol=0, atol=0)
        trace = torch.jit.trace(export_model, torch.rand(1, 3, 128, 128, generator=generator))
        traced = work / f"{mid}.pt"
        trace.save(str(traced))
    size = GOLDEN_SIZE
    scaled = size * spec["scale"]
    tile.numpy().astype(np.float32).tofile(dst / f"golden_in_3x{size}x{size}.f32")
    reference.numpy().astype(np.float32).tofile(dst / f"golden_out_3x{scaled}x{scaled}.f32")
    subprocess.run(
        [
            pnnx,
            str(traced),
            "inputshape=[1,3,128,128]",
            "inputshape2=[1,3,192,192]",
            f"fp16={int(spec['fp16'])}",
            f"ncnnparam={dst / 'model.ncnn.param'}",
            f"ncnnbin={dst / 'model.ncnn.bin'}",
            f"pnnxparam={work / (mid + '.pnnx.param')}",
            f"pnnxbin={work / (mid + '.pnnx.bin')}",
            f"pnnxpy={work / (mid + '_pnnx.py')}",
            f"pnnxonnx={work / (mid + '.pnnx.onnx')}",
            f"ncnnpy={work / (mid + '_ncnn.py')}",
        ],
        cwd=work,
        check=True,
    )
    param = (dst / "model.ncnn.param").read_text()
    if " in0 " not in param or " out0" not in param:
        raise ValueError(f"{mid}: unexpected ncnn blob names")
    metadata = {"scale": spec["scale"], "pad": spec["pad"]}
    if not spec.get("split_tiles", True):
        metadata["split_tiles"] = False
    (dst / "model.json").write_text(json.dumps(metadata) + "\n")
    provenance = {
        **spec,
        "author": "Philip Hofmann (Helaman)",
        "license": spec.get("license", "CC-BY-4.0"),
        "golden_size": GOLDEN_SIZE,
        "parity": check_conversion(model, dst, generator),
        "files": {p.name: sha256(p) for p in sorted(dst.iterdir()) if p.name != "conversion.json"},
    }
    (dst / "conversion.json").write_text(json.dumps(provenance, indent=2) + "\n")
    print(f"Converted {mid}", flush=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("out", type=pathlib.Path)
    parser.add_argument("--weights", required=True, type=pathlib.Path)
    parser.add_argument("--pnnx", required=True)
    parser.add_argument("--only", choices=sorted(MODELS))
    args = parser.parse_args()
    torch.set_num_threads(4)
    for mid, spec in MODELS.items():
        if args.only is None or mid == args.only:
            convert(mid, spec, args.weights, args.out.resolve(), args.pnnx)


if __name__ == "__main__":
    main()
