# shellcheck shell=bash
# UI helpers of the emulator scripts (e2e.sh, update_e2e.sh), sourced after DOCKER, NAME and
# OUT are set: adb in the emulator container, screenshots, uiautomator taps and waits.

adb_() { $DOCKER exec "$NAME" adb "$@"; }
shot() { $DOCKER exec "$NAME" adb exec-out screencap -p > "$OUT/$1.png"; echo "  screenshot $OUT/$1.png"; }

# The current UI tree in /sdcard/ui.xml; empty when the dump fails (e.g. "could not get idle
# state" during an animation), never the tree of an earlier screen.
dump_ui() {
  adb_ shell rm -f /sdcard/ui.xml
  adb_ shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || true
}

# Centre of a clickable UI node whose text or content-desc contains $1: printed, and tapped
# unless NOTAP=1. Waits up to $2 dumps.
tap_text() {
  local want=$1 tries=${2:-30}
  for _ in $(seq "$tries"); do
    dump_ui
    local xy
    xy=$(adb_ shell cat /sdcard/ui.xml 2>/dev/null | python3 -c '
import re, sys
want = sys.argv[1]
hit = None
for m in re.finditer(r"<node [^>]*>", sys.stdin.read()):
    n = m.group(0)
    attr = lambda k: (re.search(k + r"=\"([^\"]*)\"", n) or [None, ""])[1]
    t = attr("text") + " " + attr("content-desc")
    if want in t and "clickable=\"true\"" in n:  # buttons, not titles with the same text
        b = list(map(int, re.findall(r"\d+", re.search(r"bounds=\"([^\"]*)\"", n).group(1))))
        hit = ((b[0] + b[2]) // 2, (b[1] + b[3]) // 2)
if hit: print(*hit)' "$want")
    if [[ -n "$xy" ]]; then
      if [[ ${NOTAP:-0} = 1 ]]; then echo "  '$want' shown at $xy"; else adb_ shell input tap "${xy% *}" "${xy#* }"; echo "  tap '$want' at $xy"; fi
      return 0
    fi
    sleep 2
  done
  echo "  '$want' not found"; debug_dump "notfound-${want// /_}"; return 1
}

# Waits until some UI node's text or content-desc contains $1 (no tap).
wait_text() {
  local want=$1 tries=${2:-30}
  for _ in $(seq "$tries"); do
    dump_ui
    if adb_ shell cat /sdcard/ui.xml 2>/dev/null | grep -qF "$want"; then return 0; fi
    sleep 2
  done
  echo "  '$want' not shown"; debug_dump "missing-${want// /_}"; return 1
}

# Screenshot, UI tree, activity stack and logcat into $OUT for a failed step.
debug_dump() {
  shot "$1"
  adb_ shell cat /sdcard/ui.xml > "$OUT/$1.xml" 2>/dev/null || true
  adb_ shell dumpsys activity activities | grep -E "Hist #|ResumedActivity" > "$OUT/$1.activities.txt" || true
  adb_ logcat -d > "$OUT/$1.logcat.txt" || true
}
