// Output encoders besides JPEG (FR-EXP-001, ADR-0003, ADR-0018). Same row-push interface as
// JpegWriter, same metadata (OutputMeta: EXIF TIFF block, XMP packet, ICC profile).
// PNG streams rows to disk; WebP cannot (libwebp encodes a whole picture): WebpWriter collects
// RGB (3 B/px) plus libwebp's YUV (1.5 B/px) or ARGB (4 B/px) copy, so it is size-limited.
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <cstdint>
#include <memory>
#include <string>

#include "image/image.hpp"

namespace enh {

// WebP format limit (VP8/VP8L: 14-bit dimensions).
inline constexpr int kWebpMaxSide = 16383;
// Peak memory bounds (NFR-MEM-001, 600 MB): ~4.5 B/px lossy, ~7 B/px plus encoder state lossless.
inline constexpr double kWebpMaxPixels = 50e6;
inline constexpr double kWebpLosslessMaxPixels = 24e6;

class PngWriter {
 public:
  // [alpha]: RGBA output; write_rows then takes the alpha rows (1 B/px) too (FR-IMP-007).
  PngWriter(const std::string& path, int w, int h, const OutputMeta* meta = nullptr,
            bool alpha = false);
  ~PngWriter();
  PngWriter(const PngWriter&) = delete;
  PngWriter& operator=(const PngWriter&) = delete;
  void write_rows(const uint8_t* rgb, int rows, const uint8_t* alpha = nullptr);
  void finish();

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

// Throws ENH_E_LIMIT above kWebpMaxSide, kWebpMaxPixels or (lossless) kWebpLosslessMaxPixels.
// `quality` 1..100 is the lossy quality; lossless uses a fixed effort (preset 3).
class WebpWriter {
 public:
  // [alpha]: as PngWriter (RGBA collected: 4 B/px instead of 3).
  WebpWriter(const std::string& path, int w, int h, int quality, bool lossless,
             const OutputMeta* meta = nullptr, bool alpha = false);
  ~WebpWriter();
  WebpWriter(const WebpWriter&) = delete;
  WebpWriter& operator=(const WebpWriter&) = delete;
  void write_rows(const uint8_t* rgb, int rows, const uint8_t* alpha = nullptr);
  void finish();

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace enh
