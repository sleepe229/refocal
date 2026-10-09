# Spike S1 — GFPGAN 1.4 → ncnn / Core ML

Goal: can GFPGAN v1.4 be converted for on-device inference (ncnn Vulkan/CPU on Android,
Core ML on iOS) without quality loss, and how fast/heavy is it?

Report (RU): [`docs/spikes/S1.md`](../../docs/spikes/S1.md).

## Reproduce

```bash
uv venv -p 3.12 .venv && uv pip install -p .venv/bin/python -r requirements.lock
git clone --depth 1 --branch v1.3.8 https://github.com/TencentARC/GFPGAN third_party/GFPGAN
mkdir -p weights
curl -L -o weights/GFPGANv1.4.pth https://github.com/TencentARC/GFPGAN/releases/download/v1.3.0/GFPGANv1.4.pth
#   sha256 e2cd4703ab14f4d01fd1383a8a8b266f9a5833dacee8e6a79d3bf21a1b6be5ad
curl -L -o weights/face_detection_yunet_2023mar.onnx \
  https://github.com/opencv/opencv_zoo/raw/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx
# test photos (public domain, Wikimedia Commons) -> data/raw/*.jpg, see docs/spikes/S1.md

.venv/bin/python prepare_faces.py                  # YuNet + FFHQ-512 alignment -> data/faces/
.venv/bin/python export_models.py                  # original:  out/models/gfpgan14.{pt,onnx}
.venv/bin/python export_models.py --static-modconv # rewritten: out/models/gfpgan14s.{pt,onnx}
(cd out/models && ../../.venv/bin/pnnx gfpgan14.pt  "inputshape=[1,3,512,512]" fp16=1)
(cd out/models && ../../.venv/bin/pnnx gfpgan14s.onnx "inputshape=[1,3,512,512]" fp16=1)  # .pt crashes pnnx
.venv/bin/python run_backend.py torch_fp32                       # reference (original model)
.venv/bin/python run_backend.py ncnn_vk0_fp16 --model gfpgan14s  # backends: see run_backend.py
.venv/bin/python compare.py                                      # PSNR / LPIPS vs reference, montage
.venv/bin/python convert_coreml.py                               # out/models/gfpgan14s.mlpackage
```

## Files

| File | Purpose |
|---|---|
| `gfpgan_model.py` | Loads GFPGANv1Clean without basicsr; `static_modconv=True` applies the mobile rewrite |
| `prepare_faces.py` | YuNet detection on a 640 px copy, FFHQ-512 similarity alignment, synthetic LQ variants |
| `export_models.py` | TorchScript + ONNX (opset 17, static 1×3×512×512) |
| `run_backend.py` | One backend per process: outputs, latency, peak RSS |
| `compare.py` | Parity vs PyTorch fp32 of the original model; spec gate (NFR-QLT-001) |
| `convert_coreml.py` | Core ML mlprogram fp16 (iOS 16) |
| `device_bench.md` | How to measure latency on real Android/iOS devices (S1b) |

Not committed (see `.gitignore`): `.venv/`, `third_party/`, `weights/`, `data/`, `out/`.
