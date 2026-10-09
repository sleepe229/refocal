#!/usr/bin/env bash
# End-to-end crash sentinel test (ADR-0016, TEST-FAULT-005 prototype).
# The process really dies (abort()/SIGSEGV) in the middle of a Vulkan stage; subsequent starts
# must route the (driver, model) pair to CPU according to the policy.
# Usage: tests/sentinel_crash_test.sh path/to/refocal-probe [gpu_index]
set -u
ulimit -c 0  # no core dumps from the simulated crashes
PROBE=${1:?path to refocal-probe}
GPU=${2:-${REFOCAL_TEST_GPU:-1}}
MODEL=sr.general-x4v3
fail=0

field() { python3 -c "import json,sys; d=json.loads(sys.stdin.readline()); print(eval(sys.argv[1]))" "$1"; }
stage() {  # prints the decision JSON line, returns the process exit code
    "$PROBE" stage --state-dir "$STATE" --gpu "$GPU" --model-id "$MODEL" "$@" 2>/dev/null | head -1
    return "${PIPESTATUS[0]}"
}
expect() {  # expect <label> <actual> <wanted>
    if [[ "$2" == "$3" ]]; then echo "  ok   $1: $2"; else echo "  FAIL $1: got '$2', want '$3'"; fail=1; fi
}

echo "== policy: quarantine after 1st hit (S3 proposal), permanent after 2 consecutive hits"
STATE=$(mktemp -d)
out=$(stage --crash abort); rc=$?
expect "run1 backend" "$(echo "$out" | field 'd["backend"]')" "vk$GPU-fp16"
expect "run1 died (SIGABRT=134)" "$rc" "134"
expect "sentinel left on disk" "$(test -f "$STATE/sentinel.json" && echo yes)" "yes"
out=$(stage)
expect "run2 hits" "$(echo "$out" | field 'd["startup"]["hits"]')" "1"
expect "run2 backend (quarantine)" "$(echo "$out" | field 'd["backend"]')" "cpu-fp16"
out=$(stage --crash abort); rc=$?
expect "run3 backend (GPU retried)" "$(echo "$out" | field 'd["backend"]')" "vk$GPU-fp16"
expect "run3 died" "$rc" "134"
out=$(stage)
expect "run4 hits" "$(echo "$out" | field 'd["startup"]["hits"]')" "2"
expect "run4 blocked_now" "$(echo "$out" | field 'd["startup"]["blocked_now"]')" "True"
expect "run4 backend" "$(echo "$out" | field 'd["backend"]')" "cpu-fp16"
out=$(stage --no-run)
expect "run5 backend (permanent)" "$(echo "$out" | field 'd["backend"]')" "cpu-fp16"
expect "run5 rule source" "$(echo "$out" | field 'd["blocklist"]["rules"][0]["source"]')" "local"
out=$("$PROBE" stage --state-dir "$STATE" --gpu "$GPU" --model-id face.gfpgan-1.4 --no-run 2>/dev/null | head -1)
expect "other model unaffected" "$(echo "$out" | field 'd["backend"]')" "vk$GPU-fp16"
rm -rf "$STATE"

echo "== policy: strict ADR-0016 (--no-quarantine): CPU from the 3rd start"
STATE=$(mktemp -d)
stage --no-quarantine --crash segv >/dev/null; rc=$?
expect "run1 died (SIGSEGV=139)" "$rc" "139"
out=$(stage --no-quarantine --crash segv); rc=$?
expect "run2 backend (still GPU)" "$(echo "$out" | field 'd["backend"]')" "vk$GPU-fp16"
expect "run2 died" "$rc" "139"
out=$(stage --no-quarantine --no-run)
expect "run3 backend" "$(echo "$out" | field 'd["backend"]')" "cpu-fp16"
rm -rf "$STATE"

echo "== exit reason known (Android ApplicationExitInfo)"
STATE=$(mktemp -d)
stage --crash abort >/dev/null
out=$(stage --exit-reason os_kill --no-run)
expect "os_kill: not counted" "$(echo "$out" | field 'd["startup"]["hits"]')" "0"
expect "os_kill: GPU kept" "$(echo "$out" | field 'd["backend"]')" "vk$GPU-fp16"
rm -f "$STATE/sentinel.json"
stage --crash abort >/dev/null
out=$(stage --exit-reason native_crash --no-run)
expect "native_crash: blocked at once" "$(echo "$out" | field 'd["backend"]')" "cpu-fp16"
rm -rf "$STATE"

if [[ $fail == 0 ]]; then echo "sentinel e2e: PASS"; else echo "sentinel e2e: FAIL"; fi
exit $fail
