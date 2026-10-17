// SPDX-License-Identifier: Apache-2.0
#include "pipeline/jpeg_clean.hpp"

#include <mat.h>

#include <algorithm>
#include <cmath>
#include <vector>

#include "pipeline/geometry.hpp"
#include "util/error.hpp"

namespace enh {

float jpeg_qf_of_quality(int quality) {
  if (quality < 1 || quality > 100) quality = 50;
  return 1.f - float(quality) / 100.f;
}

Rgb8 jpeg_clean(InferenceBackend& be, const Rgb8& img, float qf, int tile, int pad,
                const std::function<bool(int, int)>& tick) {
  const Geometry g = Geometry::make(img.w, img.h, tile, pad, 1, 1);
  const int P = g.pad;
  auto up8 = [](int n) {
    return (n + kJpegCleanMultiple - 1) / kJpegCleanMultiple * kJpegCleanMultiple;
  };
  const int nw = up8(g.net_in_w()), nh = up8(g.net_in_h());
  ncnn::Mat q(1, 1, 1);
  q[0] = std::clamp(qf, 0.f, 1.f);

  Rgb8 out;
  out.w = img.w;
  out.h = img.h;
  out.px.resize(img.px.size());
  std::vector<int> colidx(static_cast<size_t>(nw));
  const int total = g.tiles();
  int done = 0;
  for (int b = 0; b < g.bands(); ++b) {
    const int y0 = g.ys[size_t(b)];
    // Rows this band owns (tiles overlap where the last one is shifted inward).
    const int oy0 = g.band_in_y0(b), oy1 = g.band_in_y1(b);
    for (int j = 0; j < g.tiles_per_band(); ++j) {
      const int x0 = g.xs[size_t(j)];
      const int ox0 = owned_start(g.xs, j, g.tw);
      const int ox1 = j + 1 < g.tiles_per_band() ? owned_start(g.xs, j + 1, g.tw) : g.in_w;
      ncnn::Mat in(nw, nh, 3);
      for (int xx = 0; xx < nw; ++xx) colidx[size_t(xx)] = reflect101(x0 - P + xx, g.in_w);
      for (int yy = 0; yy < nh; ++yy) {
        const uint8_t* row = img.row(reflect101(y0 - P + yy, g.in_h));
        float* r = in.channel(0).row(yy);
        float* gr = in.channel(1).row(yy);
        float* bl = in.channel(2).row(yy);
        for (int xx = 0; xx < nw; ++xx) {
          const uint8_t* p = row + colidx[size_t(xx)] * 3;
          r[xx] = p[0] * (1.f / 255.f);
          gr[xx] = p[1] * (1.f / 255.f);
          bl[xx] = p[2] * (1.f / 255.f);
        }
      }
      // By name: ncnn lists every unconsumed blob as an output, in any order (backend.hpp).
      const std::vector<ncnn::Mat> res = be.run_inputs({in, q}, {"out0"});
      if (res.empty() || res[0].w != nw || res[0].h != nh || res[0].c != 3)
        fail(ENH_E_BACKEND, "jpeg cleanup: unexpected output shape");
      const ncnn::Mat& o = res[0];
      for (int y = oy0; y < oy1; ++y) {
        const int yy = y - y0 + P;
        const float* r = o.channel(0).row(yy);
        const float* gr = o.channel(1).row(yy);
        const float* bl = o.channel(2).row(yy);
        uint8_t* dst = out.row(y);
        for (int x = ox0; x < ox1; ++x) {
          const int xx = x - x0 + P;
          auto u8 = [](float v) { return uint8_t(std::lround(std::clamp(v, 0.f, 1.f) * 255.f)); };
          dst[x * 3] = u8(r[xx]);
          dst[x * 3 + 1] = u8(gr[xx]);
          dst[x * 3 + 2] = u8(bl[xx]);
        }
      }
      ++done;
      if (tick && !tick(done, total)) fail(ENH_E_CANCELLED, "jpeg cleanup stopped");
    }
  }
  return out;
}

}  // namespace enh
