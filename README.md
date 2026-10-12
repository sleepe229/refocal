# Refocal

**Bring your photos back into focus. On your phone.**

Refocal is an open-source, cross-platform (Flutter, Android + iOS) AI photo enhancer:
upscaling, denoising and face restoration that run **entirely on the device** —
no servers, no accounts, no telemetry.

> Status: **pre-alpha / design phase.** The technical specification lives in
> [`docs/spec/`](docs/spec/README.md) (in Russian). Current milestone: M0 spikes.

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

# Android release APK in the pinned toolchain (no Android SDK needed on the host)
docker build -t refocal-rebuilder:s8 tools/rebuilder
tools/rebuilder/s8.sh            # two independent builds + diffoscope + signature copy
```

## License

Code: [Apache-2.0](LICENSE). Some optional face-restoration models are distributed
by their authors under **non-commercial** licenses and are downloaded separately,
on demand, after you accept their license.
