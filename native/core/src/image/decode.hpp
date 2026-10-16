// Input decoding for every format (ADR-0003, FR-IMP-003): JPEG (libjpeg-turbo), PNG (libpng),
// WebP (libwebp) in the core; HEIC/HEIF/AVIF/GIF/BMP by the platform (Android AImageDecoder,
// API 30+). Output is RGB8 with alpha composited onto white (what the SR model sees); the
// alpha itself is handed out in SourceMeta (FR-IMP-007: the job keeps it, PNG and WebP exports
// get it back, scaled separately). Size limits are checked on the header before any pixel is
// decoded.
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "image/image.hpp"

namespace enh {

// SEC-INP-002
inline constexpr int kMaxSide = 30000;
inline constexpr double kMaxPixels = 200e6;
inline constexpr int64_t kMaxFileBytes = int64_t(200) << 20;

struct ImageInfo {
  int w = 0, h = 0;       // as stored (before orientation)
  int orientation = 1;    // EXIF 1..8; 1 when the decoder already applied it
  std::string format;     // jpeg | png | webp | heif | avif | gif | bmp | other
  bool alpha = false;     // had transparency (composited onto white; SourceMeta::alpha)
  bool animated = false;  // first frame only
};

// Metadata carried to the result (ADR-0018). exif is a bare TIFF block.
struct SourceMeta {
  std::vector<uint8_t> exif;
  std::vector<uint8_t> icc;
  // Straight alpha, w*h as stored (before orientation), when the image has transparency.
  std::vector<uint8_t> alpha;
};

// By magic bytes: jpeg | png | webp | heif | avif | gif | bmp | "" (unknown).
std::string sniff_format(const std::string& path);

// Header only. Throws ENH_E_INVALID (unsupported/corrupt), ENH_E_LIMIT (SEC-INP-002), ENH_E_IO.
ImageInfo probe_image(const std::string& path);
// Orientation is reported in info, not applied.
Rgb8 decode_image(const std::string& path, ImageInfo* info = nullptr, SourceMeta* meta = nullptr);

// ---- per-format back ends (decode.cpp dispatches) ----
ImageInfo png_probe(const std::string& path);
Rgb8 png_decode(const std::string& path, SourceMeta* meta);
ImageInfo webp_probe(const std::string& path);
Rgb8 webp_decode(const std::string& path, SourceMeta* meta);
bool platform_decoder_available();
ImageInfo platform_probe(const std::string& path);  // orientation already applied
Rgb8 platform_decode(const std::string& path, std::vector<uint8_t>* alpha);

// Composites interleaved RGBA8 (straight or premultiplied alpha) onto white, in place:
// `px` holds w*h*4 bytes on entry and w*h*3 on return; the alpha goes to [alpha] if given.
void rgba_to_rgb_on_white(std::vector<uint8_t>& px, size_t pixels, bool premultiplied,
                          std::vector<uint8_t>* alpha = nullptr);

}  // namespace enh
