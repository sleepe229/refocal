#!/usr/bin/env bash
# S3 detection experiments (desktop). Every timed run is serialized with the shared bench lock.
set -u
cd "$(dirname "$0")/.."
P=build/refocal-probe
L="flock /tmp/refocal-bench.lock"
mkdir -p data/runs
# 1) real garbage: original GFPGAN graph (fp16 overflow -> zeros, S1) on every backend
rm -rf data/runs/garbage
$L $P probe --work-dir data/runs/garbage --face-only --face-model gfpgan14 --threads 6 --face-runs 1 \
   --backends vk0-fp16,vk0-fp32,vk1-fp16,vk1-fp32,cpu-fp16 --record-wrong-output 2>&1 | grep '^\[probe\]'
# 1b) second start with the same state: wrong_output pairs are now in the local blocklist
$L $P probe --work-dir data/runs/garbage --out data/runs/garbage/report2.json --face-only --face-model gfpgan14 \
   --threads 6 --face-runs 1 --backends vk0-fp16,vk1-fp16,vk0-fp32 2>&1 | grep '^\[probe\]'
# 1c) the rewritten graph is a different model version -> not blocked by 1)
$L $P probe --work-dir data/runs/garbage --out data/runs/garbage/report3.json --face-only --threads 6 \
   --face-runs 1 --backends vk0-fp16,vk1-fp16 2>&1 | grep '^\[probe\]'
# 2) synthetic corruption of a correct GPU output
for m in zero noise nan block32 half swap_rb offset; do
  $L $P bench-one --backend vk0-fp16 --runs 1 --corrupt $m 2>/dev/null | python3 -c "
import json,sys; r=json.load(sys.stdin)
print(json.dumps({k:r.get(k) for k in ['corrupt','status','reason','psnr_db','bad_frac','max_abs_err_u8','nonfinite']}))"
done | tee data/runs/corruption.jsonl
# 3) crash inside the probe child (isolation): child dies, parent records a confirmed crash
rm -rf data/runs/crash
$L $P probe --work-dir data/runs/crash --backends vk1-fp16,cpu-fp16 --threads 6 --crash-backend vk1-fp16 \
   --crash segv 2>&1 | grep '^\[probe\]'
$L $P probe --work-dir data/runs/crash --out data/runs/crash/report2.json --backends vk1-fp16,cpu-fp16 \
   --threads 6 2>&1 | grep '^\[probe\]'
