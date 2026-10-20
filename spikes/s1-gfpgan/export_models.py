"""Export GFPGAN v1.4 to TorchScript (for pnnx -> ncnn) and ONNX (opset 17, static 1x3x512x512)."""

import argparse
import time
from pathlib import Path

import torch
from gfpgan_model import load_gfpgan

HERE = Path(__file__).resolve().parent
OUT = HERE / "out" / "models"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--static-modconv", action="store_true", help="export the static-weight variant (gfpgan14s)"
    )
    args = ap.parse_args()
    name = "gfpgan14s" if args.static_modconv else "gfpgan14"
    OUT.mkdir(parents=True, exist_ok=True)
    model = load_gfpgan(static_modconv=args.static_modconv)
    x = torch.rand(1, 3, 512, 512) * 2 - 1

    t = time.time()
    with torch.no_grad():
        ts = torch.jit.trace(model, x, check_trace=False)
    ts_path = OUT / f"{name}.pt"
    ts.save(str(ts_path))
    print(
        f"TorchScript: {ts_path.name} {ts_path.stat().st_size / 1e6:.1f} MB "
        f"({time.time() - t:.1f}s)"
    )

    t = time.time()
    onnx_path = OUT / f"{name}.onnx"
    torch.onnx.export(
        model,
        (x,),
        str(onnx_path),
        input_names=["input"],
        output_names=["output"],
        opset_version=17,
        do_constant_folding=True,
        dynamo=False,
    )
    print(
        f"ONNX: {onnx_path.name} {onnx_path.stat().st_size / 1e6:.1f} MB ({time.time() - t:.1f}s)"
    )

    import onnx

    m = onnx.load(str(onnx_path))
    onnx.checker.check_model(m)
    ops = sorted({n.op_type for n in m.graph.node})
    print(f"ONNX nodes: {len(m.graph.node)}, op types ({len(ops)}): {', '.join(ops)}")


if __name__ == "__main__":
    main()
