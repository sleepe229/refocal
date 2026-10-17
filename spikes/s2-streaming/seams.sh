#!/usr/bin/env bash
# Seam experiment: tiled vs whole-image single pass on a ~1 MP image.
# usage: ./seams.sh [backend] [fp16]   (default: cpu 0)
set -euo pipefail
cd "$(dirname "$0")"
BE=${1:-cpu}; FP=${2:-0}
IN=data/stockholm_1mp.jpg
OUT=out/seams_${BE}_fp${FP}; mkdir -p "$OUT"
LOCK="flock /tmp/refocal-bench.lock"
run() { # name args...
  local n=$1; shift
  $LOCK build/s2_stream --input $IN --job "$OUT/job" --backend $BE --fp16 $FP --threads 8 \
    --out-png "$OUT/$n.png" --png-level 1 --stats "$OUT/$n.json" "$@" 2>/dev/null
}
run whole --tile 0
for T in 128 256 512; do
  for P in 0 8 16 32; do run t${T}_p${P}_f0 --tile $T --pad $P --feather 0; done
  run t${T}_p16_f8 --tile $T --pad 16 --feather 8
done
../s1-gfpgan/.venv/bin/python -I seam_metrics.py "$OUT" | tee "$OUT/summary.txt"
