// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace enh {

// Interleaved RGB8, row-major, no padding.
struct Rgb8 {
  int w = 0, h = 0;
  std::vector<uint8_t> px;
  size_t stride() const { return size_t(w) * 3; }
  uint8_t* row(int y) { return px.data() + size_t(y) * stride(); }
  const uint8_t* row(int y) const { return px.data() + size_t(y) * stride(); }
};

// Metadata written into an export (ADR-0018) by JpegWriter, PngWriter and WebpWriter, each in
// its format's container (JPEG APP1/APP2 markers, PNG eXIf/iTXt/iCCP, WebP EXIF/XMP/ICCP).
struct OutputMeta {
  std::vector<uint8_t> exif;  // TIFF block
  std::string xmp;
  std::vector<uint8_t> icc;
};

}  // namespace enh
