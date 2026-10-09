# Spike S3: GPU probe, correctness-checked microbenchmark, GPU blocklist, crash sentinel

Report (Russian): [`docs/spikes/S3.md`](../../docs/spikes/S3.md). Spec: 05 §2/§6/§11, ADR-0016, ADR-0017.

What is here:

| Part | Files | Depends on |
|---|---|---|
| `refocal_gpu_policy` (moves to native core) | `src/blocklist.*`, `src/builtin_blocklist.cpp`, `src/sentinel.*`, `src/tier.*` | C++20 + nlohmann/json only |
| `refocal_bench` | `src/bench.*` (microbenchmark + 8-bit metrics), `src/device_info.*` | ncnn (Vulkan) |
| `refocal-probe` CLI | `src/main.cpp` | both |
| Tests | `tests/test_blocklist.cpp`, `tests/test_sentinel.cpp`, `tests/sentinel_crash_test.sh` | none (own mini runner) |
| Experiments | `tools/run_detection.sh`, `tools/run_final.sh` (results -> `data/runs/`, gitignored), `tools/export_golden_face.py` | — |
| Community | `perf-report.yml` (draft issue form), runbook below | — |

## Build and test (desktop)

```bash
cd spikes/s3-gpu-probe
tools/fetch_deps.sh                         # nlohmann/json 3.11.3 -> third_party/ (gitignored), SHA-256 checked
cmake -S . -B build -G Ninja && cmake --build build
ctest --test-dir build --output-on-failure  # unit tests + crash-sentinel e2e (uses Vulkan device 1)
```

The golden face pair (GFPGAN, 2 x 3 MB, gitignored) is exported from the S1 artifacts:

```bash
../s1-gfpgan/.venv/bin/python tools/export_golden_face.py   # -> data/golden/face_{in,out_gfpgan14}_3x512x512.f32
```

On the shared spike machine every timed run goes through the bench lock:

```bash
flock /tmp/claude-1000/refocal-bench.lock build/refocal-probe probe --threads 6 --face
```

## CLI

```
refocal-probe info                         # host + Vulkan devices (JSON)
refocal-probe probe [options]              # full probe -> <work-dir>/report.json
refocal-probe stage ...                    # one simulated app GPU stage with crash sentinel
refocal-probe match ...                    # evaluate blocklist rules for a given GPU identity (offline)
refocal-probe calib --backend B --tile T   # 1 MP (1152x864) tiled run, inference only (threshold calibration)
refocal-probe bench-one ...                # internal: one (model, backend) in a child process
```

`probe` options:

| Option | Meaning |
|---|---|
| `--backends vk0-fp16,vk0-fp32,cpu-fp16` | default: every Vulkan device in fp16 and fp32 + `cpu-fp16` |
| `--face` / `--face-only` | also / only GFPGAN on the golden face |
| `--face-model gfpgan14s\|gfpgan14` | ADR-0023 rewrite (default) or the original graph (fp16 garbage, for validation) |
| `--runs 5 --face-runs 3 --warmup 1` | timed runs after warm-up |
| `--threads N` | CPU threads (default: big cores; on x86 with SMT pass physical cores) |
| `--data DIR` | flat on-device layout (see runbook) instead of repo paths |
| `--blocklist FILE` (repeatable) | extra blocklist source (manifest format); built-in is always loaded unless `--no-builtin` |
| `--ignore-blocklist` | benchmark blocklisted backends too (diagnostics) |
| `--record-wrong-output` | a GPU `wrong_output` adds a local rule (05 §11 "провал бенчмарка") |
| `--corrupt BACKEND:MODE` | synthetic corruption of that backend's output: `zero noise nan block32 half swap_rb offset` |
| `--crash-backend B [--crash abort\|segv]` | the child dies in the middle of backend B (isolation test) |
| `--max-run-ms MS` | warm-up slower than MS -> `too_slow` without timed runs (NFR-PERF-009 budget guard) |
| `--no-isolate` | run in-process (default: each backend in a child process; crash/hang = status, not probe death) |
| `--work-dir DIR --state-dir DIR --out FILE` | outputs; state dir holds `sentinel.json` and `local_blocklist.json` |
| `--min-psnr 35 --max-bad-frac 0.001` | correctness gate |
| `--t2-ms 25 --t1-ms 80 --t0-ms 280` | tier thresholds (compact SR, ms per 128x128 tile) |

Each backend runs in a child process (`fork` + `exec` of itself) with a timeout (`--timeout`, 300 s).
A child that dies by a signal is `crash`; one that does not finish is `timeout`. Both are written
to the local blocklist as *confirmed* crashes (pinned to driver version + model).

## Report schema (`refocal-probe/1`)

```jsonc
{
  "schema": "refocal-probe/1", "probe_version": "0.3.0", "ncnn_version": "1.0.20261009", "timestamp": "...Z",
  "host": { "platform": "android|linux", "os_version": "34 (Android API level) | kernel", "os_build": "fingerprint",
            "device_model": "...", "soc": "ro.soc.manufacturer + ro.soc.model | CPU model",
            "cpu_model": "...", "cpu_count": 8, "big_cpu_count": 4, "little_cpu_count": 4,
            "isa": ["neon", "asimdhp(fp16)", "asimddp(dotprod)", "i8mm"], "ram_gb": 7.4, "ram_avail_gb": 3.1 },
  "gpus": [ { "index": 0, "name": "Mali-G68 MC4", "vendor": "ARM", "vendor_id": "0x13B5", "device_id": "0x...",
              "type": "integrated|discrete|cpu|virtual", "driver_name": "...",
              "driver_version_raw": "0x...", "driver_version": "r38p1", "api_version": "1.3.247",
              "fp16_storage": true, "fp16_arithmetic": true, "int8_storage": true, "int8_arithmetic": true,
              "device_local_mb": 7000, "memory_heaps": [ { "size_mb": 7000, "device_local": true } ] } ],
  "config": { "runs": 5, "face_runs": 3, "warmup": 1, "isolate": true,
              "gate": { "min_psnr": 35, "max_bad_frac": 0.001, "bad_level_u8": 16 },
              "thresholds": { "t0_ram_gb": 3.3, "t2_ram_gb": 7.0, "t2_tile128_ms": 25, "t1_tile128_ms": 80,
                              "t0_tile128_ms": 280, "require_soc_for_t2": false } },
  "blocklist_sources": [ { "source": "builtin|<file>|local", "rules": 4, "errors": [], "warnings": [], "revoke": [] } ],
  "sentinel_startup": { "found": false, "key": "", "exit_reason": "unknown", "hits": 0,
                        "blocked_now": false, "quarantined_now": false, "note": "" },
  "results": [ {
      "backend": "vk0-fp16", "gpu_index": 0, "precision": "fp16", "model": "sr.general-x4v3@dn050",
      "status": "ok | wrong_output | error | crash | timeout | too_slow | skipped_blocklist | skipped_quarantine",
      "reason": "nan_inf,psnr<35,bad_frac (wrong_output only)", "error": "(error/crash/timeout)",
      "fp16_effective": true, "threads": 4,
      "load_ms": 580, "first_run_ms": 17, "median_ms": 9.9, "min_ms": 9.5, "max_ms": 10.4, "runs": 5,
      "tile128_median_ms": 5.3,                          // compact SR only: 128x128 crop, timing only
      "psnr_db": 54.76, "bad_frac": 0.0, "max_abs_err_u8": 2, "nonfinite": 0, "out_min": 0.0, "out_max": 1.0,
      "total_ms": 700, "wall_ms": 803, "peak_rss_mb": 271,  // wall/peak RSS of the child process
      "blocklist": { "action": "none|gpu_fp32|cpu|disable", "rules": [ { "id": "...", "source": "...", "reason": "..." } ] }
  } ],
  "summary": { "healthy_sr_backends": ["vk0-fp16", "..."], "selected_backend": "vk0-fp16",
               "selected_tile128_ms": 5.3, "soc_in_t2_list": -1, "tier": "T2", "tier_reasons": ["..."],
               "below_t0_budget": false, "tier_if_only_backend": { "cpu-fp16": "T0" },
               "routing": { "sr.general-x4v3": { "backend": "vk0-fp16", "median_ms": 9.9 },
                            "face.gfpgan-1.4": { "backend": "vk0-fp16", "median_ms": 33.8 } },
               "probe_wall_ms": 200976 }
}
```

Correctness gate per (model, backend): output shape matches, no NaN/Inf, PSNR >= 35 dB on 8-bit
values (`round(x*255)`, for GFPGAN `round((x+1)*127.5)`), and at most 0.1 % of 8-bit values
off by more than 16 levels (`bad_frac`, catches localized corruption that a global PSNR misses).
Golden references are PyTorch fp32 outputs (compact SR: `_shared/models/golden_out_dn050_*`;
GFPGAN: the *original* model, S1).

The selected backend is the **fastest healthy** one (not "GPU first"): llvmpipe-class drivers and
slow GPUs lose to the CPU automatically.

## Blocklist format

Manifest field `gpu_blocklist` (manifest.schema.json) plus optional extensions proposed in S3:

```json
{
  "gpu_blocklist": [
    {"id": "m-2026-001", "vendor": "ARM", "device_regex": "Mali-G52.*", "driver_max": "r26p0",
     "models": ["face.*"], "action": "cpu", "reason": "fp16 NaN in modulated conv"},
    {"id": "m-2026-002", "vendor": "Qualcomm", "device_regex": "Adreno \\(TM\\) 6[0-4][0-9]",
     "api_max": "1.1.86", "models": ["*"], "action": "cpu", "reason": "example: old driver"},
    {"id": "m-2026-003", "vendor": "Samsung", "device_regex": ".*Xclipse 9[0-9]0", "platform": "android",
     "os_min": "34", "os_max": "35", "models": ["face.gfpgan-1.4@*"], "action": "gpu_fp32"}
  ],
  "gpu_blocklist_revoke": ["bi-powervr-all"]
}
```

| Field | Rule |
|---|---|
| `vendor` | canonical name or alias, case-insensitive (`Qualcomm`/`Adreno`, `ARM`/`Mali`, `ImgTec`/`PowerVR`, `Apple`, `Samsung`/`Xclipse`, `AMD`, `NVIDIA`, `Intel`, `Mesa`, `Google`/`SwiftShader`, `Huawei`), hex `0x13B5`, or `*` |
| `device_regex` | ECMAScript, **full match**, case-insensitive, on `VkPhysicalDeviceProperties.deviceName`. `"Mali-G52"` does not match `"Mali-G52 MC2"`: write `"Mali-G52.*"`. Invalid regex rejects only that rule |
| `driver_min` / `driver_max` | inclusive, **prefix comparison** on the vendor-decoded driver version: `"r26"` covers all r26pX, `"580"` all 580.x |
| `os_min` / `os_max` | Android: API level (`"34"`); iOS: version (`"17.4"` covers 17.4.x). Unknown OS version -> a bounded rule does not apply |
| `api_max` (ext.) | Vulkan `apiVersion` upper bound (ncnn's own quirk table keys on it) |
| `platform` (ext.) | `android` / `ios` / omitted = any |
| `models` | globs (`*`, `?`) over `"<pack id>@<version>"`, e.g. `face.*`, `sr.general-x4v3`, `face.gfpgan-1.4@*` |
| `action` | `cpu`, `disable`, `gpu_fp32` (ext.: keep GPU, fp32 only). Strongest wins: disable > cpu > gpu_fp32 |
| `id` (ext.) | stable id; needed for `gpu_blocklist_revoke` and telemetry. Default `<source>#<index>` |
| `gpu_blocklist_revoke` (ext.) | manifest can revoke built-in/manifest rule ids (false positive fix without a release). Local rules cannot be revoked remotely |

Sources are merged as a union: built-in (compiled in) + manifest (signed, optional) + local
(crash sentinel, benchmark failure). Unknown fields are ignored with a warning (forward compatible).

### Driver version encoding (`VkPhysicalDeviceProperties.driverVersion`)

| Vendor | Packing | Human form | Verified |
|---|---|---|---|
| NVIDIA `0x10DE` | 10.8.8.6 bits | `595.99.02` | yes: matches `nvidia-smi` on the RTX 3060 |
| Mesa (Intel ANV, llvmpipe, RADV, Turnip, Panfrost) | `VK_MAKE_VERSION` 10.10.12 | `26.0.8` (Mesa version) | yes (Intel UHD 730, llvmpipe) |
| Intel on Windows | 18.14 bits | `101.4255` | no (not a target) |
| Qualcomm `0x5143` (proprietary) | `VK_MAKE_VERSION`, major is 512 | `512.615.0`, minor = driver release (`V@0615`) | no -> S3b |
| ARM `0x13B5` (proprietary) | `VK_MAKE_VERSION(rX, pY, 0)` | `r38p1` | no -> S3b |
| ImgTec `0x1010` | `VK_MAKE_VERSION` (exact meaning unknown) | `1.x.y` | no -> S3b |
| Samsung Xclipse `0x144D` | presumably `VK_MAKE_VERSION` | ? | no -> S3b |
| Apple | no Vulkan (Core ML path): rules use `platform: ios` + `os_max` and the chip name | `17.4` | n/a |

The probe stores the raw value (`driver_version_raw`) next to the decoded form, so S3b reports
can confirm the packing per vendor without a new build.

## Crash sentinel (ADR-0016)

`<state>/sentinel.json` is written (tmp + fsync + rename) before a GPU stage and removed after it.
On start a leftover sentinel becomes a hit for key `vendor:device:driverVersion|model`.

| Previous exit | Action |
|---|---|
| `native_crash` (Android `ApplicationExitInfo` REASON_CRASH_NATIVE/ANR, or probe parent saw a signal/hang) | permanent local rule immediately |
| `os_kill` (LMK, user swipe: REASON_LOW_MEMORY, USER_REQUESTED, ...) | ignored |
| `unknown` (iOS, Android 10) | hit 1 -> CPU for this session only (quarantine), hit 2 in a row -> permanent |

A successful GPU stage resets the counter (consecutive semantics). Permanent local rules pin the
exact driver version (`driver_min == driver_max`), so a driver update lifts them. `--no-quarantine`
gives the strict ADR-0016 behaviour (GPU retried until the 2nd hit).

## Cross-compile for Android (arm64-v8a, API 29)

Not built in S3: no Android NDK on the spike machine. Commands:

```bash
# 1. NDK r26+ (sdkmanager "ndk;27.2.12479018") and the prebuilt ncnn Android Vulkan package
#    matching the desktop ncnn version: https://github.com/Tencent/ncnn/releases -> ncnn-<ver>-android-vulkan.zip
export ANDROID_NDK=$HOME/Android/Sdk/ndk/27.2.12479018
export NCNN_ANDROID=$HOME/ncnn-<ver>-android-vulkan   # same ncnn version as the desktop build
# 2. configure + build (same as tools/build_android.sh)
cmake -S . -B build-android-arm64 -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK/build/cmake/android.toolchain.cmake \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-29 -DANDROID_STL=c++_static \
  -DCMAKE_BUILD_TYPE=Release -Dncnn_DIR=$NCNN_ANDROID/arm64-v8a/lib/cmake/ncnn
cmake --build build-android-arm64 --target refocal-probe test_blocklist test_sentinel
```

Android specifics already in the code: `__system_property_get` for `ro.build.version.sdk`,
`ro.soc.model`, `ro.product.model`, fingerprint; `-static-libstdc++ -static-openmp` so one binary
can be pushed; `TMPDIR`/`/data/local/tmp` in tests; `/proc/self/exe` for child processes.

## Community runbook

### A. adb (developer options, ~5 minutes)

1. Enable *Developer options* -> *USB debugging*, connect the phone, `adb devices` shows it.
   Battery > 50 %, phone cool, close other apps.
2. Download `refocal-probe-android-arm64.zip` from the release page (contains the binary, models and golden files) and unpack.
3. Push and run:

```bash
adb shell mkdir -p /data/local/tmp/refocal
adb push refocal-probe sr_compact_dn050.ncnn.param sr_compact_dn050.ncnn.bin \
         golden_in_3x160x160.f32 golden_out_dn050_3x640x640.f32 /data/local/tmp/refocal/
# optional face test (+180 MB): gfpgan14s.ncnn.param gfpgan14s.ncnn.bin face_in_3x512x512.f32 face_out_gfpgan14_3x512x512.f32
adb shell chmod +x /data/local/tmp/refocal/refocal-probe
adb shell "cd /data/local/tmp/refocal && ./refocal-probe probe --data . --work-dir out --ignore-blocklist" 2>&1 | tee probe-console.txt
#   add --face if you pushed the face files
adb pull /data/local/tmp/refocal/out/report.json
adb shell getprop > getprop.txt   # optional, helps with SoC/driver identification
```

4. If the phone froze or rebooted, reconnect and run the same command again: the state directory
   remembers the crash (`sentinel_startup` in the report). Send both console outputs.
5. Open an issue with the *Device report* form (`perf-report.yml`), attach `report.json` and
   `probe-console.txt`. No photos are involved; the report contains device model, SoC, GPU,
   driver, Android version/fingerprint, RAM and timings.
6. Clean up: `adb shell rm -rf /data/local/tmp/refocal`.

### B. In-app (later: debug/profile builds, "Benchmark" screen, 05 §10)

Settings -> About -> Diagnostics -> *GPU probe* runs the same code (`refocal_bench` +
`refocal_gpu_policy`) in a separate process, shows the tier/backends and offers *Share report*
(Android share sheet / iOS share sheet) with the same JSON. The issue form accepts both.

### What maintainers do with a report

- `status != ok` on a GPU backend with a valid CPU result -> candidate blocklist rule
  (`vendor`, `device_regex` from `name`, `driver_max` from `driver_version`, models from `model`).
- `crash`/`timeout` -> rule with action `cpu` for that model; reproduce with a second report.
- Timings -> tier threshold calibration (`tile128_median_ms` vs the device's tier in device-matrix.md).
