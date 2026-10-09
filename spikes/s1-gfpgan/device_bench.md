# S1b — latency on real devices

Desktop results only approximate phones. These steps measure GFPGAN (rewritten, `gfpgan14s`)
on the reference devices from `docs/spec/appendix/device-matrix.md`.

## Android (ncnn, Vulkan and CPU)

`benchncnn` measures latency from the `.param` alone (weights are zero-filled, which does not
affect speed). Build it once with the NDK:

```bash
git clone --depth 1 https://github.com/Tencent/ncnn && cd ncnn && git submodule update --init
mkdir build-android && cd build-android
cmake -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
      -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-29 \
      -DNCNN_VULKAN=ON -DNCNN_BUILD_BENCHMARK=ON -DNCNN_BUILD_EXAMPLES=OFF -DNCNN_BUILD_TOOLS=OFF ..
make -j$(nproc) benchncnn
```

Prepare the param: benchncnn needs a fixed input shape, so patch the `Input` line of
`gfpgan14s.ncnn.param` to `0=512 1=512 2=3` and name the file `gfpgan.param`.

```bash
adb push benchmark/benchncnn /data/local/tmp/
adb push gfpgan.param /data/local/tmp/
adb shell 'cd /data/local/tmp && ./benchncnn 4 $(nproc) 0 0 0 param=gfpgan.param shape=[512,512,3]'   # Vulkan GPU 0
adb shell 'cd /data/local/tmp && ./benchncnn 4 4 2 -1 0 param=gfpgan.param shape=[512,512,3]'          # CPU, big cores, 4 threads
adb shell dumpsys meminfo <pid>   # or watch VmHWM in /proc/<pid>/status during the run
```

Record: device, SoC, GPU, Android version, `min/max/avg` ms, peak memory, thermal state.
Add the row to the table in `docs/spikes/S1.md` (section "Мобильные устройства").

**Correctness on device** (fp16 NaN/garbage is driver-specific): run the full app pipeline
or `run_backend.py`-equivalent on device once the native core exists (0.1); until then,
compare one output against `out/results/gfpgan14__torch_fp32.npy` with a small JNI harness.

## iOS (Core ML)

Requires a Mac with Xcode 16+ and an iPhone (A14 and A17 per the matrix).

1. Copy `out/models/gfpgan14s.mlpackage` to the Mac, open it in Xcode.
2. **Performance** tab → choose the connected device → compute units `All`, then `CPU and GPU`.
   Xcode reports load time, median prediction latency and which ops run on ANE/GPU/CPU.
3. **Predictions** tab: drop an aligned 512×512 face (from `data/faces/`), visually compare
   with the PyTorch output; for numbers, use `coremltools` on macOS:

```python
import coremltools as ct, numpy as np
m = ct.models.MLModel("gfpgan14s.mlpackage", compute_units=ct.ComputeUnit.ALL)
y = m.predict({"input": x})["output"]   # x: (1,3,512,512) float32 in [-1,1]
```

Pass criteria: PSNR ≥ 35 dB vs the PyTorch fp32 reference, no NaN, latency within NFR-PERF-003.
