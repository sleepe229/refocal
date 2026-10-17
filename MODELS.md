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
| `jpeg.fbcnn` | pack (0.6), T2 | [jiaxi-jiang/FBCNN](https://github.com/jiaxi-jiang/FBCNN) v1.0 release `fbcnn_color.pth` (8b0e4ef2…2387e8), commit 54d18319 | Apache-2.0, © Jiaxi Jiang et al. | `tools/models/convert_fbcnn.py` (restore graph only, QF as the second input; S9) | `model.ncnn.param` f3662e8a…b7b89a5, `model.ncnn.bin` c973ad06…69952c1, `model.json` e6da6680…0894cd9 |
| `old.scratch` | pack (0.6), T1 | [microsoft/Bringing-Old-Photos-Back-to-Life](https://github.com/microsoft/Bringing-Old-Photos-Back-to-Life) v1.0 release, `checkpoints/detection/FT_Epoch_latest.pt` (b2d7ab04…a59a95), commit 33875ecc | MIT, © Microsoft Corporation | `tools/models/convert_scratch.py` (grey in, scratch probability out; S9) | `model.ncnn.param` 0986bf5e…16084e, `model.ncnn.bin` 12984526…654dcc, `model.json` 6f23279c…c462b3 |
| `old.inpaint-migan` | pack (0.6), T1 | [Picsart-AI-Research/MI-GAN](https://github.com/Picsart-AI-Research/MI-GAN) 512 Places2, from the ONNX pipeline on Hugging Face `andraniksargsyan/migan` (593eba0b…0fc5ae), revision 406830d0 | MIT (code and `LICENSE-WEIGHTS`), © Picsart AI Research | `tools/models/convert_migan.py` (the generator cut out of the pipeline; S9) | `model.ncnn.param` 6088ec4a…933b0a, `model.ncnn.bin` 319e248f…73722d, `model.json` df2fc58b…a96a9f |
| `old.lowlight-cidnet` | pack (0.6), T1 | [Fediory/HVI-CIDNet](https://github.com/Fediory/HVI-CIDNet) Generalization weights, Hugging Face `Fediory/HVI-CIDNet-Generalization` `pytorch_model.bin` (9fba7514…a316aa), revision 51481ef2 | MIT, © Fediory Feng | `tools/models/convert_cidnet.py` (the network between its HVI transforms, which the core does; S9) | `model.ncnn.param` 4ff94961…62507e, `model.ncnn.bin` 9e714e40…1ae1fe, `model.json` 0a2345db…722f65 |

## Evaluation

| Model | Check | Result |
|---|---|---|
| `sr.general-x4v3` | TEST-ML-001: ncnn CPU vs PyTorch fp32, 160×160 golden tile (`tools/models/golden.lock`) | ≥ 40 dB on every PR (CI) |
| `sr.general-x4v3` | TEST-ML-005: same input, recipe and backend → byte-identical result | every PR (CI) |
| `sr.x4plus`, `sr.x4plus-anime6b` | TEST-ML-001: ncnn CPU vs PyTorch fp32, 96×96 golden tile (`golden.lock`) | 64.5 dB, 63.9 dB; ≥ 40 dB on every PR (CI) |
| `face.gfpgan-1.4` | ncnn fp16 vs PyTorch fp32 (S1) | CPU 54.8 dB, Vulkan 51.4 dB |
| `face.codeformer` | ncnn fp16 vs PyTorch fp32, one real face (`test_faces`, nightly) | CPU 43.9 dB at w 0.7 (48.5 at 1.0, 40.1 at 0.5, 34.1 at 0); 252 of 256 codebook picks equal |
| `jpeg.fbcnn` | TEST-ML-001: ncnn CPU vs PyTorch fp32, 96×96 golden tile at qf 0.7 (`golden.lock`); QF estimate per tile vs whole image at qualities 10–90 (S9) | ≥ 40 dB on every PR (CI); QF within ±0.004 across tiles |
| `jpeg.fbcnn` | "jpeg" golden category: 8 Kodak photos at JPEG quality 10–50, plain pipeline vs cleanup (`tools/ml/jpeg_eval.py`, S9) | MUSIQ 75.4 vs 70.6 at q10, 77.3 vs 76.7 at q50; PSNR and SSIM higher at every quality |
| `old.scratch` | TEST-ML-001: ncnn CPU vs PyTorch fp32, 256×384 golden input (`golden.lock`); synthetic scratches (S9) | ≥ 40 dB on every PR (CI); precision 0.98, recall 0.64 at threshold 0.4 |
| `old.inpaint-migan` | TEST-ML-001: ncnn CPU vs onnxruntime fp32, 512×512 golden input (`golden.lock`); synthetic holes (S9) | ≥ 40 dB on every PR (CI); 32.5 dB inside the holes (mean fill 16.4 dB) |
| `old.lowlight-cidnet` | TEST-ML-001: the C++ HVI transform vs upstream's, the network on ncnn CPU vs PyTorch fp32, 128×128 golden tile (`golden.lock`); one run on a 384 px downscale vs the full image on a synthetic dark photo (S9) | transform within 3e-8; ≥ 40 dB on every PR (CI); 31.9 dB vs the full image |

## Known limitations

- `old.scratch` misses part of the thinnest scratches (under a pixel at the 256 px it runs at);
  `old.inpaint-migan` fills smoothly and does not recreate film grain, so a filled scratch on
  a grainy scan stays faintly visible.
- `old.lowlight-cidnet` runs on a 384 px copy of the photo: it brightens and recolours the whole
  photo but does not denoise at full size, so lifted shadows show their noise.
- `sr.x4plus-anime6b` is trained on drawings: on photos it flattens texture into flat colour
  areas.
- SR models invent plausible detail; they cannot recover text, number plates or fine patterns
  that the input does not show, and may render them wrong.
- `face.gfpgan-1.4` reconstructs a face from a prior learned on FFHQ: small or heavily degraded
  faces may come out looking like someone else, and quality differs across skin tones. Per
  subgroup (ML-BIAS-001, [docs/ml/bias-2026-10.md](docs/ml/bias-2026-10.md), 700 FairFace faces,
  ArcFace identity similarity): 0.567 overall (0.653 at the default 50% blend), 0.628 for the
  lightest skin (Monk 1) and 0.457 for the darkest (Monk 10); 0.530 for faces labelled Black
  against 0.597 for Middle Eastern. Age, gender and pose differ by ≤ 0.05. The editor's strength slider and per-face toggle
  (FR-FACE-007) keep the original available.
- `face.codeformer` replaces each face with codebook entries chosen by a transformer: at low
  fidelity (w near 0) faces are sharper but drift further from the person; fp16 changes a few
  near-tie code picks (252/256 equal), visible mostly at w 0. Same FFHQ biases as GFPGAN,
  smaller: at w 0.7, 0.603 overall, 0.645 at Monk 1 against 0.522 at Monk 10
  ([bias report](docs/ml/bias-2026-10.md)).
- `det.yunet-2023mar` runs on a 640 px copy of the photo: it can miss very small faces and
  strong profiles, which then get no face restoration.

Attribution shown in the app: About → Licenses has the Real-ESRGAN BSD-3-Clause and YuNet MIT
texts (`tools/licenses/collect.sh`); a pack's license text is shown before it is installed
(the face pack asks for acceptance).
