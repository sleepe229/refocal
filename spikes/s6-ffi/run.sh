#!/usr/bin/env bash
# S6: build mock core (+ sanitizer variants), run native stress, then every Dart scenario in both
# event-delivery modes, each in its own AOT process. Results: out/results.jsonl, crashes noted.
set -uo pipefail
cd "$(dirname "$0")" || exit 1
DART=${DART:-$HOME/sdk/dart-sdk/bin/dart}
OUT=out; mkdir -p "$OUT"; : > "$OUT/results.jsonl"

for v in rel: tsan:thread asan:address; do
  d=${v%%:*}; s=${v#*:}
  CC=clang-18 CXX=clang++-18 cmake -S native -B "native/build-$d" -DSANITIZE="$s" >/dev/null
  cmake --build "native/build-$d" -j"$(nproc)" >/dev/null || exit 1
  echo "native stress [$d]: $("native/build-$d/stress" "${STRESS_ROUNDS:-1000}" 2>&1 | tail -1)"
done

(cd dart && "$DART" pub get >/dev/null && "$DART" compile exe bin/s6.dart -o ../$OUT/s6 >/dev/null) || exit 1
export S6_LIB=$PWD/native/build-rel/libenh_mock.so

for mode in callable port; do
  for sc in ${SCENARIOS:-concurrent needs_user throughput soak cancel destroy_blocking early_close isolate_kill bad_utf8}; do
    S6_MODE=$mode timeout 600 "$OUT/s6" "$sc" > "$OUT/tmp.out" 2> "$OUT/$mode-$sc.err"
    rc=$?
    cat "$OUT/tmp.out" >> "$OUT/results.jsonl"
    if [ $rc -ne 0 ]; then
      msg=$(grep -m1 -E "error:|Unhandled|Exception" "$OUT/$mode-$sc.err" | tr '"' "'")
      echo "{\"scenario\":\"$sc\",\"mode\":\"$mode\",\"crash\":true,\"rc\":$rc,\"error\":\"$msg\"}" >> "$OUT/results.jsonl"
    fi
    echo "$mode/$sc rc=$rc"
  done
done
rm -f "$OUT/tmp.out"
