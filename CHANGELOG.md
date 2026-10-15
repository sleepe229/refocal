# Changelog

## 0.0.4-alpha.1

Fourth developer preview. Still **not tested on a phone**: only on a desktop and a headless
Android 15 emulator. Please report problems with the device model and Android version.

New:
- **Queue:** choose several photos ("Process several photos") or share several to Refocal, pick
  one preset for all of them, and they are enhanced one after another, also with the screen off.
  Change the order by dragging, remove photos, pause and continue. One photo that fails does not
  stop the others; at the end you see "Done N, failed M". The queue survives a restart of the
  app or the phone.
- Batch results are **saved to the gallery automatically** in your default format (can be
  turned off in Settings or for one batch; then the results wait in the queue).
- **History:** every saved result is listed with its preview and settings; process the photo
  again with other settings while its copy is still there; delete one entry or all. History can
  be turned off in Settings (this also clears it).
- **Presets:** "Fast" and "Quality", and your own: save the settings of a result under a name,
  apply them before enhancing, rename or delete them.
- **Report a problem** (About): shows the app's log in full and lets you share it. File paths
  and links are removed from the log before it is written.
- Settings and your presets are included in your phone's backup (Google); photos, history and
  the queue are not.

Fixed:
- Error messages no longer show internal details such as file paths.
- Two photos picked or shared at the same moment could get the same internal name.

Known limitations:
- Android only; iOS is not available yet.
- In a batch, a photo too large for the chosen scale is processed at the largest scale that fits
  instead of asking.
- WebP is limited to 50 MP (lossless: 24 MP). HEIC output is not available yet. Transparency is
  not kept.
- No face restoration yet. Large photos at 4× can take minutes; the queue does not pause yet
  when the phone gets hot.

Model: Real-ESRGAN realesr-general-x4v3 (BSD-3-Clause), bundled.

## 0.0.3-alpha.1

Third developer preview. Still **not tested on a phone**: only on a desktop and a headless
Android 15 emulator. Please report problems with the device model and Android version.

New:
- **Save as PNG or WebP** as well as JPEG, and **Save as file…** to any folder or app (for example
  Downloads or a cloud drive). Save the same result several times, in different formats, without
  enhancing again. The default format and the JPEG/WebP quality are in Settings.
- **Strength:** a slider under the result blends it with the original. The preview updates right
  away; 100% is the full effect.
- **1×:** same size, only noise and blur are cleaned up.
- **Share to Refocal:** share a photo from the gallery or another app to open it in Refocal.
- **Russian** translation; the language can be changed in Settings.
- A short introduction on first start (also in Settings).
- Notifications use the app's language.
- **Smaller download:** the APK is 13.6 MB (was 29.7 MB). Its native libraries are now
  compressed and unpacked by Android on install, so the installed app takes about as much space
  as before.

Fixed:
- WebP photos whose EXIF starts with an "Exif" header were not rotated upright.
- Android 10: very large HEIC photos are refused before decoding instead of running out of
  memory; HEIC colors are converted to sRGB.
- If Android closed the app's Flutter side while a photo was processed, the notification kept
  Pause and Cancel buttons that did nothing. It is now removed.

Known limitations:
- Android only; iOS is not available yet.
- WebP is limited to 50 MP (lossless: 24 MP); larger results can be saved as JPEG or PNG.
  HEIC output is not available yet. Transparency is not kept.
- Below 100% strength the original photo is needed: results whose original was deleted can
  only be saved at 100%.
- One photo at a time: sharing several photos at once and the queue come later.
- No face restoration, history or presets yet. Large photos at 4× can take minutes.

Model: Real-ESRGAN realesr-general-x4v3 (BSD-3-Clause), bundled.

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
