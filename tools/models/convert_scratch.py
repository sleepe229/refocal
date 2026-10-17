#!/usr/bin/env python3
"""Spike S9 (1.1, old photos): converts the scratch detector of "Bringing Old Photos Back to
Life" (microsoft/Bringing-Old-Photos-Back-to-Life, MIT; weights MIT, release v1.0) to ncnn fp16,
and measures how well it finds synthetic scratches.

  <venv>/bin/python tools/models/convert_scratch.py OUT_DIR [--pnnx PATH]

The detector is a U-Net (4 levels: input a multiple of 16) on the grey image scaled to 256 px on
the short side, as upstream's detection.py runs it; upstream thresholds the sigmoid at 0.4. The
graph takes grey in [0, 1] and returns the scratch probability (the [-1, 1] normalisation and
the sigmoid are inside), so the core only scales, thresholds and upsamples the mask. Writes
OUT_DIR/old.scratch/{model.ncnn.param,model.ncnn.bin,model.json}, a golden pair, and
scratch_report.json: IoU and recall of the mask on a seeded synthetic photo with drawn
scratches, against the scratches drawn.
Needs torch, pnnx, numpy and Pillow (spikes/s1-gfpgan/requirements.lock).
"""
import argparse, hashlib, json, pathlib, subprocess, sys, urllib.request, zipfile

import numpy as np
import torch
from PIL import Image, ImageDraw, ImageFilter

COMMIT = "33875eccf4ebcd3665cf38cc56f3a0ce563d3a9c"
RAW = f"https://raw.githubusercontent.com/microsoft/Bringing-Old-Photos-Back-to-Life/{COMMIT}/Global/detection_models"
ZIP = "https://github.com/microsoft/Bringing-Old-Photos-Back-to-Life/releases/download/v1.0/global_checkpoints.zip"
MEMBER = "checkpoints/detection/FT_Epoch_latest.pt"
# sha256 of the files above (networks.py and antialiasing.py pinned from the upstream commit; the
# zip (2 GB, of which the detector is one member) and the member from the first conversion run).
SRC_SHA = {
    "networks.py": "5aaa9f8d23620be0d7cf27b9da634134f5fb1bff20d2b7c043232b7f27fa0013",
    "antialiasing.py": "277bcecdf3e81e3238494c42ba12e7b9dfbe509c531b724abaa8c80f7e74cca5",
}
ZIP_SHA = None
WEIGHTS_SHA = None
GOLDEN = (256, 384)  # h, w: the 256 px short side of a 2:3 photo
THRESHOLD = 0.4  # upstream detection.py


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


class Detect(torch.nn.Module):
    """Grey [0, 1] -> scratch probability, as upstream's Normalize([0.5], [0.5]) and sigmoid."""

    def __init__(self, net):
        super().__init__()
        self.net = net

    def forward(self, x):
        return torch.sigmoid(self.net(x * 2 - 1))


def scratched_photo() -> tuple[Image.Image, np.ndarray]:
    """A seeded synthetic grey photo with thin bright and dark scratches, and their mask."""
    rng = np.random.default_rng(20261017)
    h, w = 512, 768
    y, x = np.mgrid[0:h, 0:w] / max(h, w)
    img = 0.45 + 0.25 * np.sin(7 * x + 2 * y) + 0.15 * y
    for _ in range(10):  # rectangles: edges that are not scratches
        y0, x0 = rng.integers(0, h - 96), rng.integers(0, w - 96)
        img[y0:y0 + rng.integers(24, 96), x0:x0 + rng.integers(24, 96)] = rng.random()
    img = np.clip(img + rng.normal(0, 0.03, img.shape), 0, 1)
    photo = Image.fromarray((img * 255).astype(np.uint8))
    mask = Image.new("L", (w, h), 0)
    dp, dm = ImageDraw.Draw(photo), ImageDraw.Draw(mask)
    for i in range(14):
        pts = [(int(rng.integers(0, w)), int(rng.integers(0, h)))]
        for _ in range(3):  # a slightly bent line
            pts.append((int(np.clip(pts[-1][0] + rng.integers(-160, 160), 0, w - 1)),
                        int(np.clip(pts[-1][1] + rng.integers(-160, 160), 0, h - 1))))
        width = int(rng.integers(1, 4))
        dp.line(pts, fill=235 if i % 3 else 20, width=width)
        dm.line(pts, fill=255, width=width)
    return photo, np.asarray(mask) > 0


def to_input(photo: Image.Image, short: int = 256) -> torch.Tensor:
    w, h = photo.size
    s = short / min(w, h)
    nw, nh = int(round(w * s / 16) * 16), int(round(h * s / 16) * 16)
    a = np.asarray(photo.convert("L").resize((nw, nh), Image.BICUBIC), np.float32) / 255
    return torch.from_numpy(a)[None, None]


def scratch_report(det: Detect) -> dict:
    photo, truth = scratched_photo()
    with torch.no_grad():
        p = det(to_input(photo))
    p = torch.nn.functional.interpolate(p, size=truth.shape, mode="nearest")[0, 0].numpy()
    out = {}
    for t in (0.3, THRESHOLD, 0.5):
        m = p >= t
        inter, union = (m & truth).sum(), (m | truth).sum()
        # Scratches drawn 1-3 px wide on the full image are under a pixel at 256 px: a hit within
        # 2 px of a drawn scratch counts (the inpainting mask is dilated anyway).
        near = np.asarray(Image.fromarray(truth.astype(np.uint8) * 255).filter(
            ImageFilter.MaxFilter(5))) > 0
        out[str(t)] = {
            "iou": float(inter / max(union, 1)),
            "recall": float(inter / max(truth.sum(), 1)),
            "precision_2px": float((m & near).sum() / max(m.sum(), 1)),
            "coverage": float(m.mean()),
        }
        print(f"  t{t}: " + " ".join(f"{k} {v:.3f}" for k, v in out[str(t)].items()))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--pnnx", default="pnnx")
    a = ap.parse_args()
    out = pathlib.Path(a.out).resolve()
    dst = out / "old.scratch"
    work = out / "work"
    pkg = work / "detection_models"
    (pkg / "sync_batchnorm").mkdir(parents=True, exist_ok=True)
    dst.mkdir(parents=True, exist_ok=True)

    for name, sha in SRC_SHA.items():
        fetch(f"{RAW}/{name}", pkg / name, sha)
    (pkg / "__init__.py").write_text("")
    # Only DataParallel (sync_bn=True) needs it; the network uses plain BatchNorm2d.
    (pkg / "sync_batchnorm" / "__init__.py").write_text("DataParallelWithCallback = None\n")
    pt = work / "FT_Epoch_latest.pt"
    if not pt.exists():
        zp = work / "global_checkpoints.zip"
        fetch(ZIP, zp, ZIP_SHA)
        with zipfile.ZipFile(zp) as z:
            name = next(n for n in z.namelist() if n.endswith(MEMBER))
            pt.write_bytes(z.read(name))
        zp.unlink()
    fetch(ZIP, pt, WEIGHTS_SHA)  # already there: only checked
    sys.path.insert(0, str(work))
    from detection_models import networks  # noqa: E402  (upstream code, pinned above)

    net = networks.UNet(in_channels=1, out_channels=1, depth=4, conv_num=2, wf=6, padding=True,
                        batch_norm=True, up_mode="upsample", with_tanh=False, sync_bn=False,
                        antialiasing=True)
    state = torch.load(pt, map_location="cpu", weights_only=False)["model_state"]
    net.load_state_dict({k.removeprefix("module."): v for k, v in state.items()}, strict=True)
    net.eval()
    det = Detect(net).eval()

    print("synthetic scratches:")
    (dst / "scratch_report.json").write_text(json.dumps(scratch_report(det), indent=2) + "\n")

    photo, _ = scratched_photo()
    x = to_input(photo)[:, :, :GOLDEN[0], :GOLDEN[1]].contiguous()
    with torch.no_grad():
        y = det(x)
    x.numpy().tofile(dst / f"golden_in_1x{GOLDEN[0]}x{GOLDEN[1]}.f32")
    y.numpy().astype(np.float32).tofile(dst / f"golden_out_1x{GOLDEN[0]}x{GOLDEN[1]}.f32")

    with torch.no_grad():
        torch.jit.trace(det, torch.rand(1, 1, 256, 256)).save(str(work / "detect.pt"))
    subprocess.run(
        [a.pnnx, str(work / "detect.pt"), "inputshape=[1,1,256,256]",
         "inputshape2=[1,1,256,384]", "fp16=1",
         f"ncnnparam={dst / 'model.ncnn.param'}", f"ncnnbin={dst / 'model.ncnn.bin'}",
         f"pnnxparam={work / 'detect.pnnx.param'}", f"pnnxbin={work / 'detect.pnnx.bin'}",
         f"pnnxpy={work / 'detect_pnnx.py'}", f"pnnxonnx={work / 'detect.pnnx.onnx'}",
         f"ncnnpy={work / 'detect_ncnn.py'}"],
        check=True, cwd=work, stdout=subprocess.DEVNULL)
    (dst / "model.json").write_text(
        json.dumps({"scale": 1, "short_side": 256, "multiple": 16, "threshold": THRESHOLD}) + "\n")
    for f in sorted(dst.iterdir()):
        print(f"  old.scratch/{f.name} {f.stat().st_size} {sha256(f)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
