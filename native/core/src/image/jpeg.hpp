// JPEG decode/encode on libjpeg-turbo. libjpeg errors are converted to enh::Error.
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <cstdint>
#include <cstdio>
#include <memory>
#include <string>
#include <vector>

#include "image/decode.hpp"
#include "image/image.hpp"

namespace enh {

struct JpegInfo {
  int w = 0, h = 0, components = 0;
  int orientation = 1;  // EXIF 1..8
  // IJG quality 1..100 closest to the luminance quantization table (S9: the QF of the JPEG
  // cleanup pass); 0 when the file has no table 0. Approximate for non-IJG (camera) tables.
  int quality = 0;
};

// The IJG quality whose scaled standard luminance table is closest to [table] (64 entries,
// natural order, as libjpeg keeps them).
int jpeg_quality_of_table(const uint16_t* table);

JpegInfo jpeg_probe(const std::string& path);
// Decodes to RGB8 (grayscale is expanded). Orientation is reported, not applied.
// `meta` receives the EXIF (TIFF block) and the ICC profile.
Rgb8 jpeg_decode(const std::string& path, JpegInfo* info = nullptr, SourceMeta* meta = nullptr);

// Streaming encoder: rows are pushed in order; the full image is never in memory.
// `meta` goes right after SOI (ADR-0018): EXIF APP1, XMP APP1, ICC APP2. Blocks that do not
// fit a marker are skipped (EXIF > 64 KB after the rewrite is rare).
class JpegWriter {
 public:
  JpegWriter(const std::string& path, int w, int h, int quality, const OutputMeta* meta = nullptr);
  ~JpegWriter();
  JpegWriter(const JpegWriter&) = delete;
  JpegWriter& operator=(const JpegWriter&) = delete;
  void write_rows(const uint8_t* rgb, int rows);
  void finish();

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

void jpeg_encode(const std::string& path, const Rgb8& img, int quality);

}  // namespace enh
