// Looks (FR-LOOK-001..004, ADR-0012 amendment 0.8): a global colour filter (one so far, pastel)
// at an amount and an optional light-leak overlay, applied by enh_export after the strength blend, so a look changes
// without processing again. Nothing here depends on the position of a face or reshapes anything
// (15 §3: no beautification): a look is one affine colour transform of the whole photo, the
// leaks a smooth overlay tied to the frame's edges.
//
// The colour transform is a 4 x 5 matrix in the layout of Flutter's ColorFilter.matrix (RGBA
// 0..255, the fifth column an offset in 0..255): the editor previews a look with exactly that
// matrix (enh_look_matrix). It is affine, so it commutes with the strength blend (a lerp), and the
// preview's blend of two layers equals the export's. The leaks are a small image (enh_look_leaks)
// stretched bilinearly over the result and blended with "screen", as the editor draws it.
// Processing stays in the source encoding (ADR-0013).
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <array>
#include <cstdint>
#include <string>
#include <vector>

#include "image/image.hpp"

namespace enh {

using LookMatrix = std::array<float, 20>;

inline constexpr int kLeaksSide = 256;  // ENH_LOOK_LEAKS_SIDE

// Known ids: none pastel.
bool look_known(const std::string& id);

// The matrix of [id] at [amount] 0..1: identity + amount * (preset - identity). Throws
// Error(ENH_E_INVALID) for an unknown id or an amount outside 0..1.
LookMatrix look_matrix(const std::string& id, float amount);

// Applies [m] to n RGB8 pixels in place (alpha is opaque), rounded to the nearest 8-bit value.
void apply_look(const LookMatrix& m, uint8_t* rgb, size_t pixels);

// The leak overlay for a w x h result: RGB8, the longer side kLeaksSide, the aspect of w x h.
Rgb8 leak_grid(int w, int h);

// Stretches a leak grid over a w-wide result row by row (bilinear, texel centres at +0.5 as a
// GPU samples a stretched image) and screen-blends it into the rows.
class LeakOverlay {
 public:
  LeakOverlay(int w, int h);
  // rows [y0, y0 + rows) of the result, rows * w * 3 bytes, blended in place.
  void blend_rows(int y0, int rows, uint8_t* rgb);

 private:
  int w_, h_;
  Rgb8 grid_;
  std::vector<int> x0_;
  std::vector<float> fx_;
};

// One export's look: parsed from output_json "look" ({"id":"pastel","amount":0.8,"leaks":true};
// absent: none).
struct Look {
  std::string id = "none";
  float amount = 1;
  bool leaks = false;
  bool active() const { return id != "none" || leaks; }
};

}  // namespace enh
