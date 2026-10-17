# S2 — streaming SR through an on-disk BandStore

Spike for Refocal: 12 MP → ×4 (192 MP, 576 MB RGB8, never held in memory) → JPEG/PNG,
streamed through an on-disk BandStore with checkpoint/resume. The report (in Russian) is
[`docs/spikes/S2.md`](../../docs/spikes/S2.md).

## Layout

| File | Purpose |
|---|---|
| `src/main.cpp` | `s2_stream` CLI: decode → tiled SR (band = row of tiles) → BandStore → preview → JPEG/PNG export |
| `src/sha256.h` | SHA-256 for `model_sha256` / `recipe_hash` in `checkpoint.json` |
| `matrix.sh` | Benchmark matrix on the 12 MP image (→ `out/matrix/*.json`) |
| `seams.sh`, `seam_metrics.py` | Tiled vs whole-image output, PSNR and NFR-QLT-003 boundary-gradient metrics |
| `resume_test.sh` | Reference run vs. `kill -9` mid-way + `--resume`; checks byte-identical outputs |
| `summarize.py` | Builds result tables from `out/matrix/*.json` |
| `extras.sh` | Follow-ups: cold-read export, iGPU seams, resume tests, SIMD JPEG reference |
| `seams_vk.sh` | Reduced seam set on Vulkan device 1 (fp16) |
| `jpeg_simd_ref.py` | JPEG q92 speed of a 192 MP image with SIMD libjpeg-turbo (OpenCV), reference only |

## Build

Uses the prebuilt dependencies in `spikes/_deps` (ncnn static with Vulkan, libjpeg-turbo static
built **without SIMD**, lz4 static) and system libpng 1.6.

```sh
cd spikes/s2-streaming
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build
```

## Test data (not in git, `spikes/**/data/` is ignored)

```sh
mkdir -p data
UA="RefocalSpike/0.1 (research spike)"
curl -L -A "$UA" -o data/avignon_12mp.jpg \
  'https://upload.wikimedia.org/wikipedia/commons/1/12/Avignon_-_Rue_de_la_Carreterie_-_Baladine.jpg'
curl -L -A "$UA" -o data/stockholm_1mp.jpg \
  'https://upload.wikimedia.org/wikipedia/commons/5/55/Stockholm_%2819097231126%29.jpg'
```

| File | Size | Source | License |
|---|---|---|---|
| `avignon_12mp.jpg` | 4000×3000, Pixel 9a | [Commons: Avignon - Rue de la Carreterie - Baladine.jpg](https://commons.wikimedia.org/wiki/File:Avignon_-_Rue_de_la_Carreterie_-_Baladine.jpg), Romainbehar | CC0 |
| `stockholm_1mp.jpg` | 1280×960, LG-E440 | [Commons: Stockholm (19097231126).jpg](https://commons.wikimedia.org/wiki/File:Stockholm_(19097231126).jpg), fotokoci (Flickr) | CC0 |

## Usage

```sh
build/s2_stream --input data/avignon_12mp.jpg --job out/job \
  --scale 4 --tile 128 --pad 16 --backend cpu --threads 8 \
  --out-jpeg out/x4.jpg --out-png out/x4.png --out-preview out/preview.jpg --stats out/x4.json
# after a crash / kill -9:
build/s2_stream <same args> --resume
```

Key options: `--tile T` (core tile in input px; network input is `T+2·pad`; `0` = whole image),
`--pad P` (default 16), `--feather F` (output px, default 0), `--scale 4|2|fast2`,
`--backend cpu|vkN`, `--fp16 0|1`, `--lz4`, `--sync-io`, `--no-fsync`, `--drop-cache`,
`--png-level L`.

BandStore layout: `job/bands/NNNN.raw` (RGB8 rows, no header) or `NNNN.lz4` (24-byte header +
LZ4 block), `NNNN.tail` (feather only: the band's prediction of the next band's first F rows),
`job/checkpoint.json`. Every file is written to `*.tmp`, fsynced, renamed, then the directory is
fsynced; the checkpoint is updated last. Band writing runs on a separate thread (depth 1, i.e. at
most two bands in RAM); `--sync-io` disables the overlap.

Peak RSS is read from `VmHWM`; the HWM is reset (`/proc/self/clear_refs` = 5) at every stage
boundary, so `stage_peak_mb` in the stats JSON is a per-stage peak and `peak_rss_mb` is the max.

## Reproduce

Timed runs share the machine with other benchmarks, so every timed command is wrapped in
`flock /tmp/refocal-bench.lock` (the scripts do this).

```sh
./matrix.sh                                   # ~1 h; results in out/matrix/
../s1-gfpgan/.venv/bin/python -I summarize.py out/matrix
./seams.sh cpu 0                              # seams on the 1 MP image, CPU fp32
./seams_vk.sh                                 # Intel UHD 730, fp16 (compare against the CPU
                                              # reference: the single-pass whole image on this
                                              # GPU is corrupted, see docs/spikes/S2.md §6.4)
./resume_test.sh cpu_t128 --tile 128 --backend cpu
KILL_DELAY_MAX=10 ./resume_test.sh vk1_t256_lz4 --tile 256 --backend vk1 --lz4
./extras.sh                                   # everything after the matrix
```
