"""Run GFPGAN on all aligned faces with one backend; save outputs, latency and peak RSS.

Usage: run_backend.py <backend> [--runs N]
Backends: torch_fp32, ort_fp32, ncnn_cpu_fp32, ncnn_cpu_fp16, ncnn_vk<dev>_fp16, ncnn_vk<dev>_fp32
Each backend runs in its own process so that ru_maxrss is per-backend.
"""
import argparse
import json
import resource
import statistics
import time
from pathlib import Path

import cv2
import numpy as np

HERE = Path(__file__).resolve().parent
FACES = HERE / "data" / "faces"
MODELS = HERE / "out" / "models"
RESULTS = HERE / "out" / "results"


def load_faces():
    paths = sorted(FACES.glob("*.png"))
    batch = []
    for p in paths:
        rgb = cv2.cvtColor(cv2.imread(str(p)), cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0
        batch.append(((rgb - 0.5) / 0.5).transpose(2, 0, 1).copy())  # CHW, [-1, 1]
    return paths, batch


def make_runner(backend: str, threads: int, model_name: str):
    if backend == "torch_fp32":
        import torch
        from gfpgan_model import load_gfpgan
        torch.set_num_threads(threads)
        model = load_gfpgan(static_modconv=model_name.endswith("s"))

        def run(x):
            with torch.no_grad():
                return model(torch.from_numpy(x)[None]).numpy()[0]
        return run

    if backend == "ort_fp32":
        import onnxruntime as ort
        so = ort.SessionOptions()
        so.intra_op_num_threads = threads
        sess = ort.InferenceSession(str(MODELS / f"{model_name}.onnx"), so, providers=["CPUExecutionProvider"])
        return lambda x: sess.run(None, {"input": x[None]})[0][0]

    if backend.startswith("ncnn_"):
        import ncnn
        _, dev, prec = backend.split("_")
        net = ncnn.Net()
        fp16 = prec == "fp16"
        net.opt.use_fp16_packed = fp16
        net.opt.use_fp16_storage = fp16
        net.opt.use_fp16_arithmetic = fp16
        net.opt.num_threads = threads
        import os
        lowmem = os.environ.get("NCNN_LOWMEM", "")
        if "nowino" in lowmem:
            net.opt.use_winograd_convolution = False
        if "nosgemm" in lowmem:
            net.opt.use_sgemm_convolution = False
        if "nopack" in lowmem:
            net.opt.use_packing_layout = False
        if dev.startswith("vk"):
            net.opt.use_vulkan_compute = True
            net.set_vulkan_device(int(dev[2:]))
        net.load_param(str(MODELS / f"{model_name}.ncnn.param"))
        net.load_model(str(MODELS / f"{model_name}.ncnn.bin"))

        def run(x):
            ex = net.create_extractor()
            ex.input("in0", ncnn.Mat(x).clone())
            _, out = ex.extract("out0")
            return np.array(out).copy()
        return run

    raise SystemExit(f"unknown backend {backend}")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("backend")
    ap.add_argument("--runs", type=int, default=3, help="timed runs on the first face (after 1 warm-up)")
    ap.add_argument("--threads", type=int, default=8)
    ap.add_argument("--model", default="gfpgan14", help="gfpgan14 (original) or gfpgan14s (static modconv)")
    args = ap.parse_args()

    paths, batch = load_faces()
    t0 = time.perf_counter()
    run = make_runner(args.backend, args.threads, args.model)
    load_s = time.perf_counter() - t0

    t0 = time.perf_counter()
    run(batch[0])  # warm-up (includes Vulkan pipeline compilation)
    first_s = time.perf_counter() - t0

    times = []
    for _ in range(args.runs):
        t0 = time.perf_counter()
        run(batch[0])
        times.append(time.perf_counter() - t0)

    outputs = np.stack([run(x) for x in batch]).astype(np.float32)
    RESULTS.mkdir(parents=True, exist_ok=True)
    import os
    tag = f"{args.model}__{args.backend}" + (f"__{os.environ['NCNN_LOWMEM']}" if os.environ.get("NCNN_LOWMEM") else "")
    np.save(RESULTS / f"{tag}.npy", outputs)
    stats = {
        "model": args.model,
        "backend": args.backend,
        "threads": args.threads,
        "load_s": round(load_s, 3),
        "first_run_s": round(first_s, 3),
        "median_s": round(statistics.median(times), 3),
        "min_s": round(min(times), 3),
        "peak_rss_mb": round(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024, 1),
        "nan_or_inf": int((~np.isfinite(outputs)).sum()),
        "faces": [p.name for p in paths],
    }
    (RESULTS / f"{tag}.json").write_text(json.dumps(stats, indent=2))
    print(json.dumps({k: v for k, v in stats.items() if k != "faces"}))


if __name__ == "__main__":
    main()
