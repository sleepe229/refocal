"""Load GFPGANv1Clean (v1.4 weights) without installing basicsr.

The upstream architecture (third_party/GFPGAN, Apache-2.0) imports two tiny helpers
from basicsr; we stub them so the spike depends only on torch.
"""

import sys
import types
from pathlib import Path

import torch
from torch import nn
from torch.nn import functional as F

HERE = Path(__file__).resolve().parent
GFPGAN_SRC = HERE / "third_party" / "GFPGAN"
WEIGHTS = HERE / "weights" / "GFPGANv1.4.pth"


def _install_basicsr_stubs() -> None:
    if "basicsr" in sys.modules:
        return

    class _Registry:
        def register(self, obj=None):
            return obj if obj is not None else (lambda o: o)

    def default_init_weights(module_list, scale=1, bias_fill=0, **kwargs):
        # Initialization is irrelevant: all weights are overwritten by the checkpoint.
        return None

    basicsr = types.ModuleType("basicsr")
    utils = types.ModuleType("basicsr.utils")
    registry = types.ModuleType("basicsr.utils.registry")
    registry.ARCH_REGISTRY = _Registry()
    archs = types.ModuleType("basicsr.archs")
    arch_util = types.ModuleType("basicsr.archs.arch_util")
    arch_util.default_init_weights = default_init_weights
    for name, mod in {
        "basicsr": basicsr,
        "basicsr.utils": utils,
        "basicsr.utils.registry": registry,
        "basicsr.archs": archs,
        "basicsr.archs.arch_util": arch_util,
    }.items():
        sys.modules[name] = mod


def _import_clean_arch():
    _install_basicsr_stubs()
    # Import the arch modules directly, bypassing gfpgan/__init__.py (which pulls in
    # basicsr/facexlib).
    import importlib.util

    pkg = types.ModuleType("gfpgan_archs")
    pkg.__path__ = [str(GFPGAN_SRC / "gfpgan" / "archs")]
    sys.modules["gfpgan_archs"] = pkg
    for name in ("stylegan2_clean_arch", "gfpganv1_clean_arch"):
        spec = importlib.util.spec_from_file_location(
            f"gfpgan_archs.{name}", GFPGAN_SRC / "gfpgan" / "archs" / f"{name}.py"
        )
        mod = importlib.util.module_from_spec(spec)
        sys.modules[f"gfpgan_archs.{name}"] = mod
        spec.loader.exec_module(mod)
    return sys.modules["gfpgan_archs.gfpganv1_clean_arch"].GFPGANv1Clean


def _static_modconv_forward(self, x, style):
    """Mathematically equivalent ModulatedConv2d (batch=1) with *static* conv weights.

    Original: conv(x, W * s) * demod-in-weights, where the conv weight is computed per sample
    (dynamic weight -> not supported by ncnn Vulkan / Core ML ANE fast paths).
    Here: conv(x * s, W) * demod, with demod_o = rsqrt(sum_i Wsq[o, i] * s_i^2 + eps)
    and Wsq[o, i] = sum_k W[o, i, k]^2 precomputed. Per-channel scaling commutes with
    bilinear resampling, so it is applied after up/downsampling.
    """
    b, c, h, w = x.shape
    s = self.modulation(style).view(b, c)
    if self.demodulate:
        # fp16 safety: demodulation is invariant to a global scale of s
        # (conv(x*s/k) * rsqrt(sum W^2 (s/k)^2) == conv(x*s) * rsqrt(sum W^2 s^2), eps aside),
        # so normalize s to [-1, 1]. Without this, s^2 reaches ~1e6 and overflows fp16 (max 65504),
        # rsqrt(inf) = 0 and the layer output silently collapses to zero on GPU fp16.
        s = s / s.abs().amax(dim=1, keepdim=True).clamp_min(1e-6)
    if self.sample_mode == "upsample":
        x = F.interpolate(x, scale_factor=2, mode="bilinear", align_corners=False)
    elif self.sample_mode == "downsample":
        x = F.interpolate(x, scale_factor=0.5, mode="bilinear", align_corners=False)
    out = F.conv2d(x * s.view(b, c, 1, 1), self.weight[0], padding=self.padding)
    if self.demodulate:
        demod = torch.rsqrt(F.linear(s * s, self.weight_sq) + self.eps)  # (b, c_out)
        out = out * demod.view(b, self.out_channels, 1, 1)
    return out


def _patch_static_modconv(net: nn.Module) -> int:
    mod_cls = sys.modules["gfpgan_archs.stylegan2_clean_arch"].ModulatedConv2d
    n = 0
    for m in net.modules():
        if isinstance(m, mod_cls):
            m.register_buffer(
                "weight_sq", m.weight[0].detach().pow(2).sum([2, 3]), persistent=False
            )
            m.forward = types.MethodType(_static_modconv_forward, m)
            n += 1
    return n


class GFPGANExport(nn.Module):
    """Deterministic single-output wrapper: input/output NCHW RGB in [-1, 1], 1x3x512x512."""

    def __init__(self, net: nn.Module):
        super().__init__()
        self.net = net

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        out, _ = self.net(x, return_rgb=False, randomize_noise=False)
        return out


def load_gfpgan(weights: Path = WEIGHTS, static_modconv: bool = False) -> GFPGANExport:
    GFPGANv1Clean = _import_clean_arch()
    net = GFPGANv1Clean(
        out_size=512,
        num_style_feat=512,
        channel_multiplier=2,
        decoder_load_path=None,
        fix_decoder=False,
        num_mlp=8,
        input_is_latent=True,
        different_w=True,
        narrow=1,
        sft_half=True,
    )
    ckpt = torch.load(weights, map_location="cpu", weights_only=True)
    state = ckpt.get("params_ema", ckpt.get("params", ckpt))
    net.load_state_dict(state, strict=True)
    net.eval()
    if static_modconv:
        n = _patch_static_modconv(net)
        print(f"static modulated conv: patched {n} layers")
    return GFPGANExport(net).eval()


if __name__ == "__main__":
    ref, m = load_gfpgan(), load_gfpgan(static_modconv=True)
    x = torch.rand(1, 3, 512, 512) * 2 - 1
    with torch.no_grad():
        d = (ref(x) - m(x)).abs()
    print(f"static vs original: max|diff| = {float(d.max()):.2e}, mean = {float(d.mean()):.2e}")
    n_params = sum(p.numel() for p in m.parameters())
    print(f"GFPGANv1Clean loaded: {n_params / 1e6:.2f}M params")
    with torch.no_grad():
        y = m(torch.zeros(1, 3, 512, 512))
    print("output", tuple(y.shape), float(y.min()), float(y.max()))
