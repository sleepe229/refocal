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
};

bool is_jpeg_file(const std::string& path);
JpegInfo jpeg_probe(const std::string& path);
// Decodes to RGB8 (grayscale is expanded). Orientation is reported, not applied.
// `meta` receives the EXIF (TIFF block) and the ICC profile.
Rgb8 jpeg_decode(const std::string& path, JpegInfo* info = nullptr, SourceMeta* meta = nullptr);

// Metadata written by JpegWriter right after SOI (ADR-0018): EXIF APP1, XMP APP1, ICC APP2.
// Blocks that do not fit a marker are skipped (EXIF > 64 KB after the rewrite is rare).
struct JpegMeta {
  std::vector<uint8_t> exif;  // TIFF block
  std::string xmp;
  std::vector<uint8_t> icc;
};

// Streaming encoder: rows are pushed in order; the full image is never in memory.
class JpegWriter {
 public:
  JpegWriter(const std::string& path, int w, int h, int quality, const JpegMeta* meta = nullptr);
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
