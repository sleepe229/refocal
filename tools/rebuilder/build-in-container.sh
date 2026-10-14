#!/usr/bin/env bash
# Runs inside refocal-rebuilder: unpack the source snapshot at $SRC, attach the Flutter SDK
# from a local git mirror (Flutter needs its git history for versioning), build the release
# APK of the given flavor and copy it to /out.
set -euo pipefail
umask "${UMASK:-022}"
: "${SRC:?}" "${FLAVOR:=fdroid}" "${FLUTTER_SHA:?}"
mkdir -p "$SRC" "$HOME"
tar -xf /in/source.tar -C "$SRC"
git config --global --add safe.directory '*'
git config --global advice.detachedHead false
git config --global init.defaultBranch main
git clone -q /in/flutter.git "$SRC/flutter"
git -C "$SRC/flutter" checkout -q "$FLUTTER_SHA"
export PATH="$SRC/flutter/bin:$PATH"
flutter --suppress-analytics config --no-analytics >/dev/null
flutter --suppress-analytics --version
if [[ -f /out/in/release.jks ]]; then  # optional: Gradle-signed build (release.yml path)
  cp /out/in/release.jks "$SRC/app/android/release.jks"
  printf 'storeFile=release.jks\nstorePassword=%s\nkeyAlias=%s\nkeyPassword=%s\n' \
    "$KS_PASS" "$KS_ALIAS" "$KS_PASS" > "$SRC/app/android/key.properties"
fi
cd "$SRC/app"
flutter --suppress-analytics build apk --release --flavor "$FLAVOR" --target-platform android-arm64 \
  --split-debug-info=build/symbols
install -m 644 "build/app/outputs/flutter-apk/app-$FLAVOR-release.apk" "/out/$OUT_NAME.apk"
