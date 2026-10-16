#!/usr/bin/env bash
# Builds the libFuzzer targets (native/tests/fuzz) with ASan+UBSan and runs each for SECONDS
# (11 §1: 5 min per PR, 1 h nightly). The corpus grows in CORPUS_DIR (kept in the CI cache),
# seeded from git. A finding fails the run and leaves crash-*/timeout-*/leak-* in ARTIFACTS.
#   tools/fuzz/run.sh SECONDS_PER_TARGET [CORPUS_DIR] [ARTIFACTS]
set -euo pipefail
SECS=${1:?seconds per target}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CORPUS=${2:-$ROOT/native/build-fuzz/corpus}
ART=${3:-$ROOT/native/build-fuzz/findings}
CC=${CC:-clang-18} CXX=${CXX:-clang++-18} cmake -S "$ROOT/native" -B "$ROOT/native/build-fuzz" \
  -DENH_SANITIZE=address -DENH_BUILD_FUZZ=ON -DENH_NCNN_RUNTIME_CPU=OFF \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo ${CMAKE_EXTRA:-} >/dev/null
cmake --build "$ROOT/native/build-fuzz" -j"$(nproc)" --target fuzz_metaio fuzz_decode fuzz_zip
mkdir -p "$ART"
status=0
for t in metaio decode zip; do
  mkdir -p "$CORPUS/$t"
  cp -n "$ROOT/native/tests/fuzz/corpus/$t/"* "$CORPUS/$t/" 2>/dev/null || true
  echo "== fuzz_$t for ${SECS}s"
  # -timeout: one input taking longer is a hang; -rss_limit_mb: decoders may use up to the
  # SEC-INP-002 limits (the target skips inputs above 4 MP).
  if ! "$ROOT/native/build-fuzz/fuzz_$t" -max_total_time="$SECS" -timeout=10 -max_len=65536 \
      -rss_limit_mb=2560 -print_final_stats=1 -artifact_prefix="$ART/$t-" "$CORPUS/$t"; then
    status=1
  fi
done
exit $status
