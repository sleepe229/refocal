# Changelog

## 0.0.1-alpha.1

First developer preview. **Not tested on phones yet** — only on a desktop and a headless
Android 15 emulator. Expect bugs; please report them with the device model and Android version.

What works (Android 10+, arm64):
- Pick a photo in the system Photo Picker (no access to your whole gallery is requested).
- Enhance on the device: 4×, 2× or Fast 2× (default for photos of 8 MP and more), with
  progress and cancel.
- Compare before/after with a slider; save the result as JPEG to `Pictures/Refocal`.
- GPU (Vulkan) when the device passes a correctness check, otherwise the CPU; crashes in the
  GPU driver switch the next run to the CPU.
- No accounts, ads, telemetry or network use.

Known limitations:
- Android only; iOS is not available yet.
- JPEG input only (no HEIC/PNG/WebP yet); EXIF metadata is not copied to the result.
- Keep the app open while a photo is processed: there is no background processing yet, and a
  photo that was interrupted cannot be resumed from the UI.
- No face restoration, history, presets or other output formats yet.
- Processing time depends heavily on the phone; large photos at 4× can take minutes.

Model: Real-ESRGAN realesr-general-x4v3 (BSD-3-Clause), bundled.
