#!/usr/bin/env bash
# End-to-end check on a headless AOSP emulator (no phone needed):
# pick a photo in the system Photo Picker -> enhance -> save -> verify the gallery entry.
#   docker build -t refocal-emulator:35 tools/emulator
#   [SCENARIO=basic|background|pause|queue] tools/emulator/e2e.sh APK [PHOTO.jpg|png|webp] [SCALE_LABEL]
# background: Home during processing -> FGS notification, "Photo ready" -> reopen -> save.
# pause: Pause -> force-stop (process killed) -> reopen -> continue from the list -> save.
# Every scenario ends with the log check, share intake, "edit with" and a queue of two photos;
# queue: only share intake and the queue (no 4x run).
# HEIC=1: also "Save as file" in HEIC, checked by check_heic.py (HEIC_CHECK="--icc --exif").
# rfpack: RFPACK=<file.rfpack> PACK=<pack id>: import it on the Models screen through the system
# file picker (FR-MODEL-006, no network), check it is installed; nothing else.
# Without SCALE_LABEL the editor's Auto must show its explanation (FR-ENH-007) before Enhance,
# and a fragment preview runs (FR-ENH-015).
# The APK must contain x86_64 libs (e.g. flutter build apk --profile --target-platform android-x64).
set -euo pipefail
APK=$(realpath "${1:?apk}")
PHOTO=$(realpath "${2:-$(dirname "$0")/../../spikes/s2-streaming/data/stockholm_1mp.jpg}")
SCALE=${3:-}
SCENARIO=${SCENARIO:-basic}
EXT=${PHOTO##*.}
OUT=${OUT:-$(mktemp -d)}
mkdir -p "$OUT"
DOCKER=${DOCKER:-docker --context default}
# Where /dev/kvm is not local (Docker Desktop): KVM_GID=0 EMU_USER=root (the device is 0600 there).
KVM_GID=${KVM_GID:-$(stat -c %g /dev/kvm)}
NAME=refocal-e2e-$$

cleanup() { $DOCKER rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

$DOCKER run -d --name "$NAME" --device /dev/kvm --group-add "$KVM_GID" ${EMU_USER:+--user "$EMU_USER"} \
  -v "$APK:/in/app.apk:ro" -v "$PHOTO:/in/photo.$EXT:ro" \
  ${RFPACK:+-v "$(realpath "$RFPACK"):/in/pack.rfpack:ro"} refocal-emulator:35 bash -c '
    emulator -avd refocal35 -no-window -no-audio -no-boot-anim -no-snapshot -no-metrics \
      -gpu swiftshader_indirect -memory 4096 -cores 4 > /tmp/emu.log 2>&1 &
    adb wait-for-device
    until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d "\r")" = 1 ]; do sleep 3; done
    echo BOOTED; sleep infinity' >/dev/null

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
      if [[ ${NOTAP:-0} = 1 ]]; then echo "  '$want' shown at $xy"; else adb_ shell input tap $xy; echo "  tap '$want' at $xy"; fi
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

echo "== boot"
for _ in $(seq 120); do $DOCKER logs "$NAME" 2>&1 | grep -q BOOTED && break; sleep 5; done
adb_ shell getprop ro.build.version.release
echo "== install"
adb_ install -r /in/app.apk | tail -1
adb_ push "/in/photo.$EXT" "/sdcard/Pictures/e2e_input.$EXT" >/dev/null
if [[ -n "${RFPACK:-}" ]]; then adb_ push /in/pack.rfpack "/sdcard/Download/$(basename "$RFPACK")" >/dev/null; fi
adb_ shell pm grant io.github.refocal.app android.permission.POST_NOTIFICATIONS
adb_ shell content call --method scan_volume --uri content://media --arg external_primary >/dev/null
adb_ shell am start -n io.github.refocal.app/.MainActivity >/dev/null

echo "== flow"
tap_text "Skip" 60  # first run: the introduction (FR-ONB-001)
if [[ $SCENARIO = rfpack ]]; then
  echo "== offline pack (FR-MODEL-006)"
  tap_text "Settings" 30
  # "Models" is further down the settings list.
  for _ in $(seq 6); do
    tap_text "Models" 2 2>/dev/null && break
    adb_ shell input swipe 540 1800 540 600 300
  done
  tap_text "Import a .rfpack file" 30
  sleep 4
  # DocumentsUI: open Downloads from the roots drawer, then the file (its row has the name).
  name=$(basename "$RFPACK")
  for step in "Show roots" "Downloads" "$name"; do
    for _ in $(seq 15); do
      dump_ui
      xy=$(adb_ shell cat /sdcard/ui.xml 2>/dev/null | python3 -c '
import re, sys
want = sys.argv[1]
by_text, by_desc = None, None
for m in re.finditer(r"<node [^>]*>", sys.stdin.read()):
    n = m.group(0)
    attr = lambda k: (re.search(k + r"=\"([^\"]*)\"", n) or [None, ""])[1]
    b = list(map(int, re.findall(r"\d+", attr("bounds"))))
    xy = ((b[0] + b[2]) // 2, (b[1] + b[3]) // 2)
    # The file title, not its "Preview <name>" button (same name in content-desc).
    if want in attr("text") and by_text is None: by_text = xy
    if want in attr("content-desc") and by_desc is None: by_desc = xy
hit = by_text or by_desc
if hit: print(*hit)' "$step")
      if [[ -n "$xy" ]]; then adb_ shell input tap $xy; echo "  tap '$step' at $xy"; break; fi
      sleep 2
    done
    sleep 2
  done
  wait_text "Installed:" 60 || { echo "FAIL: pack not installed"; exit 1; }
  shot rfpack
  wait_text "${PACK:?PACK id}" 10 || { echo "FAIL: $PACK not listed"; exit 1; }
  echo "  $PACK imported and listed"
  echo PASS
  exit 0
fi
if [[ $SCENARIO != queue ]]; then
tap_text "Choose a photo" 60
sleep 3
# Photo Picker: first thumbnail in "Recent".
adb_ shell uiautomator dump /sdcard/ui.xml >/dev/null
xy=$(adb_ shell cat /sdcard/ui.xml | python3 -c '
import re, sys
for m in re.finditer(r"<node [^>]*>", sys.stdin.read()):
    n = m.group(0)
    if "Photo taken" in n or "Media" in n and "ImageView" in n:
        b = list(map(int, re.findall(r"\d+", re.search(r"bounds=\"([^\"]*)\"", n).group(1))))
        print((b[0] + b[2]) // 2, (b[1] + b[3]) // 2); break')
[[ -n "$xy" ]] || xy="177 1523"
adb_ shell input tap $xy
echo "  picked photo at $xy"
if [[ -n "$SCALE" ]]; then
  tap_text "$SCALE" 30
else
  wait_text "denoise" 60 || { echo "FAIL: no Auto explanation"; exit 1; }  # "4×, ..., denoise medium"
  shot auto
  tap_text "Adjust" 30
  shot adjust
  tap_text "Done" 10
  # FR-ENH-015: a part of the photo first, in a sheet, then back to the editor ("…" menu).
  tap_text "More" 30
  tap_text "Preview a part" 30
  wait_text "px in" 300 || { echo "FAIL: no fragment preview"; exit 1; }  # "Part 512 × 512 px in 1.2 s"
  shot fragment
  tap_text "Close" 10
fi
tap_text "Enhance" 30
t0=$SECONDS
notif() { adb_ shell dumpsys notification --noredact 2>/dev/null | grep -E "android\.(title|text)=" | grep -c "$1" || true; }
case "$SCENARIO" in
  background)
    sleep 4
    adb_ shell input keyevent KEYCODE_HOME
    for _ in $(seq 60); do [[ $(notif "Enhancing a photo") -gt 0 ]] && break; sleep 1; done
    [[ $(notif "Enhancing a photo") -gt 0 ]] || { echo "FAIL: no processing notification"; exit 1; }
    echo "  processing notification shown"
    for _ in $(seq 600); do [[ $(notif "Photo ready") -gt 0 ]] && break; sleep 1; done
    [[ $(notif "Photo ready") -gt 0 ]] || { echo "FAIL: no 'Photo ready' notification"; exit 1; }
    echo "  finished in the background"
    adb_ shell am start -n io.github.refocal.app/.MainActivity >/dev/null
    ;;
  pause)
    sleep 6
    tap_text "Pause" 60
    sleep 3  # pause lands at the next tile boundary
    adb_ shell am force-stop io.github.refocal.app
    echo "  paused and killed"
    adb_ shell am start -n io.github.refocal.app/.MainActivity >/dev/null
    tap_text "Paused enhancement" 60
    ;;
esac
shot editor_running
tap_text "Save" 600
echo "  enhance took ~$((SECONDS - t0)) s"
shot result
sleep 5
echo "== verify gallery"
adb_ shell content query --uri content://media/external/images/media \
  --projection _display_name:relative_path:width:height | grep Refocal_ || { echo FAIL; exit 1; }
if [[ ${HEIC:-0} = 1 ]]; then
  # FR-EXP-002: HeifWriter on the device, metadata from the core; the file is checked on the
  # host (tools/emulator/check_heic.py, HEIC_CHECK: --icc for a photo with a profile, --exif).
  echo "== HEIC (FR-EXP-002): Save as file -> HEIC"
  tap_text "More" 30
  tap_text "Save as file" 30
  tap_text "HEIC" 30
  sleep 4
  # DocumentsUI: save in Downloads (open it from the roots drawer if it starts elsewhere).
  if ! tap_text "SAVE" 5 2>/dev/null; then
    tap_text "Show roots" 10 && tap_text "Downloads" 10 && sleep 2
    tap_text "SAVE" 15 || { echo "FAIL: no save button"; exit 1; }
  fi
  sleep 8
  heic=$(adb_ shell find /sdcard -name 'Refocal_*.heic' 2>/dev/null | head -1 | tr -d '\r')
  [[ -n "$heic" ]] || { echo "FAIL: no HEIC saved"; debug_dump heic; exit 1; }
  adb_ pull "$heic" /tmp/result.heic >/dev/null
  $DOCKER cp "$NAME:/tmp/result.heic" "$OUT/result.heic"
  python3 "$(dirname "$0")/check_heic.py" "$OUT/result.heic" ${HEIC_CHECK:-} || { echo "FAIL: HEIC check"; exit 1; }
fi
echo "== bug-report log (FR-SET-007, PRIV-LOG-001)"
adb_ shell input keyevent KEYCODE_BACK
tap_text "About" 30
tap_text "Report a problem" 30
sleep 2
adb_ shell uiautomator dump /sdcard/ui.xml >/dev/null
log_ui=$(adb_ shell cat /sdcard/ui.xml)
grep -q "job done" <<<"$log_ui" || { echo "FAIL: the log has no finished job"; exit 1; }
if [[ -z "$SCALE" ]]; then
  grep -q "analyze:" <<<"$log_ui" || { echo "FAIL: Auto did not analyse the photo"; exit 1; }
fi
if grep -qE "/data/|/storage/|content://" <<<"$log_ui"; then echo "FAIL: a path or URI in the log"; exit 1; fi
echo "  log shows the job, no paths"
adb_ shell input keyevent KEYCODE_BACK
adb_ shell input keyevent KEYCODE_BACK
fi

echo "== share intake (FR-SHARE-001)"
id=$(adb_ shell content query --uri content://media/external/images/media --projection _id \
  --where "_display_name=\'e2e_input.$EXT\'" | sed -n 's/.*_id=\([0-9]*\).*/\1/p' | head -1)
[[ -n "$id" ]] || { echo "FAIL: input not in MediaStore"; exit 1; }
mime=image/${EXT/jpg/jpeg}
# A sending app's startActivity() moves EXTRA_STREAM into ClipData, which carries the read grant;
# `am start` does not, so the URI is also the data (granted; Flutter deep linking is off).
uri="content://media/external/images/media/$id"
adb_ shell am start -a android.intent.action.SEND -t "$mime" -d "$uri" --grant-read-uri-permission \
  --eu android.intent.extra.STREAM "$uri" -n io.github.refocal.app/.MainActivity >/dev/null
# The button, not the home screen's tagline that has the same word.
NOTAP=1 tap_text "Enhance" 60 || { echo "FAIL: shared photo did not open the editor"; exit 1; }
echo "  shared photo opened"
adb_ shell input keyevent KEYCODE_BACK  # leave the editor of the shared photo
echo "== edit with (FR-SHARE-002)"
adb_ shell am start -a android.intent.action.EDIT -t "$mime" -d "$uri" --grant-read-uri-permission \
  -n io.github.refocal.app/.MainActivity >/dev/null
NOTAP=1 tap_text "Enhance" 60 || { echo "FAIL: ACTION_EDIT did not open the editor"; exit 1; }
echo "  edited photo opened"
adb_ shell input keyevent KEYCODE_BACK

echo "== queue (FR-BATCH-001..008): multi-pick -> batch sheet -> autosave"
wait_text "Process several photos" 30
# Two fresh copies: the picker lists the newest first, and the gallery already holds the 4x
# result of the flow above (20 MP, ~17 min at Fast 2x on the emulator's CPU).
sleep 1
adb_ shell cp "/sdcard/Pictures/e2e_input.$EXT" "/sdcard/Pictures/e2e_q1.$EXT"
sleep 1
adb_ shell cp "/sdcard/Pictures/e2e_input.$EXT" "/sdcard/Pictures/e2e_q2.$EXT"
adb_ shell content call --method scan_volume --uri content://media --arg external_primary >/dev/null
before=$(adb_ shell content query --uri content://media/external/images/media \
  --projection _display_name | grep -c Refocal_ || true)
tap_text "Process several photos" 60
sleep 3
adb_ shell uiautomator dump /sdcard/ui.xml >/dev/null
adb_ shell cat /sdcard/ui.xml | python3 -c '
import re, sys
n = 0
for m in re.finditer(r"<node [^>]*>", sys.stdin.read()):
    node = m.group(0)
    if "Photo taken" in node:
        b = list(map(int, re.findall(r"\d+", re.search(r"bounds=\"([^\"]*)\"", node).group(1))))
        print((b[0] + b[2]) // 2, (b[1] + b[3]) // 2); n += 1
        if n == 2: break' | while read -r x y; do adb_ shell input tap "$x" "$y"; echo "  selected $x $y"; done
tap_text "Add" 30           # the picker's "Add (2)"
tap_text "Add to the queue" 30  # batch sheet: Fast 2x, autosave on (defaults)
t0=$SECONDS
wait_text "Done 2, failed 0" 300 || { shot queue; echo "FAIL: queue report"; exit 1; }
shot queue
echo "  queue of 2 done in ~$((SECONDS - t0)) s"
after=$(adb_ shell content query --uri content://media/external/images/media \
  --projection _display_name | grep -c Refocal_ || true)
[[ $((after - before)) -eq 2 ]] || { echo "FAIL: $((after - before)) results saved, want 2"; exit 1; }
echo "  both results in the gallery:"
adb_ shell content query --uri content://media/external/images/media \
  --projection _display_name:width:height | grep Refocal_ | tail -2
adb_ logcat -d | grep -E " enh |FATAL|AndroidRuntime" | tail -5 || true
echo PASS
