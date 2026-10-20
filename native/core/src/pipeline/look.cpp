// SPDX-License-Identifier: Apache-2.0
#include "pipeline/look.hpp"

#include <algorithm>
#include <cmath>

#include "enh.h"
#include "util/error.hpp"
#include "util/size.hpp"

namespace enh {

static_assert(kLeaksSide == ENH_LOOK_LEAKS_SIDE);

namespace {

// A preset in [0, 1] terms: x -> post * contrast(saturation(pre * x)) + offset, contrast about
// mid-grey. Kept as parameters rather than finished matrices so each one reads as what it does.
struct Preset {
  const char* id;
  float pre[3];
  float saturation;
  float contrast;
  float post[3];
  float offset[3];
};

constexpr Preset kPresets[] = {
    {"none", {1, 1, 1}, 1, 1, {1, 1, 1}, {0, 0, 0}},
    // Soft pink with lifted shadows and lower contrast.
    {"pastel", {1, 0.97f, 1}, 0.8f, 0.82f, {1, 1, 1}, {0.04f, 0, 0.03f}},
};

// Rec. 709 luma of the encoded values, as saturation matrices usually take it.
constexpr float kLuma[3] = {0.2126f, 0.7152f, 0.0722f};

const Preset* find(const std::string& id) {
  for (const auto& p : kPresets)
    if (id == p.id) return &p;
  return nullptr;
}

// Soft glows near the frame's edges: centre (fractions of width and height, may lie outside),
// radius (fraction of the longer side), colour, opacity.
struct Glow {
  float cx, cy, r;
  float rgb[3];
  float a;
};

constexpr Glow kGlows[] = {
    {-0.05f, 0.3f, 0.4f, {255, 120, 40}, 0.55f},
    {0.02f, 0.9f, 0.3f, {255, 90, 140}, 0.45f},
    {1.02f, 0.05f, 0.22f, {255, 170, 90}, 0.3f},
};

}  // namespace

bool look_known(const std::string& id) { return find(id) != nullptr; }

LookMatrix look_matrix(const std::string& id, float amount) {
  const Preset* p = find(id);
  if (!p) fail(ENH_E_INVALID, "unknown look");
  if (!(amount >= 0 && amount <= 1)) fail(ENH_E_INVALID, "look amount must be 0..1");
  // A = diag(post) * contrast * S * diag(pre); b = post * (1 - contrast) / 2 + offset.
  float a[3][3], b[3];
  for (int r = 0; r < 3; ++r) {
    for (int c = 0; c < 3; ++c) {
      const float s = p->saturation * (r == c ? 1.f : 0.f) + (1 - p->saturation) * kLuma[c];
      a[r][c] = p->post[r] * p->contrast * s * p->pre[c];
    }
    b[r] = p->post[r] * (1 - p->contrast) * 0.5f + p->offset[r];
  }
  LookMatrix m{};
  for (int r = 0; r < 3; ++r) {
    for (int c = 0; c < 3; ++c) {
      const float id_rc = r == c ? 1.f : 0.f;
      m[sz(r) * 5 + sz(c)] = id_rc + amount * (a[r][c] - id_rc);
    }
    m[sz(r) * 5 + 4] = amount * b[r] * 255;
  }
  m[18] = 1;  // alpha unchanged
  return m;
}

void apply_look(const LookMatrix& m, uint8_t* rgb, size_t pixels) {
  for (size_t i = 0; i < pixels; ++i, rgb += 3) {
    const float r = rgb[0], g = rgb[1], b = rgb[2];
    for (int c = 0; c < 3; ++c) {
      const float* row = m.data() + size_t(c) * 5;
      // Alpha is 255 (column 3): opaque results only.
      const float v = row[0] * r + row[1] * g + row[2] * b + row[3] * 255 + row[4];
      rgb[c] = uint8_t(std::clamp(std::lround(v), 0L, 255L));
    }
  }
}

Rgb8 leak_grid(int w, int h) {
  if (w <= 0 || h <= 0) fail(ENH_E_INVALID, "bad size");
  Rgb8 g;
  const double longer = std::max(w, h);
  g.w = std::max(1, int(std::lround(kLeaksSide * w / longer)));
  g.h = std::max(1, int(std::lround(kLeaksSide * h / longer)));
  g.px.resize(sz(g.w) * sz(g.h) * 3);
  // Distances in units of the longer side, so the glows stay round on any aspect.
  const float longer_g = float(std::max(g.w, g.h));
  const float ax = float(g.w) / longer_g, ay = float(g.h) / longer_g;
  for (int y = 0; y < g.h; ++y) {
    for (int x = 0; x < g.w; ++x) {
      const float u = (float(x) + 0.5f) / float(g.w), v = (float(y) + 0.5f) / float(g.h);
      float keep[3] = {1, 1, 1};  // screen of all glows: 1 - prod(1 - glow)
      for (const auto& gl : kGlows) {
        const float dx = (u - gl.cx) * ax, dy = (v - gl.cy) * ay;
        const float k = gl.a * std::exp(-(dx * dx + dy * dy) / (2 * gl.r * gl.r));
        for (int c = 0; c < 3; ++c) keep[c] *= 1 - k * gl.rgb[c] / 255;
      }
      uint8_t* o = g.row(y) + sz(x) * 3;
      for (int c = 0; c < 3; ++c) o[c] = uint8_t(std::lround((1 - keep[c]) * 255));
    }
  }
  return g;
}

LeakOverlay::LeakOverlay(int w, int h) : w_(w), h_(h), grid_(leak_grid(w, h)) {
  x0_.resize(sz(w));
  fx_.resize(sz(w));
  for (int x = 0; x < w; ++x) {
    const float sx =
        std::clamp((float(x) + 0.5f) * float(grid_.w) / float(w) - 0.5f, 0.f, float(grid_.w - 1));
    x0_[sz(x)] = std::min(int(sx), grid_.w - 1);
    fx_[sz(x)] = sx - float(x0_[sz(x)]);
  }
}

void LeakOverlay::blend_rows(int y0, int rows, uint8_t* rgb) {
  for (int r = 0; r < rows; ++r) {
    const float sy = std::clamp((float(y0 + r) + 0.5f) * float(grid_.h) / float(h_) - 0.5f, 0.f,
                                float(grid_.h - 1));
    const int gy0 = std::min(int(sy), grid_.h - 1), gy1 = std::min(gy0 + 1, grid_.h - 1);
    const float fy = sy - float(gy0);
    const uint8_t *a = grid_.row(gy0), *b = grid_.row(gy1);
    uint8_t* out = rgb + sz(r) * sz(w_) * 3;
    for (int x = 0; x < w_; ++x) {
      const int gx0 = x0_[sz(x)], gx1 = std::min(gx0 + 1, grid_.w - 1);
      const float fx = fx_[sz(x)];
      for (int c = 0; c < 3; ++c) {
        const float top = a[gx0 * 3 + c] + fx * (a[gx1 * 3 + c] - a[gx0 * 3 + c]);
        const float bot = b[gx0 * 3 + c] + fx * (b[gx1 * 3 + c] - b[gx0 * 3 + c]);
        const float l = top + fy * (bot - top);
        const float p = out[x * 3 + c];
        out[x * 3 + c] = uint8_t(std::lround(p + l - p * l / 255));  // screen
      }
    }
  }
}

}  // namespace enh
