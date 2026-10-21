# Changelog

## Unreleased

Sharper results from blurry photos.

New:
- **Blurry photos** (old point-and-shoot cameras, slightly out of focus or shaken): Auto
  measures how sharp the photo really is and enhances it from a copy at that sharpness, then
  brings it back to the full size. Edges come out crisper, and processing is faster. Auto's
  explanation says so ("blurry: enhanced at its real sharpness").
- Results get a light sharpening of edges, without bright or dark halos; restored faces are
  not sharpened again. Portrait, Old photo and Adjust handle blurry photos the same way as Auto.
- **No denoise** is now built in: Auto uses it for clean photos without a download.

Fixed:
- **Back in Adjust** closes the panel (as Done does) instead of leaving the photo and the
  settings chosen; the same for picking a part to preview.
- **Downloads you walked away from**: leave the editor while a model downloads and a small bar
  at the bottom shows the progress, without covering anything, then "Model ready". "Back to
  photo" opens the photo with the settings that asked for the model. Close it and it stays
  away until the next download. Back in the editor, the mode shows the download again.
- **Models for faster phones** are no longer hidden or refused: the offer says the model will
  be slow on this phone, and it is yours to try. Auto still picks for the phone.

## 0.8.1-beta.1

Simpler for the first time: fewer decisions, nothing promised that is not there, no work lost
by a slip.

New:
- **Hold to see the original**: a finger held on the result shows the original until it is
  lifted, as the introduction says. The loupe that used this gesture is gone; pinch to zoom
  to real pixels.
- **Models where you want them**: a mode, preset or switch whose model is missing (Portrait,
  Old photo, Anime, faces, JPEG cleanup, brighten, scratches, "Process again" in History)
  offers it right there: one question with the size, the licence text for a non-commercial
  model, then the download runs in the background with a ring around the mode's icon or a bar
  under the switch, and the mode turns on when it is in. No trip to Settings → Models.
- **Editor**: Auto · Portrait · Old photo · Adjust. The scale moved under Adjust, with the
  size of the result for each choice. Enhance no longer waits for Auto: tap it at once.
- **Result**: Share, Filter, Strength and Change as labelled buttons above Save.
- **Safer**: Back and Cancel during processing ask first; Back during the enhancement pauses it
  (continue from the home screen). Deleting an unfinished photo can be undone.
- **Errors** offer Try again, Change settings and Report a problem.
- Preview a part: the frame appears from the … menu, a tap moves it, Preview runs it (a tap on
  the photo no longer drops a frame by surprise).
- An empty home screen says what to do. No face model names, no notes about the processor or
  tile size; "Saved to the gallery".

## 0.8.0-beta.1

A filter for the result.

New:
- **Filter** on the result screen: **Pastel** (soft pink colours, lifted shadows, less
  contrast) with its own amount, and **Light leaks** (warm glows near the edges). They work
  together and with the strength. The photo changes as you go; nothing is processed again.
  What you see is what is saved, in every format.
- The filter is kept in presets and history; a preset with a filter applies it to every photo
  of a queue.
- A finished photo opened from the queue now starts at its preset's strength and filter.

## 0.7.0-beta.1

A simpler app: the photo first, the settings when you look for them.

New:
- **Editor**: the photo fills a dark screen. Below it, what Auto chose in one line, then
  **Auto · Portrait · Old photo · Scale · Adjust** and **Enhance**. **Adjust** opens the other
  presets, the model, denoise, faces and the old-photo tools without hiding the photo. If a
  mode needs a model you do not have (Portrait needs the face model), the editor offers it
  right there.
- **Result**: the comparison fills the screen, with **Share** and **Save** below; save as
  file, strength, save as preset, change settings, details (model, processor, time) and
  "report a bad result" are in the **…** menu. Preview a part is in the editor's **…** menu.
- **Share** sends the result to another app in your default format, with the same location
  and AI-marker settings as a save. It is not saved to the gallery or the history.
- **Home**: your latest results as a grid, what is unfinished, and **Choose a photo**. About
  moved to Settings.
- **Settings** in groups: saved photos, history, presets, storage (one row with its size),
  language; the AI marker, models, device class and the introduction are under **Advanced**.
- Shorter texts throughout; technical details only where you ask for them.

Fixed:
- Sharing the bug-report log: the share sheet could not read the file.
- Security: a crafted HEIC file could make saving metadata write a file that no longer opens
  (found by fuzzing).

## 0.6.0-beta.1

First steps of "old photos" (1.1).

New:
- **Remove JPEG artifacts** (Settings → Models: "JPEG cleanup", fast phones): smooths the
  blocks and halos of strong JPEG compression before enhancing. Auto turns it on for heavily
  compressed JPEGs once the model is installed; the strength comes from the photo itself.
- **Remove scratches** (models "Scratch finder" and "Scratch fill"): finds scratches, cracks
  and dust on old prints and fills them from the photo around them. A switch in the editor;
  dark scratches are not always found yet.
- **Brighten a dark photo** (model "Low light"): lifts shadows and colour of under-exposed
  photos. A switch in the editor; it can make noise in the shadows visible.
- Small faces in group photos (10–15 px) are now found, so Auto offers face restoration for
  them too.
- Models that need a newer version of Refocal are no longer offered.

Fixed:
- Auto failed ("could not analyse the photo") when a face touched the edge of the photo.
- Leaving the editor did not clean up: saved results and copies of the input stayed on the
  phone until the weekly cleanup.
- "Fast 2×" broke in the middle of the word in Russian.
- Security: a crafted HEIC file could make saving metadata misbehave (found by fuzzing).

## 0.5.0-beta.2

Security and packaging fixes for the public beta.

Fixed:
- **Security:** another app could share a link to Refocal's own private files (for example
  history previews) and have them opened in the editor. Only images other apps share are taken
  now.
- Shared or picked files larger than 200 MB are refused while copying, instead of after filling
  the storage.
- Model downloads are size-limited, and every redirect must stay on HTTPS.
- The release APK is built so that F-Droid can reproduce it byte for byte and ship our signed
  APK.

New:
- About links to the privacy policy (also at <https://sleepe229.github.io/refocal/privacy>).

## 0.5.0-beta.1

Public beta. Checked on one phone (Galaxy S24 Ultra), a desktop and an Android 15 emulator.
Please report problems with the device model and Android version (About → Report a problem).

New:
- **Compare:** side by side as well as the slider, zoom and pan both sides together, and a
  loupe (long press) for a close look at the real pixels.
- **8×** for small photos (up to 1.5 MP) on fast phones.
- **More models** (Settings → Models): "High quality" (Real-ESRGAN x4plus, sharper, slower, fast
  phones), "Anime and drawings", and **CodeFormer** for faces with a "Detail ↔ Likeness" slider
  (non-commercial license, shown before download).
- **HEIC** in "Save as file" on phones that can encode it, with the colour profile, date and
  camera, and the AI marker.
- **Report a bad result** under a result: opens a pre-filled GitHub issue you can read and edit;
  the photo is attached only if you choose to.
- **Edit with Refocal** from the gallery's "Edit with", next to "Share".
- **Presets** can be exported to a file and imported.
- **Model updates:** an optional check for newer model versions (off by default).
- Right-to-left languages are laid out right to left.
- A Refocal icon instead of the placeholder.

Fixed:
- Fast phones were classed too low, which hid 8× and "High quality".
- Tapping the selected scale unselected it and left "Enhance" greyed out.
- Security: a crafted model file could write out of bounds in the inference library (ncnn
  CVE-2026-50144). Models are signed, so this needed a signed malicious model; fixed anyway.

Known limitations:
- Android only; iOS is not available yet.
- Face models redraw faces: the result may look like another person, more so for darker skin
  ([bias report](docs/ml/bias-2026-10.md)). By default half the original face is kept.
- Very small faces in low-resolution group photos are not detected and can look waxy
  ([#44](https://github.com/sleepe229/refocal/issues/44)).
- Speed, battery and TalkBack have been checked on one phone only. WebP and HEIC are limited to
  50 MP (lossless WebP: 24 MP).

Models: Real-ESRGAN realesr-general-x4v3 (BSD-3-Clause), bundled, and its denoise variants,
x4plus and anime_6B (BSD-3-Clause, download); YuNet face detector (MIT), bundled; GFPGAN 1.4 and
CodeFormer (non-commercial, download).

## 0.3.0-beta.1

First beta. Still **not tested on a phone**: only on a desktop and a headless Android 15
emulator. Please report problems with the device model and Android version.

New:
- **Zoom:** pinch the before/after comparison up to the result's real pixels (and closer);
  double-tap switches between 1:1 and the whole photo. Even a 48 MP result stays sharp: only
  the visible part is loaded.
- **Preview a part:** tap the photo to choose a part, then "Preview a part" shows it enhanced
  with the current settings in a few seconds, next to the original, before the whole photo.
- **Single faces:** with face restoration on, each face the model would restore has a frame;
  tap it to leave that face as it is.
- **Transparency** is kept when saving as PNG or WebP (JPEG still gets a white background).
- **Result details:** under the result, the model, the processor used and the time it took.
- **Face model offer:** after the introduction, a card on the home screen offers the face model
  for portraits (until you dismiss it).
- Models imported from a `.rfpack` file are listed by their name.
- Copies of your photos kept for unfinished results take at most 1 GB; past that, the oldest
  unfinished results are removed first.

Known limitations:
- Android only; iOS is not available yet.
- HEIC output comes in 0.5 (Android's encoder cannot keep the colour profile and the AI marker).
- Accessibility (TalkBack) and speed on a range of real phones have not been checked yet.
- WebP is limited to 50 MP (lossless: 24 MP).

Models: Real-ESRGAN realesr-general-x4v3 (BSD-3-Clause), bundled, and its denoise 0 and 1.0
variants (download); YuNet face detector (MIT), bundled; GFPGAN 1.4 (non-commercial, download).

## 0.2.0-alpha.1

First alpha. Still **not tested on a phone**: only on a desktop and a headless Android 15
emulator. Please report problems with the device model and Android version.

New:
- **Auto** (selected for every new photo): Refocal looks at the photo — its size, noise and
  faces — and picks the scale, the denoise level and face restoration for this phone. It says
  what it chose, e.g. "4×, faces: 2, denoise medium". Any other choice is one tap away.
- **Face restoration** with an optional face model (non-commercial license, about 177 MB):
  faces are restored and blended with the enhanced photo (50% by default, adjustable), their
  colours kept. "Only faces" restores the faces and simply enlarges the rest, much faster.
  Before the first use Refocal explains what face restoration does. New presets "Portrait"
  and "Old photo".
- **Models** (Settings → Models): download extra models — denoise levels "none" and "strong",
  and the face model. Every model is checked against a signed list before it is used; a
  download continues where it stopped. Without internet, a model can be imported from a
  `.rfpack` file with the same checks.
- **Device class:** a few seconds' speed test after the first start picks the tile size and
  speed settings for the phone; it can be changed in Settings.
- **Low memory:** when the phone runs short of memory, Refocal processes in smaller pieces (the
  same result, slower), switches to another processor, or skips a face it cannot restore, and
  says so. If nothing helps, it asks whether to continue at a smaller size; it never reduces
  the size by itself. In a batch such a photo fails with "not enough memory" instead.

Known limitations:
- Android only; iOS is not available yet.
- Turning off single faces by tapping them comes in 0.3.
- The face model is for non-commercial use only (its license is shown before download).
- Stability and speed on a range of real phones (100 jobs without a crash, speed targets on
  mid-range and high-end phones) have not been measured yet.
- WebP is limited to 50 MP (lossless: 24 MP). HEIC output is not available yet. Transparency is
  not kept.

Models: Real-ESRGAN realesr-general-x4v3 (BSD-3-Clause), bundled, and its denoise 0 and 1.0
variants (download); YuNet face detector (MIT), bundled; GFPGAN 1.4 (non-commercial, download).

## 0.0.5-alpha.1

Fifth developer preview. Still **not tested on a phone**: only on a desktop and a headless
Android 15 emulator. Please report problems with the device model and Android version.

New:
- **Storage** (Settings → Storage): how much space copies of originals, unfinished photos,
  history, cache, the log and the models take, and a button to clear each.
- **No duplicate copies:** a photo picked or shared again reuses the copy Refocal already has.
- **Heat protection:** when the phone gets hot, processing slows down; when it is very hot, it
  waits until the phone cools down, then continues by itself. The editor says so.
- **Accessibility:** a "Show original" button next to the before/after slider, a description of
  the result for screen readers, progress announced every 10%, notes and errors announced.
  Settings stay usable with very large text.

Fixed:
- With very large text, the format and language menus in Settings did not fit.
- An image shared with its address set as data could open an empty screen.

Known limitations:
- Android only; iOS is not available yet.
- One built-in model; face restoration and more models come with the model manager.
- WebP is limited to 50 MP (lossless: 24 MP). HEIC output is not available yet. Transparency is
  not kept.

Model: Real-ESRGAN realesr-general-x4v3 (BSD-3-Clause), bundled.

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
