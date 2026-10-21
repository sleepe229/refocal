# Refocal

**Bring your photos back into focus. On your phone.**

Refocal is an open-source, cross-platform (Flutter, Android + iOS) AI photo enhancer:
upscaling, denoising and face restoration that run **entirely on the device** —
no servers, no accounts, no telemetry.

> Status: **public beta (0.5).** Android only; iOS is not started. Download `refocal-…-github-arm64-v8a.apk` from
> [GitHub Releases](https://github.com/sleepe229/refocal/releases): it can update itself
> (ADR-0027); the plain `…-arm64-v8a.apk` is the build F-Droid checks against; an F-Droid listing is under
> review. What changed: [CHANGELOG.md](CHANGELOG.md). The technical specification lives in
> [`docs/spec/`](docs/spec/README.md) (in Russian).

## Principles

- **On-device only.** Photos never leave the phone. Network is used only to download models on explicit user action.
- **Honest results.** AI invents details; results are labeled as AI-edited, and you control how much faces may change.
- **Free and open.** Apache-2.0, no ads, no subscriptions.

## Repository layout

| Path | Contents |
|---|---|
| `app/` | Flutter application (Android flavors `play`, `fdroid`; iOS) |
| `packages/` | `refocal_core` (pure Dart), `refocal_ffi` (FFI plugin → `native/`), `refocal_platform` (platform services) |
| `native/` | Shared C++ core `libenh` (C ABI `native/include/enh.h`), ncnn as a submodule |
| `flutter/` | Flutter SDK, pinned as a git submodule (reproducible builds) |
| `tools/rebuilder/` | Pinned Docker toolchain for reproducible Android builds (S8) |
| `spikes/` | M0 technical spikes |
| `docs/spec/` | Technical specification |
| `ml/` | Model conversion, evaluation, golden set *(planned)* |

## Building

```sh
git submodule update --init --recursive
export PATH="$PWD/flutter/bin:$PATH"
flutter pub get                  # pub workspace: app + packages
flutter analyze app packages
(cd packages/refocal_core && dart test) && (cd app && flutter test)

# native core + tests on the host
cmake -S native -B native/build-host -DENH_BUILD_TESTS=ON && cmake --build native/build-host -j
ctest --test-dir native/build-host

# bundled model (weights are not in git; checked against tools/models/models.lock)
tools/models/fetch.sh --from DIR

# desktop CLI on the same core (golden runs, perf)
cmake -S native -B native/build-host -DENH_BUILD_CLI=ON && cmake --build native/build-host -j
native/build-host/refocal-cli run --models MODELS --work /tmp/jobs --input in.jpg --out out.jpg

# end-to-end on a headless AOSP emulator (needs /dev/kvm), x86_64 profile APK
docker build -t refocal-emulator:35 tools/emulator
tools/emulator/e2e.sh app/build/app/outputs/flutter-apk/app-fdroid-profile.apk

# Android release APK in the pinned toolchain (no Android SDK needed on the host)
docker build -t refocal-rebuilder:s8 tools/rebuilder
tools/rebuilder/s8.sh            # two independent builds + diffoscope + signature copy
```

## Releases

Beta builds are published as GitHub pre-releases by `.github/workflows/release.yml`; see
[docs/ops/release.md](docs/ops/release.md) and [CHANGELOG.md](CHANGELOG.md).

## Translations

[![Translation status](https://hosted.weblate.org/widget/refocal/svg-badge.svg)](https://hosted.weblate.org/engage/refocal/)

Refocal is translated on [Hosted Weblate](https://hosted.weblate.org/engage/refocal/), which
opens pull requests with the changes. Thanks to Weblate for the free libre hosting.

## Privacy

Refocal collects no data: [PRIVACY.md](PRIVACY.md), also at
<https://sleepe229.github.io/refocal/privacy>.

## License

Code: [Apache-2.0](LICENSE). Some optional face-restoration models are distributed
by their authors under **non-commercial** licenses and are downloaded separately,
on demand, after you accept their license.
