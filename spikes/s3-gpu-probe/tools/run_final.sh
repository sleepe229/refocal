#!/usr/bin/env bash
# Final S3 runs (after run_detection.sh): garbage -> gpu_fp32 routing, app-like probe, budget guard.
set -u
cd "$(dirname "$0")/.."
P=build/refocal-probe
L="flock /tmp/claude-1000/refocal-bench.lock"
rm -rf data/runs/garbage2
$L $P probe --work-dir data/runs/garbage2 --face-only --face-model gfpgan14 --threads 6 --face-runs 1 \
   --backends vk0-fp16,vk1-fp16 --record-wrong-output 2>&1 | grep '^\[probe\]'
$L $P probe --work-dir data/runs/garbage2 --out data/runs/garbage2/report2.json --face-only --face-model gfpgan14 \
   --threads 6 --face-runs 1 --backends vk0-fp16,vk0-fp32,vk1-fp16,vk1-fp32 2>&1 | grep '^\[probe\]'
# app-like: built-in blocklist active (llvmpipe skipped), SR + face
rm -rf data/runs/app
$L $P probe --work-dir data/runs/app --threads 6 --face 2>&1 | grep '^\[probe\]'
# budget guard: warm-up slower than 1 s -> too_slow
rm -rf data/runs/budget
$L $P probe --work-dir data/runs/budget --threads 6 --ignore-blocklist --max-run-ms 1000 2>&1 | grep '^\[probe\]'
# repeatability of SR timings
rm -rf data/runs/sr2
$L $P probe --work-dir data/runs/sr2 --threads 6 --ignore-blocklist 2>&1 | grep '^\[probe\]'
