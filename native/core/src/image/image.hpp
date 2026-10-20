// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <cmath>
#include <cstdint>
#include <string>
#include <vector>

namespace enh {

// Half away from zero, then clamped. uint8_t(v + 0.5) is the cast
// bugprone-incorrect-roundings rejects, and a bare uint8_t(lround(v)) wraps 256 to 0.
inline uint8_t round_u8(double v) {
  long r = std::lround(v);
  if (r < 0) r = 0;
  if (r > 255) r = 255;
  return static_cast<uint8_t>(r);
}

// Same rounding for a coordinate or a count that is known to fit in int once clamped.
inline int round_int(double v, int lo, int hi) {
  long r = std::lround(v);
  if (r < lo) r = lo;
  if (r > hi) r = hi;
  return static_cast<int>(r);
}

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
