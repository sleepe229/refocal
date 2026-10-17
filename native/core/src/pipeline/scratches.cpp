// SPDX-License-Identifier: Apache-2.0
#include "pipeline/scratches.hpp"

#include <mat.h>

#include <algorithm>
#include <cmath>

#include "image/ops.hpp"
#include "pipeline/geometry.hpp"
#include "util/error.hpp"

namespace enh {

namespace {

// Bilinear resample to w x h (pixel centres aligned), for an image smaller than the detector's.
Rgb8 resize_bilinear(const Rgb8& src, int w, int h) {
  Rgb8 out;
  out.w = w;
  out.h = h;
  out.px.resize(size_t(w) * h * 3);
  for (int y = 0; y < h; ++y) {
    const float fy = std::clamp((y + 0.5f) * src.h / h - 0.5f, 0.f, float(src.h - 1));
    const int y0 = int(fy), y1 = std::min(y0 + 1, src.h - 1);
    const float ay = fy - y0;
    for (int x = 0; x < w; ++x) {
      const float fx = std::clamp((x + 0.5f) * src.w / w - 0.5f, 0.f, float(src.w - 1));
      const int x0 = int(fx), x1 = std::min(x0 + 1, src.w - 1);
      const float ax = fx - x0;
      for (int c = 0; c < 3; ++c) {
        const float top = src.row(y0)[x0 * 3 + c] * (1 - ax) + src.row(y0)[x1 * 3 + c] * ax;
        const float bot = src.row(y1)[x0 * 3 + c] * (1 - ax) + src.row(y1)[x1 * 3 + c] * ax;
        out.row(y)[x * 3 + c] = uint8_t(std::lround(top * (1 - ay) + bot * ay));
      }
    }
  }
  return out;
}

// Square max filter of radius [r] (separable), in place.
void dilate(Mask8& m, int r) {
  if (r <= 0) return;
  std::vector<uint8_t> tmp(m.px.size());
  for (int y = 0; y < m.h; ++y)
    for (int x = 0; x < m.w; ++x) {
      uint8_t v = 0;
      for (int k = std::max(0, x - r); k <= std::min(m.w - 1, x + r) && !v; ++k) v = m.at(k, y);
      tmp[size_t(y) * m.w + x] = v;
    }
  for (int y = 0; y < m.h; ++y)
    for (int x = 0; x < m.w; ++x) {
      uint8_t v = 0;
      for (int k = std::max(0, y - r); k <= std::min(m.h - 1, y + r) && !v; ++k)
        v = tmp[size_t(k) * m.w + x];
      m.px[size_t(y) * m.w + x] = v;
    }
}

// Upstream's blend weight of the photo (create_onnx_pipeline.py postprocess): the known mask
// max-pooled 3x3 (the hole shrinks by a pixel), then a 5x5 Gaussian (sigma 1, reflect pad).
// 255 keeps the photo, 0 takes the fill.
std::vector<uint8_t> blend_weight(const Mask8& hole) {
  const int w = hole.w, h = hole.h;
  std::vector<float> known(size_t(w) * h);
  for (int y = 0; y < h; ++y)
    for (int x = 0; x < w; ++x) {
      bool any = false;
      for (int dy = -1; dy <= 1 && !any; ++dy)
        for (int dx = -1; dx <= 1 && !any; ++dx) {
          const int xx = x + dx, yy = y + dy;
          any = xx >= 0 && yy >= 0 && xx < w && yy < h && !hole.at(xx, yy);
        }
      known[size_t(y) * w + x] = any ? 1.f : 0.f;
    }
  float k[5];
  float sum = 0;
  for (int i = 0; i < 5; ++i) sum += k[i] = std::exp(-float((i - 2) * (i - 2)) / 2.f);
  for (float& v : k) v /= sum;
  std::vector<float> tmp(known.size());
  for (int y = 0; y < h; ++y)
    for (int x = 0; x < w; ++x) {
      float v = 0;
      for (int i = 0; i < 5; ++i) v += k[i] * known[size_t(y) * w + reflect101(x + i - 2, w)];
      tmp[size_t(y) * w + x] = v;
    }
  std::vector<uint8_t> out(known.size());
  for (int y = 0; y < h; ++y)
    for (int x = 0; x < w; ++x) {
      float v = 0;
      for (int i = 0; i < 5; ++i) v += k[i] * tmp[size_t(reflect101(y + i - 2, h)) * w + x];
      out[size_t(y) * w + x] = uint8_t(std::lround(std::clamp(v, 0.f, 1.f) * 255.f));
    }
  return out;
}

// The detector's mask is a 256 px grid, upsampled and grown: around a thin scratch it covers
// whole cells of good photo, which the fill would replace with a smooth guess (S9 "old"
// category: 3x the damage was filled, and every no-reference metric fell). Inside it, only
// pixels that stand out from the median of their neighbourhood (the scratch itself, bright or
// dark) stay holes, grown by a pixel or two for the fill's blend.
void refine_mask(Mask8& m, const Rgb8& img) {
  const int r = std::max(3, std::min(img.w, img.h) / kScratchShortSide * 3 / 2);
  const int step = std::max(1, r / 3);  // at most 7 x 7 samples
  constexpr int kOutlier = 16;          // grey levels: above film grain
  std::vector<uint8_t> grey(size_t(img.w) * img.h);
  for (int y = 0; y < img.h; ++y)
    for (int x = 0; x < img.w; ++x) {
      const uint8_t* p = img.row(y) + x * 3;
      grey[size_t(y) * img.w + x] =
          uint8_t((p[0] * 19595 + p[1] * 38470 + p[2] * 7471 + 0x8000) >> 16);
    }
  std::vector<uint8_t> keep(m.px.size(), 0), s;
  s.reserve(64);
  for (int y = 0; y < m.h; ++y)
    for (int x = 0; x < m.w; ++x) {
      if (!m.at(x, y)) continue;
      s.clear();
      for (int dy = -r; dy <= r; dy += step)
        for (int dx = -r; dx <= r; dx += step)
          s.push_back(grey[size_t(reflect101(y + dy, m.h)) * m.w + reflect101(x + dx, m.w)]);
      std::nth_element(s.begin(), s.begin() + s.size() / 2, s.end());
      const int v = grey[size_t(y) * m.w + x];
      if (std::abs(v - s[s.size() / 2]) > kOutlier) keep[size_t(y) * m.w + x] = 255;
    }
  m.px.swap(keep);
  dilate(m, 1 + std::min(m.w, m.h) / 1500);
}

}  // namespace

size_t Mask8::count() const { return size_t(std::count(px.begin(), px.end(), uint8_t(255))); }

void scratch_input_size(int w, int h, int& nw, int& nh) {
  const double s = double(kScratchShortSide) / std::min(w, h);
  auto round16 = [](double v) {
    return std::max(kScratchMultiple, int(std::lround(v / kScratchMultiple)) * kScratchMultiple);
  };
  nw = round16(w * s);
  nh = round16(h * s);
}

Mask8 detect_scratches(InferenceBackend& be, const Rgb8& img, float threshold, int grow) {
  int nw = 0, nh = 0;
  scratch_input_size(img.w, img.h, nw, nh);
  const Rgb8 small =
      nw <= img.w && nh <= img.h ? resize_area(img, nw, nh) : resize_bilinear(img, nw, nh);
  ncnn::Mat in(nw, nh, 1);
  for (int y = 0; y < nh; ++y) {
    const uint8_t* p = small.row(y);
    float* d = in.channel(0).row(y);
    for (int x = 0; x < nw; ++x)  // PIL "L": ITU-R 601-2 luma, 16-bit fixed point
      d[x] = float((p[x * 3] * 19595 + p[x * 3 + 1] * 38470 + p[x * 3 + 2] * 7471 + 0x8000) >> 16) *
             (1.f / 255.f);
  }
  ncnn::Mat out;
  be.run(in, out);
  if (out.w != nw || out.h != nh || out.c != 1)
    fail(ENH_E_BACKEND, "scratch detection: unexpected output shape");
  Mask8 m;
  m.w = img.w;
  m.h = img.h;
  m.px.resize(size_t(img.w) * img.h);
  for (int y = 0; y < img.h; ++y) {
    const float* r = out.channel(0).row(int(int64_t(y) * nh / img.h));
    for (int x = 0; x < img.w; ++x)
      m.px[size_t(y) * img.w + x] = r[int64_t(x) * nw / img.w] >= threshold ? 255 : 0;
  }
  dilate(m, grow);
  refine_mask(m, img);
  return m;
}

Rgb8 inpaint(InferenceBackend& be, const Rgb8& img, const Mask8& mask,
             const std::function<bool(int, int)>& tick) {
  if (mask.w != img.w || mask.h != img.h) fail(ENH_E_INVALID, "inpaint: mask size");
  Rgb8 out = img;
  if (!mask.count()) return out;
  const std::vector<uint8_t> keep = blend_weight(mask);
  constexpr int S = kInpaintSize;
  const Geometry g = Geometry::make(img.w, img.h, S - 2 * kInpaintPad, kInpaintPad, 1, 1);
  const int P = g.pad;

  // Tiles whose owned part has a pixel to change.
  struct Tile {
    int x0, y0, ox0, ox1, oy0, oy1;
  };
  std::vector<Tile> tiles;
  for (int b = 0; b < g.bands(); ++b)
    for (int j = 0; j < g.tiles_per_band(); ++j) {
      Tile t{g.xs[size_t(j)],
             g.ys[size_t(b)],
             owned_start(g.xs, j, g.tw),
             j + 1 < g.tiles_per_band() ? owned_start(g.xs, j + 1, g.tw) : g.in_w,
             g.band_in_y0(b),
             g.band_in_y1(b)};
      bool need = false;
      for (int y = t.oy0; y < t.oy1 && !need; ++y)
        for (int x = t.ox0; x < t.ox1 && !need; ++x) need = keep[size_t(y) * img.w + x] < 255;
      if (need) tiles.push_back(t);
    }

  std::vector<int> colidx(S);
  int done = 0;
  for (const Tile& t : tiles) {
    // [known - 0.5, image * known], the image in [-1, 1] (upstream preprocess).
    ncnn::Mat in(S, S, 4);
    for (int xx = 0; xx < S; ++xx) colidx[size_t(xx)] = reflect101(t.x0 - P + xx, img.w);
    for (int yy = 0; yy < S; ++yy) {
      const int sy = reflect101(t.y0 - P + yy, img.h);
      const uint8_t* row = img.row(sy);
      float* m = in.channel(0).row(yy);
      float* r = in.channel(1).row(yy);
      float* gr = in.channel(2).row(yy);
      float* bl = in.channel(3).row(yy);
      for (int xx = 0; xx < S; ++xx) {
        const int sx = colidx[size_t(xx)];
        const float k = mask.at(sx, sy) ? 0.f : 1.f;
        const uint8_t* p = row + sx * 3;
        m[xx] = k - 0.5f;
        r[xx] = (p[0] * (2.f / 255.f) - 1.f) * k;
        gr[xx] = (p[1] * (2.f / 255.f) - 1.f) * k;
        bl[xx] = (p[2] * (2.f / 255.f) - 1.f) * k;
      }
    }
    ncnn::Mat o;
    be.run(in, o);
    if (o.w != S || o.h != S || o.c != 3) fail(ENH_E_BACKEND, "inpaint: unexpected output shape");
    for (int y = t.oy0; y < t.oy1; ++y) {
      const int yy = y - t.y0 + P;
      uint8_t* dst = out.row(y);
      const uint8_t* src = img.row(y);
      for (int x = t.ox0; x < t.ox1; ++x) {
        const int kw = keep[size_t(y) * img.w + x];
        if (kw == 255) continue;
        const int xx = x - t.x0 + P;
        const float a = kw * (1.f / 255.f);
        for (int c = 0; c < 3; ++c) {
          const float fill = std::clamp(o.channel(c).row(yy)[xx] * 0.5f + 0.5f, 0.f, 1.f) * 255.f;
          dst[x * 3 + c] = uint8_t(std::lround(src[x * 3 + c] * a + fill * (1 - a)));
        }
      }
    }
    ++done;
    if (tick && !tick(done, int(tiles.size()))) fail(ENH_E_CANCELLED, "inpaint stopped");
  }
  return out;
}

}  // namespace enh
