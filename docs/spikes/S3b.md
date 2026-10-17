# S3b / S2b / S1b: first device measurements

| | |
|---|---|
| Date | 2026-10-17 |
| Device | Samsung Galaxy S24 Ultra (SM-S928B), Snapdragon 8 Gen 3 (SM8650), Adreno 750, 12 GB (MemTotal 10.8 GiB), Android 14 |
| Build | release `fdroid` arm64 of `feat/0.5-heic` (0.3.0-beta.1 + 0.5 features + HEIC), signed with a throwaway key |
| Inputs | synthetic test photos (Solvay conference 1927, public domain, resized, noise σ 4–6, EXIF camera/date/GPS, sRGB ICC); no user photos |
| Verdict | **Budgets met for T2; the tier thresholds were wrong for GPUs (fixed: GPU thresholds, `tier.hpp`)** |

## Measurements

Times from the core's `job done` log line (`timings.sr`, `total`); peak memory is the process
`VmHWM`. One run each, phone on the charger, thermal status 0 (none) throughout.

| Check | Result | Budget (02-nfr) |
|---|---|---|
| Benchmark (FR-SET-003) | Vulkan Adreno 750 fp16, tile128 **47 ms**, gate PSNR 44.6 dB | — |
| NFR-PERF-001: 1 MP → 4×, compact, no faces | **3.8 s** (SR 3.1 s) | T2 ≤ 5 s ✅ |
| 1 MP → 4× with 29 faces (GFPGAN, Auto) | 34.9 s (SR 3.3 s, faces ≈ 1.07 s each with alignment and paste) | NFR-PERF-003 T1 ≤ 3 s ✅, T2 ≤ 1 s ⚠️ |
| NFR-PERF-002: 12 MP → 2× (8000 × 6000) | **38.1 s** | T2 ≤ 60 s ✅ |
| NFR-MEM-001: peak during the runs above | 959–982 MB | T1 ≤ 1.0 GB ✅, T2 ≤ 1.8 GB ✅ |
| NFR-PERF-008: cancel | **40 ms** from the tap to `job ended: cancelled` | T2 ≤ 0.5 s ✅ |
| HEIC (FR-EXP-002), 16 MP result | 5.4 s; 8 × 8 grid of 64 tiles; ICC on primary and tiles, Exif and XMP AI marker; libheif decodes it with the same ICC (`check_heic.py`) | ✅ |
| Metadata (JPEG) | ICC kept, camera and date kept, GPS removed, XMP DigitalSourceType | ✅ |
| EXIF orientation 6 | shown and processed rotated, as the gallery shows it | ✅ |

## Quality, against a ground truth

The 1600 × 1156 original, downscaled ×4 (bicubic) with noise σ 4, enhanced on the phone (Auto:
4×, denoise medium), compared with the original:

| | PSNR | SSIM | LPIPS (alex) ↓ |
|---|---|---|---|
| Bicubic ×4 | 27.1 dB | 0.767 | 0.496 |
| Lanczos ×4 | 27.4 dB | 0.770 | 0.510 |
| Refocal ×4 (phone) | 23.9 dB | 0.707 | **0.354** |

As expected of a GAN SR model, pixel metrics drop and the perceptual one improves (31% closer
than Lanczos). Edges, clothes and texture are clearly better. **Faces of 10–15 px in the input
come out as waxy masks**: the detector (YuNet on the input) misses them, so Auto does not offer
face restoration and the SR model paints them. Follow-up: detect faces on the SR output when
the input faces are too small (0.5).

## Findings

1. **Tier thresholds (fixed).** The S3 derivation assumed 1 MP = 140 tile128 units, true for the
   CPU. On the GPU a job runs 256 px tiles, which the 128 px benchmark tile under-uses: here 1 MP
   took 66 units. With the old 25 ms T2 limit this phone was T1, which hid 8× and the x4plus pack
   (T2 only). GPU thresholds now T2 ≤ 55 ms, T1 ≤ 170 ms (05 §6.3 amendment); CPU unchanged.
2. **A tap on the selected scale deselected it** and left "Enhance" disabled without a word
   (fixed in the editor).
3. Face restoration at ~1 s per face is over the T2 per-face budget; with many faces (group
   photos) it dominates the job. Candidates: batch faces on the GPU, skip faces under a size.

Not measured yet: battery (NFR-BAT-001), 20-job thermal run (NFR-THERM-001), background
processing on a Samsung (FGS, checked on the emulator only), TalkBack audit, more devices.
