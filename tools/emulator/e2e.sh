#!/usr/bin/env bash
# End-to-end check on a headless AOSP emulator (no phone needed):
# pick a photo in the system Photo Picker -> enhance -> save -> verify the gallery entry.
#   docker build -t refocal-emulator:35 tools/emulator
#   [SCENARIO=basic|background|pause] tools/emulator/e2e.sh APK [PHOTO.jpg|png|webp] [SCALE_LABEL]
# background: Home during processing -> FGS notification, "Photo ready" -> reopen -> save.
# pause: Pause -> force-stop (process killed) -> reopen -> continue from the list -> save.
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
KVM_GID=$(stat -c %g /dev/kvm)
NAME=refocal-e2e-$$

cleanup() { $DOCKER rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

$DOCKER run -d --name "$NAME" --device /dev/kvm --group-add "$KVM_GID" \
  -v "$APK:/in/app.apk:ro" -v "$PHOTO:/in/photo.$EXT:ro" refocal-emulator:35 bash -c '
    emulator -avd refocal35 -no-window -no-audio -no-boot-anim -no-snapshot -no-metrics \
      -gpu swiftshader_indirect -memory 4096 -cores 4 > /tmp/emu.log 2>&1 &
    adb wait-for-device
    until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d "\r")" = 1 ]; do sleep 3; done
    echo BOOTED; sleep infinity' >/dev/null

adb_() { $DOCKER exec "$NAME" adb "$@"; }
shot() { $DOCKER exec "$NAME" adb exec-out screencap -p > "$OUT/$1.png"; echo "  screenshot $OUT/$1.png"; }

# Taps the centre of the first UI node whose text or content-desc contains $1.
tap_text() {
  local want=$1 tries=${2:-30}
  for _ in $(seq "$tries"); do
    adb_ shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || true
    local xy
    xy=$(adb_ shell cat /sdcard/ui.xml 2>/dev/null | python3 -c '
import re, sys
want = sys.argv[1]
hit = None
for m in re.finditer(r"<node [^>]*>", sys.stdin.read()):
    n = m.group(0)
    t = re.search(r"text=\"([^\"]*)\"", n).group(1) + " " + re.search(r"content-desc=\"([^\"]*)\"", n).group(1)
    if want in t and "clickable=\"true\"" in n:  # buttons, not titles with the same text
        b = list(map(int, re.findall(r"\d+", re.search(r"bounds=\"([^\"]*)\"", n).group(1))))
        hit = ((b[0] + b[2]) // 2, (b[1] + b[3]) // 2)
if hit: print(*hit)' "$want")
    if [[ -n "$xy" ]]; then adb_ shell input tap $xy; echo "  tap '$want' at $xy"; return 0; fi
    sleep 2
  done
  echo "  '$want' not found"; return 1
}

echo "== boot"
for _ in $(seq 120); do $DOCKER logs "$NAME" 2>&1 | grep -q BOOTED && break; sleep 5; done
adb_ shell getprop ro.build.version.release
echo "== install"
adb_ install -r /in/app.apk | tail -1
adb_ push "/in/photo.$EXT" "/sdcard/Pictures/e2e_input.$EXT" >/dev/null
adb_ shell pm grant io.github.refocal.app android.permission.POST_NOTIFICATIONS
adb_ shell content call --method scan_volume --uri content://media --arg external_primary >/dev/null
adb_ shell am start -n io.github.refocal.app/.MainActivity >/dev/null

echo "== flow"
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
if [[ -n "$SCALE" ]]; then tap_text "$SCALE" 30; fi
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
tap_text "Save to gallery" 600
echo "  enhance took ~$((SECONDS - t0)) s"
shot result
sleep 5
echo "== verify gallery"
adb_ shell content query --uri content://media/external/images/media \
  --projection _display_name:relative_path:width:height | grep Refocal_ || { echo FAIL; exit 1; }
adb_ logcat -d | grep -E " enh |FATAL|AndroidRuntime" | tail -5 || true
echo PASS
