#!/usr/bin/env bash
# Cross-compile refocal-probe for Android arm64-v8a (API 29) with the NDK and a prebuilt
# ncnn Android Vulkan package. Not executed in S3 (no NDK on the spike machine).
#   ANDROID_NDK=~/Android/Sdk/ndk/27.2.12479018 NCNN_ANDROID=~/ncnn-<ver>-android-vulkan tools/build_android.sh
set -euo pipefail
cd "$(dirname "$0")/.."
: "${ANDROID_NDK:?set ANDROID_NDK to the NDK root (r26+)}"
: "${NCNN_ANDROID:?set NCNN_ANDROID to an unpacked ncnn-<ver>-android-vulkan package}"
tools/fetch_deps.sh
cmake -S . -B build-android-arm64 -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-29 -DANDROID_STL=c++_static \
  -DCMAKE_BUILD_TYPE=Release \
  -Dncnn_DIR="$NCNN_ANDROID/arm64-v8a/lib/cmake/ncnn"
cmake --build build-android-arm64 --target refocal-probe test_blocklist test_sentinel
file build-android-arm64/refocal-probe || true
