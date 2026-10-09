#!/usr/bin/env python3
"""Export one golden face pair (input/output, raw float32 CHW 3x512x512, range [-1,1])
from the S1 artifacts into data/golden/ (gitignored: 2 x 3 MB).

Input  = aligned face from spikes/s1-gfpgan/data/faces/<name> (same preprocessing as S1 run_backend.py)
Output = PyTorch fp32 output of the ORIGINAL GFPGAN v1.4 (spikes/s1-gfpgan/out/results/gfpgan14__torch_fp32.npy)
"""
import json, sys
from pathlib import Path
import cv2
import numpy as np

HERE = Path(__file__).resolve().parent.parent
S1 = HERE.parent / "s1-gfpgan"
name = sys.argv[1] if len(sys.argv) > 1 else "Albert_Einstein_Head_f00.png"
meta = json.loads((S1 / "out/results/gfpgan14__torch_fp32.json").read_text())
idx = meta["faces"].index(name)
ref = np.load(S1 / "out/results/gfpgan14__torch_fp32.npy", mmap_mode="r")[idx].astype(np.float32)
rgb = cv2.cvtColor(cv2.imread(str(S1 / "data/faces" / name)), cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
x = ((rgb - 0.5) / 0.5).transpose(2, 0, 1).astype(np.float32).copy()
assert x.shape == (3, 512, 512) and ref.shape == (3, 512, 512)
out = HERE / "data/golden"
out.mkdir(parents=True, exist_ok=True)
x.tofile(out / "face_in_3x512x512.f32")
np.ascontiguousarray(ref).tofile(out / "face_out_gfpgan14_3x512x512.f32")
print(f"exported {name} (index {idx}) -> {out}; out range [{ref.min():.3f}, {ref.max():.3f}]")
