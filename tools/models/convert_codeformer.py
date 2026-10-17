#!/usr/bin/env python3
"""Converts CodeFormer (04-ml-models: face.codeformer, FR-FACE-005) to an ncnn fp16 pack, and
checks it against the PyTorch fp32 original.

  <venv>/bin/python tools/models/convert_codeformer.py OUT_DIR [--pnnx PATH] [--face FACE.png]

CodeFormer's code and weights are under the S-Lab License 1.0 (non-commercial): nothing of it is
copied into this repository. The script downloads the upstream architecture files and weights
(pinned by SHA-256 below) into OUT_DIR/_work and imports them from there.

The graph is split in two (ADR-0024), so that the codebook lookup is exact and `w` is an input
of the graph (ML-CNV-003):
  encoder.ncnn.*  in0 [1,3,512,512] in [-1,1] -> out0 logits [256,1024] (one row per 16x16
                  token), out1..out4 the encoder features fused at 32, 64, 128, 256 px;
  codebook.f32    the 1024 x 256 code embeddings (fp32): the core takes the argmax of each logits
                  row (torch.topk(softmax(.), 1) picks the same) and gathers the code into a
                  [256,16,16] feature, token t at (t / 16, t % 16);
  generator.ncnn.* in0 that feature, in1..in4 the encoder features, in5 w [1,1,1,1] (fidelity 0..1)
                  -> out0 [1,3,512,512] in [-1,1].
w = 0 runs the fuse blocks with a zero residual: the same as upstream's `if w > 0` skip.
It writes OUT_DIR/face.codeformer/{encoder,generator}.ncnn.{param,bin}, codebook.f32, model.json
and the parity report of ncnn CPU against PyTorch fp32 (PSNR, at w 0, 0.5, 0.7 and 1).
Needs torch and pnnx (spikes/s1-gfpgan/requirements.lock).
"""
import argparse, hashlib, json, pathlib, subprocess, sys, types, urllib.request

import numpy as np
import torch

COMMIT = "b33cc7d639d6545bfcccc7e0bc6ae51f24e79c2b"
SOURCES = {
    "vqgan_arch.py": "5ef00125ce448e34c9c02655bdebff5dca51589597c7c43a0b4bf2326d32e8cb",
    "codeformer_arch.py": "dfccf9e9e6cd58b933301350e956418d1ffb15bb601ef5ce16d6dda3f01d020a",
}
SRC_URL = f"https://raw.githubusercontent.com/sczhou/CodeFormer/{COMMIT}/basicsr/archs/"
WEIGHTS = ("https://github.com/sczhou/CodeFormer/releases/download/v0.1.0/codeformer.pth",
           "1009e537e0c2a07d4cabce6355f53cb66767cd4b4297ec7a4a64ca4b8a5684b7")
LICENSE_URL = f"https://raw.githubusercontent.com/sczhou/CodeFormer/{COMMIT}/LICENSE"
CONNECT = ["32", "64", "128", "256"]


def sha256(p: pathlib.Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fetch(url: str, dst: pathlib.Path, want: str | None) -> None:
    if not dst.exists() or (want and sha256(dst) != want):
        print(f"downloading {url}")
        urllib.request.urlretrieve(url, dst)
    got = sha256(dst)
    if want and got != want:
        sys.exit(f"{dst.name}: sha256 {got}, want {want}")


def load_upstream(work: pathlib.Path):
    """Imports the pinned upstream modules with stand-ins for the basicsr helpers they use."""
    for name, want in SOURCES.items():
        fetch(SRC_URL + name, work / name, want)
    registry = types.SimpleNamespace(register=lambda *a, **k: (lambda c: c))
    pkgs = {
        "basicsr": types.ModuleType("basicsr"),
        "basicsr.archs": types.ModuleType("basicsr.archs"),
        "basicsr.utils": types.ModuleType("basicsr.utils"),
        "basicsr.utils.registry": types.ModuleType("basicsr.utils.registry"),
    }
    pkgs["basicsr.utils"].get_root_logger = lambda *a, **k: types.SimpleNamespace(
        info=print, warning=print)
    pkgs["basicsr.utils.registry"].ARCH_REGISTRY = registry
    sys.modules.update(pkgs)
    mods = {}
    for name in ["vqgan_arch", "codeformer_arch"]:
        mod = types.ModuleType(f"basicsr.archs.{name}")
        sys.modules[mod.__name__] = mod
        exec(compile((work / f"{name}.py").read_text(), str(work / f"{name}.py"), "exec"),
             mod.__dict__)
        mods[name] = mod
    return mods["codeformer_arch"].CodeFormer


def qkv_linears(mha):
    """nn.MultiheadAttention's projections as plain nn.Linear: q, k, v from the packed in_proj and
    out_proj (a NonDynamicallyQuantizableLinear, which pnnx leaves as an unconverted F.linear).
    pnnx converts modules, not F.linear on parameter slices."""
    e = mha.embed_dim
    out = torch.nn.ModuleList()
    ws = list(zip(mha.in_proj_weight.split(e), mha.in_proj_bias.split(e)))
    ws.append((mha.out_proj.weight, mha.out_proj.bias))
    for w, b in ws:
        lin = torch.nn.Linear(e, e)
        lin.weight.data.copy_(w.detach())
        lin.bias.data.copy_(b.detach())
        out.append(lin)
    return out


def self_attention_layer(layer, qkv, t, pos):
    """Upstream TransformerSALayer on [1, 256 tokens, 512] with nn.MultiheadAttention written out
    (ADR-0024): pnnx turns its q = k != v call into an ncnn MultiHeadAttention with two inputs,
    which ncnn reads as (q, kv), dropping the position embedding from k. The batch axis stays
    explicit (pnnx takes the first axis of any tensor as the batch); heads are slices of the
    channel axis, k is transposed once (a transposed operand next to a matmul becomes a
    two-input F.linear that ncnn cannot run)."""
    t2 = layer.norm1(t)
    qk = t2 + pos
    mha = layer.self_attn
    e, h = mha.embed_dim, mha.num_heads
    d = e // h
    q, k, v = qkv[0](qk), qkv[1](qk), qkv[2](t2)
    kt = k.transpose(1, 2).contiguous()  # [1, e, tokens]
    heads = []
    for i in range(h):
        qi, vi = q[:, :, i * d:(i + 1) * d], v[:, :, i * d:(i + 1) * d]
        kti = kt[:, i * d:(i + 1) * d, :]
        heads.append(torch.matmul(torch.softmax(torch.matmul(qi, kti) * d ** -0.5, dim=-1), vi))
    t = t + qkv[3](torch.cat(heads, dim=2))
    return t + layer.linear2(layer.activation(layer.linear1(layer.norm2(t))))


class Encoder(torch.nn.Module):
    """Upstream forward up to the logits, plus the encoder features the generator fuses."""

    def __init__(self, cf):
        super().__init__()
        self.cf = cf
        self.qkv = torch.nn.ModuleList(qkv_linears(layer.self_attn) for layer in cf.ft_layers)

    def forward(self, x):
        cf = self.cf
        out_list = [cf.fuse_encoder_block[s] for s in CONNECT]
        feats = []
        for i, block in enumerate(cf.encoder.blocks):
            x = block(x)
            if i in out_list:
                feats.append(x)
        query = cf.feat_emb(x.reshape(1, x.shape[1], -1).transpose(1, 2))  # [1, 256 tokens, 512]
        for layer, qkv in zip(cf.ft_layers, self.qkv):
            query = self_attention_layer(layer, qkv, query, cf.position_emb.unsqueeze(0))
        logits = cf.idx_pred_layer(query)  # [1, 256, 1024]
        # out_list is in block order: 256 px first. Return 32, 64, 128, 256.
        return (logits, feats[3], feats[2], feats[1], feats[0])


class Generator(torch.nn.Module):
    """Upstream forward from the quantized feature, with w as a tensor."""

    def __init__(self, cf):
        super().__init__()
        self.cf = cf

    def forward(self, quant, f32, f64, f128, f256, w):
        cf = self.cf
        enc = {"32": f32, "64": f64, "128": f128, "256": f256}
        # Block index -> feature size (a traced shape is a tensor, not a dict key).
        fuse_at = {cf.fuse_generator_block[s]: s for s in CONNECT}
        x = quant
        for i, block in enumerate(cf.generator.blocks):
            x = block(x)
            if i in fuse_at:
                s = fuse_at[i]
                x = cf.fuse_convs_dict[s](enc[s], x, w)
        return x


def lookup(logits: np.ndarray, codebook: np.ndarray) -> np.ndarray:
    """What the core does: argmax per token, gather, [256,16,16]."""
    idx = logits.argmax(axis=1)
    return codebook[idx].reshape(16, 16, 256).transpose(2, 0, 1).copy()


def face_input(path: str | None) -> np.ndarray:
    if path:
        import cv2
        img = cv2.cvtColor(cv2.imread(path), cv2.COLOR_BGR2RGB)
        img = cv2.resize(img, (512, 512), interpolation=cv2.INTER_AREA)
    else:  # a smooth seeded pattern: parity only, not quality
        rng = np.random.default_rng(20261016)
        y, x = np.mgrid[0:512, 0:512] / 512
        img = np.stack([0.5 + 0.4 * np.sin(9 * x + 3 * y), 0.4 + 0.3 * y, 0.6 - 0.4 * x], -1)
        img = np.clip(img + rng.normal(0, 0.02, img.shape), 0, 1) * 255
    return (img.astype(np.float32).transpose(2, 0, 1) / 127.5 - 1).copy()


def psnr(a: np.ndarray, b: np.ndarray) -> float:
    a8 = np.clip((a + 1) * 127.5 + 0.5, 0, 255).astype(np.uint8).astype(np.float64)
    b8 = np.clip((b + 1) * 127.5 + 0.5, 0, 255).astype(np.uint8).astype(np.float64)
    mse = np.mean((a8 - b8) ** 2)
    return 99.0 if mse == 0 else 10 * np.log10(255 ** 2 / mse)


def pnnx_convert(pnnx: str, ts: pathlib.Path, shapes: list[str], dst: pathlib.Path, name: str,
                 work: pathlib.Path) -> None:
    args = [pnnx, str(ts)]
    args += [f"inputshape={','.join(shapes)}", "fp16=1",
             f"ncnnparam={dst / (name + '.ncnn.param')}", f"ncnnbin={dst / (name + '.ncnn.bin')}",
             f"pnnxparam={work / (name + '.pnnx.param')}", f"pnnxbin={work / (name + '.pnnx.bin')}",
             f"pnnxpy={work / (name + '_pnnx.py')}", f"pnnxonnx={work / (name + '.pnnx.onnx')}",
             f"ncnnpy={work / (name + '_ncnn.py')}"]
    subprocess.run(args, check=True, cwd=work, stdout=subprocess.DEVNULL)


def run_ncnn(dst: pathlib.Path, name: str, inputs: list[np.ndarray], n_out: int) -> list:
    import ncnn
    net = ncnn.Net()
    net.opt.use_vulkan_compute = False
    net.load_param(str(dst / f"{name}.ncnn.param"))
    net.load_model(str(dst / f"{name}.ncnn.bin"))
    ex = net.create_extractor()
    for i, a in enumerate(inputs):
        ex.input(f"in{i}", ncnn.Mat(np.ascontiguousarray(a)))
    outs = []
    for i in range(n_out):
        _, m = ex.extract(f"out{i}")
        outs.append(np.array(m))
    return outs


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--pnnx", default="pnnx")
    ap.add_argument("--face", help="an aligned 512x512 face for the parity check")
    ap.add_argument("--parity-only", action="store_true", help="reuse the converted files")
    a = ap.parse_args()
    out = pathlib.Path(a.out).resolve()
    work = out / "_work"
    work.mkdir(parents=True, exist_ok=True)
    dst = out / "face.codeformer"
    dst.mkdir(parents=True, exist_ok=True)

    CodeFormer = load_upstream(work)
    pth = work / "codeformer.pth"
    fetch(WEIGHTS[0], pth, WEIGHTS[1])
    fetch(LICENSE_URL, dst / "LICENSE.txt", None)
    cf = CodeFormer(dim_embd=512, codebook_size=1024, n_head=8, n_layers=9,
                    connect_list=CONNECT)
    state = torch.load(pth, map_location="cpu", weights_only=True)
    cf.load_state_dict(state["params_ema"], strict=True)  # ML-CNV-003: params_ema
    cf.eval()
    enc, gen = Encoder(cf).eval(), Generator(cf).eval()
    codebook = cf.quantize.embedding.weight.detach().numpy().astype(np.float32)
    codebook.tofile(dst / "codebook.f32")

    x = torch.from_numpy(face_input(a.face))[None]
    with torch.no_grad():
        e_out = enc(x)
        quant = torch.from_numpy(lookup(e_out[0][0].numpy(), codebook))[None]
        feats = e_out[1:]
        w0 = torch.full((1, 1, 1, 1), 0.7)
        if not a.parity_only:
            torch.jit.trace(enc, x).save(str(work / "encoder.pt"))
            torch.jit.trace(gen, (quant, *feats, w0)).save(str(work / "generator.pt"))
        # The rewritten transformer gives upstream's logits (forward with code_only).
        up_logits = cf(x, code_only=True)[0][0]
        diff = (up_logits - e_out[0][0]).abs().max().item()
        if diff > 1e-3:
            sys.exit(f"encoder logits differ from upstream: {diff}")
        # The split graph equals upstream at every w (upstream skips the fuse at w = 0).
        for w in (0.0, 0.5, 0.7, 1.0):
            ref = cf(x, w=w, adain=False)[0]
            mine = gen(quant, *feats, torch.full((1, 1, 1, 1), w))
            diff = (ref - mine).abs().max().item()
            if diff > 1e-4:
                sys.exit(f"split graph differs from upstream at w={w}: {diff}")
    if not a.parity_only:
        pnnx_convert(a.pnnx, work / "encoder.pt", ["[1,3,512,512]"], dst, "encoder", work)
        shapes = ["[1,256,16,16]"] + [f"[1,{t.shape[1]},{t.shape[2]},{t.shape[3]}]" for t in feats]
        pnnx_convert(a.pnnx, work / "generator.pt", shapes + ["[1,1,1,1]"], dst, "generator", work)

    report = {}
    e_nc = run_ncnn(dst, "encoder", [x[0].numpy()], 5)
    q_nc = lookup(e_nc[0].reshape(256, 1024), codebook)
    same_codes = int((e_nc[0].reshape(256, 1024).argmax(1) == e_out[0][0].numpy().argmax(1)).sum())
    report["codes_equal"] = f"{same_codes}/256"
    for w in (0.0, 0.5, 0.7, 1.0):
        with torch.no_grad():
            ref = cf(x, w=w, adain=False)[0][0].numpy()
        nc = run_ncnn(dst, "generator", [q_nc] + e_nc[1:] +
                      [np.full((1, 1, 1), w, np.float32)], 1)[0]
        report[f"psnr_w{w}"] = round(psnr(nc, ref), 2)
    # Golden pair for the core (test_faces): the input face and the PyTorch fp32 output at the
    # default fidelity, next to the pack directory (not part of the pack).
    gold = out / "face.codeformer-golden"
    gold.mkdir(exist_ok=True)
    x[0].numpy().astype(np.float32).tofile(gold / "in_3x512x512.f32")
    with torch.no_grad():
        cf(x, w=0.7, adain=False)[0][0].numpy().astype(np.float32).tofile(gold / "out_w07_3x512x512.f32")
    print(json.dumps(report))
    (dst / "model.json").write_text(json.dumps({
        "split": "codeformer", "fidelity_default": 0.7, "codebook": [1024, 256]}) + "\n")
    (out / "parity.json").write_text(json.dumps(report, indent=1) + "\n")
    for f in sorted(dst.iterdir()):
        print(f"  face.codeformer/{f.name} {f.stat().st_size} {sha256(f)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
