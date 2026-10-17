// SPDX-License-Identifier: Apache-2.0
#include "pipeline/lowlight.hpp"

#include <mat.h>

#include <algorithm>
#include <cmath>
#include <vector>

#include "image/ops.hpp"
#include "pipeline/geometry.hpp"
#include "util/error.hpp"

namespace enh {

namespace {

constexpr float kPi = 3.14159265358979323846f;
constexpr float kEps = 1e-8f;

float sensitivity(float v, float k) { return std::pow(std::sin(v * 0.5f * kPi) + kEps, k); }

}  // namespace

Hvi hvi_of_rgb(float r, float g, float b, float k) {
  const float v = std::max({r, g, b}), mn = std::min({r, g, b});
  float hue = 0;
  if (mn != v) {
    // Upstream assigns blue, then green, then red: red wins a tie, then green.
    if (r == v) {
      hue = std::fmod((g - b) / (v - mn + kEps), 6.f);
      if (hue < 0) hue += 6.f;  // torch's % takes the divisor's sign
    } else if (g == v) {
      hue = 2.f + (b - r) / (v - mn + kEps);
    } else {
      hue = 4.f + (r - g) / (v - mn + kEps);
    }
  }
  hue /= 6.f;
  const float s = v == 0 ? 0.f : (v - mn) / (v + kEps);
  const float cs = sensitivity(v, k);
  return {cs * s * std::cos(2 * kPi * hue), cs * s * std::sin(2 * kPi * hue), v};
}

void rgb_of_hvi(Hvi x, float k, float& r, float& g, float& b) {
  float H = std::clamp(x.h, -1.f, 1.f), V = std::clamp(x.v, -1.f, 1.f);
  const float v = std::clamp(x.i, 0.f, 1.f);
  const float cs = sensitivity(v, k);
  H = std::clamp(H / (cs + kEps), -1.f, 1.f);
  V = std::clamp(V / (cs + kEps), -1.f, 1.f);
  float h = std::atan2(V + kEps, H + kEps) / (2 * kPi);
  h -= std::floor(h);
  const float s = std::clamp(std::sqrt(H * H + V * V + kEps), 0.f, 1.f);
  const float h6 = h * 6.f;
  const int hi = int(std::floor(h6)) % 6;
  const float f = h6 - std::floor(h6);
  const float p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s);
  switch (hi) {
    case 0:
      r = v, g = t, b = p;
      break;
    case 1:
      r = q, g = v, b = p;
      break;
    case 2:
      r = p, g = v, b = t;
      break;
    case 3:
      r = p, g = q, b = v;
      break;
    case 4:
      r = t, g = p, b = v;
      break;
    default:
      r = v, g = p, b = q;
      break;
  }
}

Rgb8 enhance_low_light(InferenceBackend& be, const Rgb8& img, float k, int max_side) {
  // The downscale the network sees (never up), and its input padded to a multiple of 8.
  const double sc = std::min(1.0, double(max_side) / std::max(img.w, img.h));
  const int sw = std::max(1, int(std::lround(img.w * sc))),
            sh = std::max(1, int(std::lround(img.h * sc)));
  const Rgb8 small = sw == img.w && sh == img.h ? img : resize_area(img, sw, sh);
  auto up8 = [](int n) {
    return (n + kLowLightMultiple - 1) / kLowLightMultiple * kLowLightMultiple;
  };
  const int nw = up8(sw), nh = up8(sh);
  ncnn::Mat in(nw, nh, 3);
  for (int y = 0; y < nh; ++y) {
    const uint8_t* row = small.row(reflect101(y, sh));
    for (int x = 0; x < nw; ++x) {
      const uint8_t* p = row + reflect101(x, sw) * 3;
      const Hvi c = hvi_of_rgb(p[0] / 255.f, p[1] / 255.f, p[2] / 255.f, k);
      in.channel(0).row(y)[x] = c.h;
      in.channel(1).row(y)[x] = c.v;
      in.channel(2).row(y)[x] = c.i;
    }
  }
  ncnn::Mat out;
  be.run(in, out);
  if (out.w != nw || out.h != nh || out.c != 3)
    fail(ENH_E_BACKEND, "low light: unexpected output shape");
  // The correction on the downscale.
  std::vector<float> d(size_t(sw) * sh * 3);
  for (int c = 0; c < 3; ++c)
    for (int y = 0; y < sh; ++y)
      for (int x = 0; x < sw; ++x)
        d[(size_t(y) * sw + x) * 3 + c] = out.channel(c).row(y)[x] - in.channel(c).row(y)[x];

  Rgb8 res;
  res.w = img.w;
  res.h = img.h;
  res.px.resize(img.px.size());
  auto u8 = [](float v) { return uint8_t(std::lround(std::clamp(v, 0.f, 1.f) * 255.f)); };
  for (int y = 0; y < img.h; ++y) {
    // Bilinear, pixel centres aligned (align_corners=False), edges clamped.
    const float fy = std::clamp((y + 0.5f) * sh / img.h - 0.5f, 0.f, float(sh - 1));
    const int y0 = int(fy), y1 = std::min(y0 + 1, sh - 1);
    const float ay = fy - y0;
    const uint8_t* src = img.row(y);
    uint8_t* dst = res.row(y);
    for (int x = 0; x < img.w; ++x) {
      const float fx = std::clamp((x + 0.5f) * sw / img.w - 0.5f, 0.f, float(sw - 1));
      const int x0 = int(fx), x1 = std::min(x0 + 1, sw - 1);
      const float ax = fx - x0;
      float delta[3];
      for (int c = 0; c < 3; ++c) {
        auto at = [&](int yy, int xx) { return d[(size_t(yy) * sw + xx) * 3 + c]; };
        delta[c] = (at(y0, x0) * (1 - ax) + at(y0, x1) * ax) * (1 - ay) +
                   (at(y1, x0) * (1 - ax) + at(y1, x1) * ax) * ay;
      }
      Hvi c = hvi_of_rgb(src[x * 3] / 255.f, src[x * 3 + 1] / 255.f, src[x * 3 + 2] / 255.f, k);
      c.h += delta[0];
      c.v += delta[1];
      c.i += delta[2];
      float r, g, b;
      rgb_of_hvi(c, k, r, g, b);
      dst[x * 3] = u8(r);
      dst[x * 3 + 1] = u8(g);
      dst[x * 3 + 2] = u8(b);
    }
  }
  return res;
}

}  // namespace enh
