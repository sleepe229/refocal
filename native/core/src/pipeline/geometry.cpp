// SPDX-License-Identifier: Apache-2.0
#include "pipeline/geometry.hpp"

#include <algorithm>

#include "util/error.hpp"

namespace enh {

std::vector<int> tile_origins(int n, int t) {
  std::vector<int> o;
  if (t >= n) return {0};
  for (int x = 0; x + t < n; x += t) o.push_back(x);
  o.push_back(n - t);
  return o;
}

int owned_start(const std::vector<int>& o, int i, int t) { return i == 0 ? 0 : o[i - 1] + t; }

int reflect101(int i, int n) {
  if (n == 1) return 0;
  while (i < 0 || i >= n) {
    if (i < 0) i = -i;
    if (i >= n) i = 2 * n - 2 - i;
  }
  return i;
}

Geometry Geometry::make(int in_w, int in_h, int tile, int pad, int model_scale, int down) {
  if (in_w < 1 || in_h < 1) fail(ENH_E_INVALID, "empty image");
  if (down != 1 && down != 2 && down != 4) fail(ENH_E_INVALID, "bad downscale factor");
  if (model_scale % down != 0 && down > model_scale) fail(ENH_E_INVALID, "bad scale");
  Geometry g;
  g.in_w = in_w;
  g.in_h = in_h;
  int t = tile <= 0 ? std::max(in_w, in_h) : tile;
  g.tw = std::min(t, in_w);
  g.th = std::min(t, in_h);
  // reflect101 needs pad < size; a tiny image just gets a smaller pad.
  g.pad = std::max(0, std::min(pad, std::min(in_w, in_h) - 1));
  g.model_scale = model_scale;
  g.down = down;
  g.sr_w = in_w * model_scale;
  g.sr_h = in_h * model_scale;
  g.out_w = g.sr_w / down;
  g.out_h = g.sr_h / down;
  g.xs = tile_origins(in_w, g.tw);
  g.ys = tile_origins(in_h, g.th);
  return g;
}

}  // namespace enh
