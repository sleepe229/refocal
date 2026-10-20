// Scratch removal for old photos (S9, 1.1): the BOPBTL U-Net finds scratches on the grey image
// at 256 px on the short side (old.scratch), MI-GAN fills them (old.inpaint-migan). The fill is
// tiled (512 px inputs: a 384 px core and 64 px of context), only tiles whose core holds a hole
// run, and only hole pixels change: the known ones keep the photo exactly, with upstream's
// blend at the hole border (the known mask max-pooled 3x3, then a 5x5 Gaussian, sigma 1).
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <cstdint>
#include <functional>
#include <vector>

#include "backend/backend.hpp"
#include "image/image.hpp"
#include "util/size.hpp"

namespace enh {

inline constexpr int kScratchShortSide = 256;
inline constexpr int kScratchMultiple = 16;       // four stride-2 levels
inline constexpr float kScratchThreshold = 0.4f;  // upstream detection.py
inline constexpr int kInpaintSize = 512;
inline constexpr int kInpaintPad = 64;

// One byte per pixel, row-major: 255 hole (scratch), 0 kept.
struct Mask8 {
  int w = 0, h = 0;
  std::vector<uint8_t> px;
  uint8_t at(int x, int y) const { return px[sz(y) * sz(w) + sz(x)]; }
  size_t count() const;
};

// The detector's input size for a w x h image: the short side 256, each side rounded to a
// multiple of 16 (upstream's scale_tensor).
void scratch_input_size(int w, int h, int& nw, int& nh);

// Runs the detector [be] (grey [0, 1] -> probability, one input and output) on [img]; the mask
// at the image size (nearest, as upstream), grown by [grow] px.
Mask8 detect_scratches(InferenceBackend& be, const Rgb8& img, float threshold = kScratchThreshold,
                       int grow = 1);

// Fills the holes of [mask] with the inpainting model [be] (4 x 512 x 512 -> 3 x 512 x 512).
// [tick](done, total) after each tile run; returning false stops (the caller throws).
Rgb8 inpaint(InferenceBackend& be, const Rgb8& img, const Mask8& mask,
             const std::function<bool(int, int)>& tick = {});

}  // namespace enh
