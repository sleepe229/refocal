// Pixel operations used by the pipeline (CPU, RGB8).
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <cstdint>
#include <cstddef>
#include <vector>

#include "image/image.hpp"

namespace enh {

// Applies EXIF orientation 1..8 so the result is upright (orientation 1).
Rgb8 apply_orientation(Rgb8 src, int orientation);

// Box (area) downscale by an integer factor of `rows` rows (multiple of f), width w -> w/f.
void area_down(const uint8_t* src, int w, int rows, int f, uint8_t* dst);
// Whole-image area downscale; odd remainder rows/cols are dropped (as in S2 "fast 2x").
Rgb8 area_down(const Rgb8& src, int f);

// Area-accumulated preview (<= max_side px), fed band by band (S2).
class PreviewAccumulator {
 public:
  void init(int w, int h, int max_side);
  void add_rows(const uint8_t* rgb, int y0, int rows);
  Rgb8 finish() const;
  int width() const { return pw_; }
  int height() const { return ph_; }

 private:
  int w_ = 0, h_ = 0, pw_ = 0, ph_ = 0;
  std::vector<int> colmap_;
  std::vector<uint32_t> sum_, colcount_, rowcount_;
};

// Lanczos-3 resampling of a whole source image to out_w x out_h, produced row by row in
// increasing order (export: the base of the strength blend, ADR-0012, FR-ENH-005). Keeps only
// a few horizontally resampled source rows besides the source itself. Same size: a copy.
class LanczosResampler {
 public:
  LanczosResampler(const Rgb8& src, int out_w, int out_h);
  // Writes rows [y0, y0 + rows) as RGB8 into dst (rows * out_w * 3 bytes). y0 must not decrease.
  void rows(int y0, int rows, uint8_t* dst);

 private:
  struct Axis {
    int taps = 0;
    std::vector<int> idx;     // [out][taps], clamped source indices
    std::vector<float> w;     // [out][taps], normalized
  };
  static Axis make_axis(int in, int out);
  const float* hrow(int sy);

  const Rgb8& src_;
  int out_w_, out_h_;
  Axis ax_, ay_;
  std::vector<std::vector<float>> ring_;  // horizontally resampled source rows
  std::vector<int> ring_y_;
};

// out = base + (sr - base) * strength, strength in [0, 1] (8-bit fixed point), n bytes.
void blend(const uint8_t* base, const uint8_t* sr, size_t n, float strength, uint8_t* out);

}  // namespace enh
