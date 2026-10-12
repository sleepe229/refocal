// Tile/band geometry of the SR pass (S2): fixed tile core T, reflect pad P, last tile shifted
// inward so every network input has the same shape; a band is one row of tiles.
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <vector>

namespace enh {

std::vector<int> tile_origins(int n, int t);
int owned_start(const std::vector<int>& origins, int i, int t);
int reflect101(int i, int n);

struct Geometry {
  int in_w = 0, in_h = 0;  // SR input (after the optional "fast 2x" pre-downscale)
  int tw = 0, th = 0;      // tile core
  int pad = 0;
  int model_scale = 4;
  int down = 1;            // area downscale after SR: 1 (x4), 2 (x2), 4 (x1)
  int sr_w = 0, sr_h = 0;  // model-scale output
  int out_w = 0, out_h = 0;
  std::vector<int> xs, ys;

  static Geometry make(int in_w, int in_h, int tile, int pad, int model_scale, int down);
  int bands() const { return int(ys.size()); }
  int tiles_per_band() const { return int(xs.size()); }
  int tiles() const { return bands() * tiles_per_band(); }
  int band_in_y0(int b) const { return owned_start(ys, b, th); }
  int band_in_y1(int b) const { return b + 1 < bands() ? owned_start(ys, b + 1, th) : in_h; }
  int band_sr_rows(int b) const { return model_scale * (band_in_y1(b) - band_in_y0(b)); }
  int band_out_rows(int b) const { return band_sr_rows(b) / down; }
  int band_out_y0(int b) const { return model_scale * band_in_y0(b) / down; }
  int net_in_w() const { return tw + 2 * pad; }
  int net_in_h() const { return th + 2 * pad; }
};

}  // namespace enh
