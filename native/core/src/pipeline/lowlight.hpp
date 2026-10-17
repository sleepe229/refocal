// Low-light enhancement for old and dark photos (S9, 1.1): HVI-CIDNet (old.lowlight-cidnet).
// The network works in CIDNet's HVI colour space; the transforms are here (upstream
// net/HVI_transform.py, with its learnt density k from model.json), the graph is HVI -> HVI.
// Its attention spans the whole image, so it runs once, on the photo scaled to at most
// [max_side] px (input a multiple of 8, reflect-padded); the correction it makes (output - input,
// in HVI) is upsampled bilinearly and added to each full-size pixel's HVI.
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <functional>

#include "backend/backend.hpp"
#include "image/image.hpp"

namespace enh {

inline constexpr int kLowLightMultiple = 8;   // three bilinear halvings
inline constexpr int kLowLightMaxSide = 384;  // S9 run 39065558081

struct Hvi {
  float h, v, i;
};

// RGB in [0, 1] -> HVI, and back (upstream HVIT / PHVIT, gates off).
Hvi hvi_of_rgb(float r, float g, float b, float k);
void rgb_of_hvi(Hvi x, float k, float& r, float& g, float& b);

// Runs [be] (HVI 3 x h x w -> HVI) as above. [k]: the pack's density_k.
Rgb8 enhance_low_light(InferenceBackend& be, const Rgb8& img, float k,
                       int max_side = kLowLightMaxSide);

}  // namespace enh
