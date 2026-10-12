# Models

Every model shipped in the app or offered as a download is listed here (OPS-LIC-002,
TEST-COMP-004). Weights are never committed to git; bundled files are verified against
`tools/models/models.lock`.

| Pack id | Delivery | Upstream | Weights license | Conversion | Files (SHA-256) |
|---|---|---|---|---|---|
| `sr.general-x4v3` | bundled (0.1) | [xinntao/Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) `realesr-general-x4v3` + `realesr-general-wdn-x4v3`, DNI denoise 0.5 (ADR-0015) | BSD-3-Clause, © 2021 Xintao Wang | `spikes/_shared/convert_sr.py` (PyTorch → ONNX → ncnn, S1/S2) | `model.ncnn.param` a950267a…55e5fe, `model.ncnn.bin` 8fe24682…9645aa |

Attribution shown in the app (About → Licenses): the Real-ESRGAN BSD-3-Clause license text.
