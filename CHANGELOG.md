# Changelog

## 0.0.2-alpha.1

Second developer preview. Still **not tested on a phone** — only on a desktop and a headless
Android 15 emulator. Please report problems with the device model and Android version.

New:
- **More photo formats:** PNG and WebP (including transparent and animated: transparent areas
  become white, animations use the first frame); HEIC/HEIF and AVIF on Android 11+ through the
  system decoder, HEIC on Android 10 as well (converted when picked). Photos larger than
  30000 px per side or 200 MP are refused before decoding.
- **Background processing:** you can leave the app while a photo is processed. A notification
  shows the progress with Pause and Cancel, and tells you when the photo is ready.
- **Pause and continue:** pause a photo and continue it later, also after the app was closed or
  the phone restarted. Unfinished and unsaved photos are listed on the home screen.
- **Metadata in saved photos:** date, camera settings and the color profile (e.g. Display P3)
  are kept; the photo is marked as AI-enhanced (IPTC "trained algorithmic media" in XMP).
  Location, camera serial numbers, maker notes and the EXIF thumbnail are removed.
- **Settings:** keep the location; turn the AI marker off (with a warning).
- Temporary files are cleaned up: saved results right away, everything else after 7 days.

Known limitations:
- Android only; iOS is not available yet.
- Results are JPEG only (PNG/WebP/HEIC output is planned); transparency is not kept.
- EXIF of HEIC/AVIF photos is not copied yet (their orientation and colors are applied).
- One photo at a time: no queue or batch processing yet. On Android 15 the system limits
  background processing to 6 hours a day; after that the photo is paused.
- No face restoration, history, presets yet. Large photos at 4× can take minutes.

Model: Real-ESRGAN realesr-general-x4v3 (BSD-3-Clause), bundled.

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
