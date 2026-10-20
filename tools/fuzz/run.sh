#!/usr/bin/env bash
# Builds the libFuzzer targets (native/tests/fuzz) with ASan+UBSan and runs each for SECONDS
# (11 §1: 5 min per PR, 1 h nightly). The corpus grows in CORPUS_DIR (kept in the CI cache),
# seeded from git. A finding fails the run and leaves crash-*/timeout-*/leak-* in ARTIFACTS.
# TARGETS (default: all) picks targets, SEED fixes libFuzzer's seed (shards of fuzz-ga.yml).
# FORK workers (default: the cores, at most 4) fuzz each target at once, sharing its corpus:
# SECONDS of wall time are FORK x SECONDS of fuzzing (a GitHub runner has 4 cores).
#   tools/fuzz/run.sh SECONDS_PER_TARGET [CORPUS_DIR] [ARTIFACTS]
set -euo pipefail
SECS=${1:?seconds per target}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CORPUS=${2:-$ROOT/native/build-fuzz/corpus}
ART=${3:-$ROOT/native/build-fuzz/findings}
TARGETS=${TARGETS:-metaio decode zip heif}
# At most 4 by default: each worker may take -rss_limit_mb below.
FORK=${FORK:-$(n=$(nproc); echo $((n < 4 ? n : 4)))}
read -ra cmake_extra <<< "${CMAKE_EXTRA:-}"  # more -D options
read -ra targets <<< "$TARGETS"
CC=${CC:-clang-18} CXX=${CXX:-clang++-18} cmake -S "$ROOT/native" -B "$ROOT/native/build-fuzz" \
  -DENH_SANITIZE=address -DENH_BUILD_FUZZ=ON -DENH_NCNN_RUNTIME_CPU=OFF \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo "${cmake_extra[@]}" >/dev/null
cmake --build "$ROOT/native/build-fuzz" -j"$(nproc)" --target "${targets[@]/#/fuzz_}"
mkdir -p "$ART"
status=0
for t in "${targets[@]}"; do
  mkdir -p "$CORPUS/$t"
  cp -n "$ROOT/native/tests/fuzz/corpus/$t/"* "$CORPUS/$t/" 2>/dev/null || true
  echo "== fuzz_$t for ${SECS}s, $FORK workers"
  # -timeout: one input taking longer is a hang; -rss_limit_mb: decoders may use up to the
  # SEC-INP-002 limits (the target skips inputs above 4 MP). Fork mode ignores timeouts and
  # OOMs unless told not to: here they are findings, as in a single process.
  if ! "$ROOT/native/build-fuzz/fuzz_$t" -fork="$FORK" -ignore_timeouts=0 -ignore_ooms=0 \
      -max_total_time="$SECS" -timeout=10 -max_len=65536 -rss_limit_mb=2560 -seed="${SEED:-0}" \
      -print_final_stats=1 -artifact_prefix="$ART/$t-" "$CORPUS/$t"; then
    status=1
  fi
done
exit $status
