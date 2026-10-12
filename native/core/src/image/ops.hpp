// Pixel operations used by the pipeline (CPU, RGB8).
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <cstdint>
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

}  // namespace enh
