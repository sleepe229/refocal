#!/usr/bin/env bash
# App self-update end to end on the headless emulator (ADR-0027, FR-UPD-001…004):
# v1 (installed by adb) -> "Check for updates" -> "Update" -> "Install unknown apps" -> (Android's
# own dialog, if it asks) -> v2; then v2 -> v3 with no dialog at all (the app is the installer
# of record now).
# The feed and the APKs are served over HTTPS from the emulator container (10.0.2.2 from the
# emulator), signed with a throwaway minisign key.
#
#   tools/emulator/update_e2e.sh DIR
# DIR holds v1.apk v2.apk v3.apk, increasing versionCodes, one signing key, and the minisign
# secret key test.key whose public key the APKs were built with:
#   minisign -G -W -p DIR/test.pub -s DIR/test.key
#   flutter build apk --profile --flavor github --target-platform android-x64 --build-number N \
#     --dart-define=REFOCAL_UPDATE_TEST_BASE=https://10.0.2.2:8443 \
#     --dart-define=REFOCAL_UPDATE_TEST_KEY="$(sed -n 2p DIR/test.pub)"
# then sign the three with one key (apksigner). MINISIGN: the minisign binary (default: minisign).
set -euo pipefail
DIR=$(realpath "${1:?dir with v1.apk v2.apk v3.apk test.key}")
OUT=${OUT:-$(mktemp -d)}
mkdir -p "$OUT"
DOCKER=${DOCKER:-docker --context default}
MINISIGN=${MINISIGN:-minisign}
KVM_GID=${KVM_GID:-$(stat -c %g /dev/kvm)}
NAME=refocal-update-e2e-$$
PKG=io.github.refocal.app
ROOT=$(cd "$(dirname "$0")/../.." && pwd)

cleanup() { $DOCKER rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# shellcheck disable=SC2016  # the script runs, and expands, inside the container
$DOCKER run -d --name "$NAME" --device /dev/kvm --group-add "$KVM_GID" ${EMU_USER:+--user "$EMU_USER"} \
  -v "$DIR:/in:ro" refocal-emulator:35 bash -c '
    mkdir -p /tmp/srv && cd /tmp/srv
    openssl req -x509 -newkey rsa:2048 -nodes -keyout /tmp/key.pem -out /tmp/cert.pem -days 1 \
      -subj /CN=10.0.2.2 >/dev/null 2>&1
    python3 -c "
import http.server, ssl
s = http.server.ThreadingHTTPServer((\"127.0.0.1\", 8443), http.server.SimpleHTTPRequestHandler)
c = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); c.load_cert_chain(\"/tmp/cert.pem\", \"/tmp/key.pem\")
s.socket = c.wrap_socket(s.socket, server_side=True); s.serve_forever()" > /tmp/srv.log 2>&1 &
    emulator -avd refocal35 -no-window -no-audio -no-boot-anim -no-snapshot -no-metrics \
      -gpu swiftshader_indirect -memory 4096 -cores 4 > /tmp/emu.log 2>&1 &
    adb wait-for-device
    until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d "\r")" = 1 ]; do sleep 3; done
    echo BOOTED; sleep infinity' >/dev/null

# shellcheck source=tools/emulator/ui.sh
source "$(dirname "$0")/ui.sh"

# Taps the centre of the first node whose text contains $1, clickable or not (Settings' Compose
# rows put the click on a parent without text).
tap_label() {
  for _ in $(seq "${2:-30}"); do
    dump_ui
    local xy
    xy=$(adb_ shell cat /sdcard/ui.xml 2>/dev/null | python3 -c '
import re, sys
for m in re.finditer(r"<node [^>]*>", sys.stdin.read()):
    n = m.group(0)
    if sys.argv[1] in (re.search(r"text=\"([^\"]*)\"", n) or [None, ""])[1]:
        b = list(map(int, re.findall(r"\d+", re.search(r"bounds=\"([^\"]*)\"", n).group(1))))
        print((b[0] + b[2]) // 2, (b[1] + b[3]) // 2)
        break' "$1")
    if [[ -n "$xy" ]]; then adb_ shell input tap "${xy% *}" "${xy#* }"; echo "  tap label '$1' at $xy"; return 0; fi
    sleep 2
  done
  echo "  label '$1' not found"; debug_dump "nolabel-${1// /_}"; return 1
}

version_code() { adb_ shell dumpsys package "$PKG" | sed -n 's/.*versionCode=\([0-9]*\).*/\1/p' | head -1; }
installer() { adb_ shell dumpsys package "$PKG" | sed -n 's/.*installerPackageName=\([^ ]*\).*/\1/p' | head -1; }
code_of() { $DOCKER exec "$NAME" bash -c "/opt/android-sdk/build-tools/36.0.0/aapt2 dump badging /in/$1" | sed -n "s/.*versionCode='\([0-9]*\)'.*/\1/p"; }

# Serves v$1.apk with a feed whose stable release is it.
publish() {
  local v=$1 code tmp
  code=$(code_of "v$v.apk")
  tmp=$(mktemp -d)
  echo "Release $v" > "$tmp/en.txt"
  python3 "$ROOT/tools/release/make_app_update.py" --previous - --tag "v9.0.$v" --apk "$DIR/v$v.apk" \
    --url "https://10.0.2.2:8443/v$v.apk" --version-code "$code" --min-sdk 29 \
    --notes-en "$tmp/en.txt" --notes-ru "$tmp/none.txt" "$tmp/app-update.json" >/dev/null
  "$MINISIGN" -S -s "$DIR/test.key" -m "$tmp/app-update.json" >/dev/null
  $DOCKER exec "$NAME" cp "/in/v$v.apk" "/tmp/srv/v$v.apk"
  $DOCKER cp "$tmp/app-update.json" "$NAME:/tmp/srv/app-update.json"
  $DOCKER cp "$tmp/app-update.json.minisig" "$NAME:/tmp/srv/app-update.json.minisig"
  rm -r "$tmp"
  echo "  feed: v$v (versionCode $code)"
}

# About -> "Check for updates" -> back on the home screen -> "Update".
check_and_update() {
  adb_ shell am start -n "$PKG/.MainActivity" >/dev/null
  tap_text "Settings" 30
  for _ in $(seq 6); do
    tap_text "About" 2 2>/dev/null && break
    adb_ shell input swipe 540 1800 540 600 300
  done
  tap_text "Check for updates" 30
  wait_text "is out" 30 || wait_text "is ready" 30
  adb_ shell input keyevent KEYCODE_BACK
  adb_ shell input keyevent KEYCODE_BACK
  tap_text "Update" 60  # shown once the APK is downloaded and verified
}

wait_version() {
  for _ in $(seq "${2:-60}"); do
    [[ "$(version_code)" = "$1" ]] && return 0
    sleep 2
  done
  echo "  versionCode $(version_code), expected $1"; debug_dump "version-$1"; return 1
}

echo "== boot"
for _ in $(seq 120); do $DOCKER logs "$NAME" 2>&1 | grep -q BOOTED && break; sleep 5; done
adb_ shell getprop ro.build.version.release
adb_ install /in/v1.apk | tail -1
adb_ shell pm grant "$PKG" android.permission.POST_NOTIFICATIONS
adb_ shell am start -n "$PKG/.MainActivity" >/dev/null
tap_text "Skip" 60
v2=$(code_of v2.apk) v3=$(code_of v3.apk)

echo "== v1 -> v2: the first update asks (installed by adb, no install permission yet)"
publish 2
check_and_update
# Settings -> "Install unknown apps" for Refocal: allow, back, tap "Update" again.
tap_label "Allow from this source" 30
adb_ shell input keyevent KEYCODE_BACK
tap_text "Update" 30
# Android may show its own "Do you want to update this app?" (AOSP 15 did not: allowing the
# install was enough). Tap it if it comes, else the update is already under way.
for _ in $(seq 10); do
  [[ "$(version_code)" = "$v2" ]] && break
  if dump_ui && adb_ shell cat /sdcard/ui.xml 2>/dev/null | grep -q "packageinstaller"; then
    tap_text "Update" 5 && break
  fi
  sleep 2
done
wait_version "$v2"
echo "  installer: $(installer)"
[[ "$(installer)" = "$PKG" ]] || { echo "FAIL: installer of record is not the app"; exit 1; }

echo "== v2 -> v3: no dialog"
adb_ shell am start -n "$PKG/.MainActivity" >/dev/null
tap_text "Close" 30  # "What's new in 9.0.2", once
publish 3
check_and_update
wait_version "$v3" 60
dump_ui
if adb_ shell cat /sdcard/ui.xml 2>/dev/null | grep -q "com.android.packageinstaller\|com.google.android.packageinstaller"; then
  echo "FAIL: the installer dialog showed"; exit 1
fi
adb_ shell am start -n "$PKG/.MainActivity" >/dev/null
NOTAP=1 tap_text "Close" 30  # "What's new in 9.0.3"; no introduction: the data survived
shot done
echo "PASS: v1 -> v2 (after allowing installs) -> v3 (no question)"
