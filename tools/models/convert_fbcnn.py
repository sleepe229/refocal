#!/usr/bin/env python3
"""Spike S9 (1.1, JPEG artifacts): converts FBCNN (jiaxi-jiang/FBCNN, Apache-2.0) to ncnn fp16
as two graphs, and measures what tiling does to its quality-factor estimate.

  <venv>/bin/python tools/models/convert_fbcnn.py OUT_DIR [--pnnx PATH]

FBCNN predicts the JPEG quality factor (QF) from the image and conditions the restoration on
it. Tiles would each predict their own QF and the seams would show, so the pack has two
graphs: `estimate` (image tile -> qf, averaged over tiles by the core) and `restore`
(tile, qf -> tile, the QF given from outside: FBCNN's qf_input). Writes
OUT_DIR/jpeg.fbcnn/{estimate,restore}.ncnn.{param,bin}, model.json, a golden pair for each graph,
and qf_report.json: the QF each tile predicts on photos saved at known qualities (tiles of
96..256 px), against the whole-image prediction.
Needs torch, pnnx and Pillow (spikes/s1-gfpgan/requirements.lock).
"""
import argparse, hashlib, io, json, pathlib, subprocess, sys, urllib.request

import numpy as np
import torch
from PIL import Image

COMMIT = "54d1831927506b3247e2d4d245abb4f4dab1a1cd"
NET_URL = f"https://raw.githubusercontent.com/jiaxi-jiang/FBCNN/{COMMIT}/models/network_fbcnn.py"
WEIGHTS = "https://github.com/jiaxi-jiang/FBCNN/releases/download/v1.0/fbcnn_color.pth"
# sha256 of the files above (pinned from the first conversion run).
NET_SHA = "e1afc1f6483d57b774365467393216508f29a708b576dc973bad41bae67e8d03"
WEIGHTS_SHA = "8b0e4ef23d59cf7ac934a342cb31a17619e4fa4a0b3374a9d78c5174312387e8"
GOLDEN = 96  # multiple of 8: three stride-2 levels


def sha256(p: pathlib.Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fetch(url: str, dst: pathlib.Path, want: str | None) -> None:
    if not dst.exists():
        print(f"downloading {url}")
        urllib.request.urlretrieve(url, dst)
    got = sha256(dst)
    print(f"  {dst.name} sha256 {got}")
    if want is not None and got != want:
        sys.exit(f"{dst.name}: sha256 {got}, want {want}")


class Estimate(torch.nn.Module):
    """Tile -> QF (FBCNN's own prediction, in [0, 1] as 1 - quality/100)."""

    def __init__(self, net):
        super().__init__()
        self.net = net

    def forward(self, x):
        return self.net(x)[1]


class Restore(torch.nn.Module):
    """(tile, qf) -> restored tile, conditioned on the given QF."""

    def __init__(self, net):
        super().__init__()
        self.net = net

    def forward(self, x, qf):
        return self.net(x, qf)[0]


def test_photo() -> Image.Image:
    """A seeded synthetic photo with edges, gradients and texture (no external data)."""
    rng = np.random.default_rng(20261017)
    h, w = 512, 768
    y, x = np.mgrid[0:h, 0:w] / max(h, w)
    img = np.stack([0.5 + 0.4 * np.sin(9 * x + 3 * y), 0.4 + 0.4 * y, 0.6 - 0.5 * x], -1)
    for _ in range(12):  # rectangles: hard edges, where blocking shows
        y0, x0 = rng.integers(0, h - 64), rng.integers(0, w - 64)
        img[y0:y0 + rng.integers(16, 64), x0:x0 + rng.integers(16, 64)] = rng.random(3)
    img += rng.normal(0, 0.04, img.shape)
    return Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))


def as_tensor(im: Image.Image) -> torch.Tensor:
    return torch.from_numpy(np.asarray(im, np.float32) / 255).permute(2, 0, 1)[None]


def qf_report(est: Estimate) -> dict:
    photo = test_photo()
    out = {}
    for quality in (10, 30, 50, 70, 90):
        buf = io.BytesIO()
        photo.save(buf, "JPEG", quality=quality)
        x = as_tensor(Image.open(buf).convert("RGB"))
        with torch.no_grad():
            whole = float(est(x).flatten()[0])
            per_tile = {}
            for t in (96, 128, 256):
                qs = [float(est(x[:, :, i:i + t, j:j + t]).flatten()[0])
                      for i in range(0, x.shape[2] - t + 1, t)
                      for j in range(0, x.shape[3] - t + 1, t)]
                per_tile[t] = {"mean": float(np.mean(qs)), "std": float(np.std(qs)),
                               "min": float(np.min(qs)), "max": float(np.max(qs)), "n": len(qs)}
        out[quality] = {"true": 1 - quality / 100, "whole": whole, "tiles": per_tile}
        print(f"  q{quality}: true {1 - quality / 100:.2f} whole {whole:.3f} "
              + " ".join(f"t{t} {v['mean']:.3f}±{v['std']:.3f}" for t, v in per_tile.items()))
    return out


def pnnx_convert(pnnx: str, ts: pathlib.Path, shapes: list[str], dst: pathlib.Path, name: str,
                 work: pathlib.Path) -> None:
    subprocess.run(
        [pnnx, str(ts), *shapes, "fp16=1",
         f"ncnnparam={dst / (name + '.ncnn.param')}", f"ncnnbin={dst / (name + '.ncnn.bin')}",
         f"pnnxparam={work / (name + '.pnnx.param')}", f"pnnxbin={work / (name + '.pnnx.bin')}",
         f"pnnxpy={work / (name + '_pnnx.py')}", f"pnnxonnx={work / (name + '.pnnx.onnx')}",
         f"ncnnpy={work / (name + '_ncnn.py')}"],
        check=True, cwd=work, stdout=subprocess.DEVNULL)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--pnnx", default="pnnx")
    a = ap.parse_args()
    out = pathlib.Path(a.out).resolve()
    dst = out / "jpeg.fbcnn"
    work = out / "work"
    dst.mkdir(parents=True, exist_ok=True)
    work.mkdir(parents=True, exist_ok=True)

    net_py = work / "network_fbcnn.py"
    pth = work / "fbcnn_color.pth"
    fetch(NET_URL, net_py, NET_SHA)
    fetch(WEIGHTS, pth, WEIGHTS_SHA)
    sys.path.insert(0, str(work))
    from network_fbcnn import FBCNN  # noqa: E402  (upstream code, pinned above)

    net = FBCNN(in_nc=3, out_nc=3, nc=[64, 128, 256, 512], nb=4, act_mode="R")
    net.load_state_dict(torch.load(pth, map_location="cpu", weights_only=True), strict=True)
    net.eval()
    est, res = Estimate(net).eval(), Restore(net).eval()

    print("QF per tile vs whole image:")
    (dst / "qf_report.json").write_text(json.dumps(qf_report(est), indent=2) + "\n")

    rng = np.random.default_rng(20261017)
    tile = (rng.random((1, 3, GOLDEN, GOLDEN)) * 0.2 + as_tensor(test_photo())[
        :, :, :GOLDEN, :GOLDEN].numpy() * 0.8).astype(np.float32)
    qf = np.array([[0.7]], np.float32)  # quality 30
    with torch.no_grad():
        ref_q = est(torch.from_numpy(tile)).numpy()
        ref_y = res(torch.from_numpy(tile), torch.from_numpy(qf)).numpy()
    tile.tofile(dst / f"golden_in_3x{GOLDEN}x{GOLDEN}.f32")
    ref_q.astype(np.float32).tofile(dst / "golden_estimate_out.f32")
    ref_y.astype(np.float32).tofile(dst / f"golden_restore_out_3x{GOLDEN}x{GOLDEN}.f32")

    with torch.no_grad():
        torch.jit.trace(est, torch.rand(1, 3, 128, 128)).save(str(work / "estimate.pt"))
        torch.jit.trace(res, (torch.rand(1, 3, 128, 128), torch.rand(1, 1))).save(
            str(work / "restore.pt"))
    pnnx_convert(a.pnnx, work / "estimate.pt",
                 ["inputshape=[1,3,128,128]", "inputshape2=[1,3,192,192]"], dst, "estimate", work)
    pnnx_convert(a.pnnx, work / "restore.pt",
                 ["inputshape=[1,3,128,128],[1,1]", "inputshape2=[1,3,192,192],[1,1]"], dst,
                 "restore", work)
    (dst / "model.json").write_text(json.dumps({"scale": 1, "pad": 16, "multiple": 8}) + "\n")
    for f in sorted(dst.iterdir()):
        print(f"  jpeg.fbcnn/{f.name} {f.stat().st_size} {sha256(f)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
