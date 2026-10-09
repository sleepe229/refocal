#!/usr/bin/env bash
# Checkpoint/resume test: uninterrupted reference run vs. run killed with SIGKILL mid-way
# and continued with --resume. Outputs (JPEG, PNG) must be byte-identical.
# usage: ./resume_test.sh NAME [s2_stream args...]
set -uo pipefail
export LC_ALL=C
cd "$(dirname "$0")"
NAME=$1; shift
IN=${IN:-data/avignon_12mp.jpg}
D=out/resume/$NAME; rm -rf "$D"; mkdir -p "$D"
inner() {
  local args=("$@")
  # 1) reference
  build/s2_stream --input "$IN" --job "$D/job_ref" "${args[@]}" \
    --out-jpeg "$D/ref.jpg" --out-png "$D/ref.png" --png-level 1 --stats "$D/ref.json" 2> "$D/ref.log"
  local nb; nb=$(python3 -c "import json;print(json.load(open('$D/ref.json'))['geometry']['bands'])")
  local target=$(( nb / 2 ))
  rm -rf "$D/job_ref"
  # 2) run and SIGKILL after checkpoint reaches band `target` (+ a random part of a band)
  build/s2_stream --input "$IN" --job "$D/job" "${args[@]}" \
    --out-jpeg "$D/res.jpg" --out-png "$D/res.png" --png-level 1 2> "$D/killed.log" &
  local pid=$!
  while kill -0 $pid 2>/dev/null; do
    if [[ -f "$D/job/checkpoint.json" ]]; then
      local bi; bi=$(grep -o '"band_idx": [0-9-]*' "$D/job/checkpoint.json" | grep -o '[0-9-]*$')
      if [[ -n "$bi" && $bi -ge $target ]]; then break; fi
    fi
    sleep 0.02
  done
  sleep "$(LC_ALL=C awk -v m="${KILL_DELAY_MAX:-2}" 'BEGIN{srand(); printf "%.2f", (0.1+0.8*rand())*m}')"
  kill -9 $pid; wait $pid 2>/dev/null
  local t_kill; t_kill=$(date +%s.%N)
  local ck; ck=$(grep -o '"band_idx": [0-9-]*' "$D/job/checkpoint.json" | grep -o '[0-9-]*$')
  echo "killed: checkpoint band_idx=$ck of $nb bands" | tee "$D/kill.txt"
  echo "last log lines before kill:" >> "$D/kill.txt"; tail -4 "$D/killed.log" >> "$D/kill.txt"
  ls "$D/job/bands" >> "$D/kill.txt"
  # 3) resume
  build/s2_stream --input "$IN" --job "$D/job" "${args[@]}" --resume \
    --out-jpeg "$D/res.jpg" --out-png "$D/res.png" --png-level 1 --stats "$D/res.json" 2> "$D/resume.log"
  rm -rf "$D/job"
  for f in jpg png; do
    if cmp -s "$D/ref.$f" "$D/res.$f"; then echo "$f: IDENTICAL"; else echo "$f: DIFFERENT"; fi
  done | tee -a "$D/kill.txt"
  sha256sum "$D"/ref.* "$D"/res.* >> "$D/kill.txt"
  rm -f "$D"/*.png
}
export -f inner; export D IN
flock /tmp/claude-1000/refocal-bench.lock bash -c 'inner "$@"' _ "$@"
cat "$D/kill.txt"
