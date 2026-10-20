#!/usr/bin/env bash
# S8: build the fdroid release APK twice in deliberately different environments and compare.
# Usage: tools/rebuilder/s8.sh [outdir]   (needs the refocal-rebuilder:s8 image, see Dockerfile)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(git -C "$HERE" rev-parse --show-toplevel)
OUT=${1:-$ROOT/spikes/s8-repro/out}
DOCKER=${DOCKER:-docker --context default}
IMG=${IMG:-refocal-rebuilder:s8}
mkdir -p "$OUT/in"
chmod 777 "$OUT"

# Source snapshot = tracked (incl. staged) files of the repo and its submodules, minus the
# Flutter SDK, which is cloned in the container from the local mirror at the pinned commit.
( cd "$ROOT" && git ls-files --recurse-submodules -z | grep -zv '^flutter/' \
    | tar --null -T - -cf "$OUT/in/source.tar" )
FLUTTER_SHA=$(git -C "$ROOT" ls-files -s flutter | awk '{print $2}')  # pinned gitlink (index)
FLUTTER_GIT=$(git -C "$ROOT/flutter" rev-parse --absolute-git-dir)

run() { # name, extra docker args..., -- env assignments
  local name=$1; shift
  echo "== build $name"
  local t0=$SECONDS attempt
  for attempt in 1 2 3; do  # retry only on network failures (Maven TLS resets seen in S8)
    if run_once "$name" "$@"; then echo "   $((SECONDS - t0)) s"; return 0; fi
    grep -q "while downloading artifacts from the network\|Could not resolve" "$OUT/build-$name.log" \
      || { tail -30 "$OUT/build-$name.log"; return 1; }
    echo "   network failure, retry $attempt"
  done
  tail -30 "$OUT/build-$name.log"; return 1
}

run_once() {
  local name=$1; shift
  $DOCKER run --rm -i "$@" \
    -v "$OUT/in/source.tar:/in/source.tar:ro" -v "$FLUTTER_GIT:/in/flutter.git:ro" \
    -v "$OUT:/out" -e OUT_NAME="$name" -e FLUTTER_SHA="$FLUTTER_SHA" \
    -e FLAVOR=fdroid "$IMG" bash -s < "$HERE/build-in-container.sh" \
    > "$OUT/build-$name.log" 2>&1
}

# A: "developer" build. B: "F-Droid server" build — different user, TZ, locale, umask,
# hostname, CPU count, and later wall-clock time.
[[ -f "$OUT/A.apk" && -z "${REBUILD:-}" ]] || \
run A --hostname dev-box --cpus "$(nproc)" -e SRC=/home/vagrant/build/io.github.refocal.app -e TZ=UTC \
      -e LANG=C.UTF-8 -e UMASK=022
[[ -f "$OUT/B.apk" && -z "${REBUILD:-}" ]] || \
run B --hostname fdroid-bs --cpus 4 --user 4242:4242 -w /tmp -e HOME=/tmp/fdroid-home \
      -e SRC=/home/vagrant/build/io.github.refocal.app -e TZ=Asia/Tokyo \
      -e LANG=ru_RU.UTF-8 -e UMASK=077

cd "$OUT"
sha256sum A.apk B.apk | tee sha256.txt
if cmp -s A.apk B.apk; then
  echo "RESULT: unsigned APKs are bit-identical"
else
  echo "RESULT: APKs differ -> diffoscope"
  $DOCKER run --rm -v "$OUT:/w" -w /w "$IMG" \
    diffoscope --text diffoscope.txt --max-report-size 5000000 A.apk B.apk >/dev/null || true
  head -c 4000 diffoscope.txt
fi

# What F-Droid actually checks: copy the signature of the developer's signed APK onto the
# unsigned server build B (apksigcopier) and verify it with apksigner. Two ways to sign:
#  1. apksigner on the unsigned APK — only with --alignment-preserved (S8 finding);
#  2. Gradle signingConfig (build C = A + key.properties), the release.yml path.
# shellcheck disable=SC2016  # the script runs, and expands, inside the container
$DOCKER run --rm -v "$OUT:/w" -w /w "$IMG" bash -euo pipefail -c '
  [[ -f test.jks ]] || keytool -genkeypair -keystore test.jks -storepass s8test -keypass s8test \
    -alias s8 -keyalg RSA -keysize 4096 -validity 10000 -dname CN=refocal-s8-test >/dev/null 2>&1
  for mode in default alignment-preserved; do
    extra=""; [[ $mode == alignment-preserved ]] && extra=--alignment-preserved
    apksigner sign --ks test.jks --ks-pass pass:s8test --key-pass pass:s8test $extra \
      --out A-signed-$mode.apk A.apk
  done'
cp "$OUT/test.jks" "$OUT/in/release.jks"
[[ -f "$OUT/C.apk" && -z "${REBUILD:-}" ]] || \
run C --hostname dev-box --cpus "$(nproc)" -e SRC=/home/vagrant/build/io.github.refocal.app -e TZ=UTC \
      -e LANG=C.UTF-8 -e UMASK=022 -e KS_PASS=s8test -e KS_ALIAS=s8
rm -f "$OUT/in/release.jks"
# shellcheck disable=SC2016  # the script runs, and expands, inside the container
$DOCKER run --rm -v "$OUT:/w" -w /w "$IMG" bash -uo pipefail -c '
  for signed in A-signed-default A-signed-alignment-preserved C; do
    rm -f copy.apk
    if apksigcopier copy $signed.apk B.apk copy.apk 2>/dev/null && apksigner verify copy.apk >/dev/null 2>&1; then
      echo "RESULT: signature of $signed.apk copied onto B: VERIFIES"
    else
      echo "RESULT: signature of $signed.apk copied onto B: FAILS"
    fi
  done
  apksigner verify --print-certs C.apk | head -1'
