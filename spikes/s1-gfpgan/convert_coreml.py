"""Convert GFPGAN (static modconv + fp16-safe scaling) to a Core ML mlprogram (fp16, iOS 16).

Runs on Linux: conversion works, prediction requires macOS/iOS (done on device in a follow-up).
"""

import collections
import time
from pathlib import Path

import coremltools as ct
import torch
from gfpgan_model import load_gfpgan

HERE = Path(__file__).resolve().parent
OUT = HERE / "out" / "models"


def main() -> None:
    model = load_gfpgan(static_modconv=True)
    x = torch.rand(1, 3, 512, 512) * 2 - 1
    with torch.no_grad():
        traced = torch.jit.trace(model, x, check_trace=False)

    t = time.time()
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="input", shape=(1, 3, 512, 512))],
        outputs=[ct.TensorType(name="output")],
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS16,
    )
    path = OUT / "gfpgan14s.mlpackage"
    mlmodel.save(str(path))
    size = sum(f.stat().st_size for f in path.rglob("*") if f.is_file())
    print(f"Core ML: {path.name} {size / 1e6:.1f} MB ({time.time() - t:.1f}s)")

    prog = mlmodel._mil_program
    ops = collections.Counter(op.op_type for f in prog.functions.values() for op in f.operations)
    print("MIL ops:", ", ".join(f"{k}={v}" for k, v in sorted(ops.items(), key=lambda kv: -kv[1])))
    dyn = [
        op.name
        for f in prog.functions.values()
        for op in f.operations
        if op.op_type == "conv"
        and op.inputs["weight"].op is not None
        and op.inputs["weight"].op.op_type != "const"
    ]
    print(f"conv ops with non-constant weights: {len(dyn)}")


if __name__ == "__main__":
    main()
