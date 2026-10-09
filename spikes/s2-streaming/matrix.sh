#!/usr/bin/env bash
# S2 benchmark matrix on the 12 MP image. Every timed run holds the shared bench lock.
set -uo pipefail
cd "$(dirname "$0")"
IN=${IN:-data/avignon_12mp.jpg}
OUT=out/matrix; mkdir -p "$OUT"
LOCK="flock /tmp/claude-1000/refocal-bench.lock"
run() { # name args...
  local n=$1; shift
  if [[ -f "$OUT/$n.json" ]]; then echo "skip $n"; return; fi
  echo "=== $n $*"
  rm -rf out/job_m
  $LOCK build/s2_stream --input "$IN" --job out/job_m --threads 8 \
     --out-jpeg "$OUT/$n.jpg" --out-preview "$OUT/${n}_preview.jpg" --stats "$OUT/$n.json" "$@" \
     2> "$OUT/$n.log" || echo "FAILED $n"
  tail -1 "$OUT/$n.log" | head -1; grep "done:" "$OUT/$n.log"
  rm -f "$OUT/$n.jpg"  # keep disk usage low; sizes are in the json
}
# x4, raw
for BE in vk0 vk1 cpu; do
  for T in 128 256 512; do
    extra=()
    if [[ ( $BE == cpu && $T == 128 ) || ( $BE != cpu && $T == 256 ) ]]; then extra=(--out-png "$OUT/x4_${BE}_t${T}_raw.png"); fi
    run x4_${BE}_t${T}_raw --scale 4 --tile $T --backend $BE "${extra[@]}"
    rm -f "$OUT"/*.png
  done
done
# x4, lz4 (T0-like, T1-like, desktop GPU)
run x4_cpu_t128_lz4 --scale 4 --tile 128 --backend cpu --lz4
run x4_vk1_t256_lz4 --scale 4 --tile 256 --backend vk1 --lz4
run x4_vk0_t256_lz4 --scale 4 --tile 256 --backend vk0 --lz4
# I/O ablations on the fastest backend (I/O share is largest there)
run x4_vk0_t256_raw_syncio --scale 4 --tile 256 --backend vk0 --sync-io
run x4_vk0_t256_raw_nofsync --scale 4 --tile 256 --backend vk0 --no-fsync
run x4_vk0_t256_raw_png1 --scale 4 --tile 256 --backend vk0 --out-png "$OUT/png1.png" --png-level 1; rm -f "$OUT"/*.png
# x2 (x4 + area /2 per band) and fast 2x (input /2 then x4)
for BE in vk0 vk1 cpu; do
  for T in 128 256; do run x2_${BE}_t${T}_raw --scale 2 --tile $T --backend $BE; done
  T=$([[ $BE == cpu ]] && echo 128 || echo 256)
  run fast2_${BE}_t${T}_raw --scale fast2 --tile $T --backend $BE
done
run x2_vk1_t256_lz4 --scale 2 --tile 256 --backend vk1 --lz4
# CPU fp16 storage off (x86 has no fp16 arithmetic; storage only)
run x4_cpu_t128_raw_fp32 --scale 4 --tile 128 --backend cpu --fp16 0
rm -rf out/job_m
echo MATRIX DONE
