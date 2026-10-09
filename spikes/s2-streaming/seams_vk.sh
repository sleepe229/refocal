#!/usr/bin/env bash
# Reduced seam set on Vulkan device 1 (Intel UHD 730), fp16.
set -euo pipefail
cd "$(dirname "$0")"
IN=data/stockholm_1mp.jpg; OUT=out/seams_vk1_fp1; mkdir -p "$OUT"
LOCK="flock /tmp/claude-1000/refocal-bench.lock"
run() { local n=$1; shift
  $LOCK build/s2_stream --input $IN --job "$OUT/job" --backend vk1 --fp16 1 \
    --out-png "$OUT/$n.png" --png-level 1 --stats "$OUT/$n.json" "$@" 2>/dev/null; }
run whole --tile 0
run t128_p16_f0 --tile 128 --pad 16
run t128_p16_f8 --tile 128 --pad 16 --feather 8
run t256_p16_f0 --tile 256 --pad 16
run t256_p16_f8 --tile 256 --pad 16 --feather 8
run t256_p32_f0 --tile 256 --pad 32
run t256_p8_f0 --tile 256 --pad 8
rm -rf "$OUT/job"
../s1-gfpgan/.venv/bin/python -I seam_metrics.py "$OUT" | tee "$OUT/summary.txt"
