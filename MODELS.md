# Models

Every model shipped in the app or offered as a download is listed here (ML-REG-001, OPS-LIC-002,
TEST-COMP-004; `tools/models/check_manifest.py` fails without a row for each pack of
`tools/models/manifest.json` and each bundled model of `tools/models/models.lock`). Weights are
never committed to git; bundled files are verified against `models.lock`, packs against the
signed manifest (ADR-0011). All ncnn files are fp16 weights; nothing is int8-quantized.

| Pack id | Delivery | Upstream | Weights license | Conversion | Files (SHA-256) |
|---|---|---|---|---|---|
| `sr.general-x4v3` | bundled (0.1) | [xinntao/Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) v0.3.0 `realesr-general-x4v3.pth` (8dc7edb9…e96292) + `realesr-general-wdn-x4v3.pth`, DNI denoise 0.5 (ADR-0015) | BSD-3-Clause, © 2021 Xintao Wang | `spikes/_shared/convert_sr.py` (PyTorch → pnnx → ncnn, S1/S2) | `model.ncnn.param` a950267a…55e5fe, `model.ncnn.bin` 8fe24682…9645aa |
| `sr.general-x4v3-dn0` | pack (0.2) | as above, DNI denoise 0 | BSD-3-Clause | as above | `model.ncnn.param` a950267a…55e5fe, `model.ncnn.bin` e1a48f57…ea1231 |
| `sr.general-x4v3-dn100` | pack (0.2) | as above, DNI denoise 1.0 | BSD-3-Clause | as above | `model.ncnn.param` a950267a…55e5fe, `model.ncnn.bin` 8fdd6052…ece553 |
| `det.yunet-2023mar` | bundled (0.2) | [opencv/opencv_zoo](https://github.com/opencv/opencv_zoo) `face_detection_yunet_2023mar.onnx` (8f2383e4…552fa4) | MIT | pnnx ONNX → ncnn (`spikes/s1-gfpgan`, S1) | `model.ncnn.param` b5b3d417…6b1700, `model.ncnn.bin` 8faa696d…8ca5c9 |
| `face.gfpgan-1.4` | pack (0.2), license acceptance | [TencentARC/GFPGAN](https://github.com/TencentARC/GFPGAN) v1.3.0 release `GFPGANv1.4.pth` (e2cd4703…1be5ad) | GFPGAN license, non-commercial (`LicenseRef-GFPGAN-NC`) | `spikes/s1-gfpgan/export_models.py --static-modconv` (ADR-0023) | `model.ncnn.param` 484bdd2d…03fae7, `model.ncnn.bin` 060f2ae4…d39040, `model.json` c185d99e…75c5e4 |
| `face.codeformer` | pack (0.5), T2, license acceptance | [sczhou/CodeFormer](https://github.com/sczhou/CodeFormer) v0.1.0 release `codeformer.pth` (1009e537…5684b7), `params_ema` | S-Lab License 1.0, non-commercial (`LicenseRef-S-Lab-1.0`) | `tools/models/convert_codeformer.py` (split graph, ADR-0024) | `encoder.ncnn.param` 7275d4c5…3c765a, `encoder.ncnn.bin` 26f2d326…37383b, `codebook.f32` c006bc48…d5dcac, `generator.ncnn.param` 15fdd72f…68f74d, `generator.ncnn.bin` a0e3a099…9d6d4c, `model.json` 3c8d9f14…d08ec0 |
| `sr.x4plus` | pack (0.5), T2 | [xinntao/Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) v0.1.0 `RealESRGAN_x4plus.pth` (4fa0d389…d682f1), RRDBNet 23 blocks | BSD-3-Clause, © 2021 Xintao Wang | `tools/models/convert_rrdb.py` (TorchScript → pnnx → ncnn) | `model.ncnn.param` 86de8b20…04538f, `model.ncnn.bin` cae0a543…9a2159, `model.json` a034657c…b9a2ca |
| `sr.x4plus-anime6b` | pack (0.5), T1 | as above, v0.2.2.4 `RealESRGAN_x4plus_anime_6B.pth` (f872d837…5e99da), RRDBNet 6 blocks | BSD-3-Clause, © 2021 Xintao Wang | `tools/models/convert_rrdb.py` | `model.ncnn.param` 8fb8b2a1…c5f6ed, `model.ncnn.bin` e8b012c2…c62d2c, `model.json` 1d308df1…f62dfb |

## Evaluation

| Model | Check | Result |
|---|---|---|
| `sr.general-x4v3` | TEST-ML-001: ncnn CPU vs PyTorch fp32, 160×160 golden tile (`tools/models/golden.lock`) | ≥ 40 dB on every PR (CI) |
| `sr.general-x4v3` | TEST-ML-005: same input, recipe and backend → byte-identical result | every PR (CI) |
| `sr.x4plus`, `sr.x4plus-anime6b` | TEST-ML-001: ncnn CPU vs PyTorch fp32, 96×96 golden tile (`golden.lock`) | 64.5 dB, 63.9 dB; ≥ 40 dB on every PR (CI) |
| `face.gfpgan-1.4` | ncnn fp16 vs PyTorch fp32 (S1) | CPU 54.8 dB, Vulkan 51.4 dB |
| `face.codeformer` | ncnn fp16 vs PyTorch fp32, one real face (`test_faces`, nightly) | CPU 43.9 dB at w 0.7 (48.5 at 1.0, 40.1 at 0.5, 34.1 at 0); 252 of 256 codebook picks equal |

## Known limitations

- `sr.x4plus-anime6b` is trained on drawings: on photos it flattens texture into flat colour
  areas.
- SR models invent plausible detail; they cannot recover text, number plates or fine patterns
  that the input does not show, and may render them wrong.
- `face.gfpgan-1.4` reconstructs a face from a prior learned on FFHQ: small or heavily degraded
  faces may come out looking like someone else, and quality differs across skin tones, ages,
  glasses and profile views. The per-subgroup report (ML-BIAS-001, TEST-ML-008) goes here
  before 0.5 leaves beta (roadmap 13). The editor's strength slider and per-face toggle
  (FR-FACE-007) keep the original available.
- `face.codeformer` replaces each face with codebook entries chosen by a transformer: at low
  fidelity (w near 0) faces are sharper but drift further from the person; fp16 changes a few
  near-tie code picks (252/256 equal), visible mostly at w 0. Same FFHQ biases as GFPGAN.
- `det.yunet-2023mar` runs on a 640 px copy of the photo: it can miss very small faces and
  strong profiles, which then get no face restoration.

Attribution shown in the app: About → Licenses has the Real-ESRGAN BSD-3-Clause and YuNet MIT
texts (`tools/licenses/collect.sh`); a pack's license text is shown before it is installed
(the face pack asks for acceptance).
