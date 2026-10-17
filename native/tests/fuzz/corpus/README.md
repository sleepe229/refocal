Seed inputs for the libFuzzer targets in `..` (generated with Pillow: tiny JPEG/PNG/WebP with
EXIF orientation, GPS and a LittleCMS-generated sRGB profile; a bare EXIF APP1 and TIFF block;
zip: two small .rfpack-like archives, stored and deflated, made with Python zipfile).
heif: `iloc-offset-overflow.heic`, the fuzz-ga finding of 2026-10-17 (an item offset near
INT64_MAX overflowed when attaching metadata), kept as a regression seed.
CI keeps the grown corpus in its cache; only these seeds are in git.
