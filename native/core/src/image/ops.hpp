// Pixel operations used by the pipeline (CPU, RGB8).
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <cstddef>
#include <cstdint>
#include <functional>
#include <vector>

#include "image/image.hpp"

namespace enh {

// Applies EXIF orientation 1..8 so the result is upright (orientation 1).
Rgb8 apply_orientation(Rgb8 src, int orientation);
// The w x h part at (x, y); the caller keeps it inside the image.
Rgb8 crop(const Rgb8& src, int x, int y, int w, int h);

// Box (area) downscale by an integer factor of `rows` rows (multiple of f), width w -> w/f.
void area_down(const uint8_t* src, int w, int rows, int f, uint8_t* dst);
// Whole-image area downscale; odd remainder rows/cols are dropped (as in S2 "fast 2x").
Rgb8 area_down(const Rgb8& src, int f);
// Downscale to w x h (each <= the source side) by area averaging with fractional pixel
// coverage, separably: the mean of the source area each output pixel covers.
Rgb8 resize_area(const Rgb8& src, int w, int h);

// Half-sample symmetric reflection of an index into [0, n): -1 -> 0, n -> n - 1 (the border
// rule of the effective-resolution estimate and the unsharp mask, ADR-0025).
inline int reflect_half(int i, int n) {
  if (n == 1) return 0;
  while (i < 0 || i >= n) i = i < 0 ? -i - 1 : 2 * n - 1 - i;
  return i;
}

// BT.601 luma of an RGB8 pixel, 0..1.
inline float luma01(const uint8_t* p) {
  return (0.299f * float(p[0]) + 0.587f * float(p[1]) + 0.114f * float(p[2])) * (1.f / 255.f);
}

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

// A row of an image by its index (RGB8, no padding): an image in memory, or bands read from a
// BandStore as they are needed (ADR-0025).
using RowSource = std::function<const uint8_t*(int y)>;

// Lanczos-3 resampling of a whole source image to out_w x out_h, produced row by row in
// increasing order (export: the base of the strength blend, ADR-0012, FR-ENH-005). Keeps only
// a few horizontally resampled source rows besides the source itself. Same size: a copy.
class LanczosResampler {
 public:
  LanczosResampler(const Rgb8& src, int out_w, int out_h);
  // ADR-0025: a source of src_w x src_h given row by row; the rows asked for move forward with
  // the output rows (a window of a few rows around (y + 0.5) * src_h / out_h).
  LanczosResampler(int src_w, int src_h, RowSource row, int out_w, int out_h);
  // Writes rows [y0, y0 + rows) as RGB8 into dst (rows * out_w * 3 bytes). y0 must not decrease.
  void rows(int y0, int rows, uint8_t* dst);

 private:
  struct Axis {
    int taps = 0;
    std::vector<int> idx;  // [out][taps], clamped source indices
    std::vector<float> w;  // [out][taps], normalized
  };
  static Axis make_axis(int in, int out);
  const float* hrow(int sy);

  RowSource row_;
  int out_w_, out_h_;
  Axis ax_, ay_;
  std::vector<std::vector<float>> ring_;  // horizontally resampled source rows
  std::vector<int> ring_y_;
};

// ADR-0025: unsharp mask of the luma, gated by an edge mask, with a halo clamp. y' = y + amount
// * m * (y - G_1.5 * y), m = clamp((|Sobel(G_1 * y)| / 8 - 0.01) / 0.03, 0, 1) (flat and noisy
// areas are left alone), then y' is kept within the 3x3 min/max of y +- 0.02 (no bright or dark
// rings); each channel gets y' - y added. Borders by reflect_half; Gaussian taps truncated at
// 4 sigma; luma01.
// Writes rows [y0, y0 + rows) of an image w x h into dst; [row] is asked for rows within
// kUsmMargin of them (and inside the image), so bands computed apart join without a seam.
inline constexpr int kUsmMargin = 6;
void unsharp_luma(int w, int h, const RowSource& row, int y0, int rows, float amount, uint8_t* dst);

// out = base + (sr - base) * strength, strength in [0, 1] (8-bit fixed point), n bytes.
void blend(const uint8_t* base, const uint8_t* sr, size_t n, float strength, uint8_t* out);

}  // namespace enh
