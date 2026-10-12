# Device check before a release

Install the APK from the CI artifact (`apk-unsigned` is fine for this check) or the draft
release: `adb install -r refocal-*.apk`. Use any Android 10+ phone.

| # | Step | Expected |
|---|---|---|
| 1 | Open the app | Home screen with "Choose a photo"; About shows the version and licenses |
| 2 | Choose a 12 MP camera photo, keep "Fast 2×", Enhance | Progress moves, ETA shown; finishes without a crash |
| 3 | Drag the compare slider | Before/after line follows the finger; the result is sharper, colors unchanged |
| 4 | Save to gallery | Snackbar "Saved"; photo appears in the gallery under Pictures/Refocal |
| 5 | Same photo at 4× | Either finishes or asks to pick a smaller size; no crash |
| 6 | Start, then Cancel | Stops within a second or two |
| 7 | A portrait (rotated) photo | Result is upright |

Then attach `adb logcat -d | grep -E " enh |ncnn|FATAL"` and the output of the About screen to
the release issue. The log shows which backend ran (`gpu gate vulkan_fp16: ok/bad`, or CPU).
