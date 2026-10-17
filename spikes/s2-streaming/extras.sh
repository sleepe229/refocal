#!/usr/bin/env bash
# Follow-up experiments after matrix.sh.
set -uo pipefail
cd "$(dirname "$0")"
LOCK="flock /tmp/refocal-bench.lock"
OUT=out/matrix
# cold-read export: band files evicted from the page cache after commit
rm -rf out/job_m
$LOCK build/s2_stream --input data/avignon_12mp.jpg --job out/job_m --backend vk0 --tile 256 \
  --drop-cache --out-jpeg $OUT/x4_vk0_t256_raw_dropcache.jpg --out-png $OUT/dc.png --png-level 1 \
  --stats $OUT/x4_vk0_t256_raw_dropcache.json 2> $OUT/x4_vk0_t256_raw_dropcache.log
rm -f $OUT/*.png $OUT/x4_vk0_t256_raw_dropcache.jpg; rm -rf out/job_m
echo EXTRA1 done
# seams on the Intel iGPU in fp16 (reduced set)
./seams_vk.sh
echo EXTRA2 done
./resume_test.sh cpu_t128_raw --tile 128 --backend cpu
./resume_test.sh vk1_t256_lz4 --tile 256 --backend vk1 --lz4
./resume_test.sh vk0_t256_feather8 --tile 256 --backend vk0 --feather 8 
KILL_DELAY_MAX=5 ./resume_test.sh cpu_t128_syncio --tile 128 --backend cpu --sync-io
echo EXTRA3 done
$LOCK ../s1-gfpgan/.venv/bin/python -I jpeg_simd_ref.py data/avignon_12mp.jpg > out/jpeg_simd_ref.txt 2>&1
echo ALL EXTRAS DONE
