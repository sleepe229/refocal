// SPDX-License-Identifier: Apache-2.0
#include "image/ops.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <utility>
#include <vector>

#include "util/error.hpp"
#include "util/size.hpp"

namespace enh {

Rgb8 crop(const Rgb8& src, int x, int y, int w, int h) {
  Rgb8 out;
  out.w = w;
  out.h = h;
  out.px.resize(sz(w) * sz(h) * 3);
  for (int r = 0; r < h; ++r)
    std::memcpy(&out.px[sz(r) * sz(w) * 3], src.row(y + r) + sz(x) * 3, sz(w) * 3);
  return out;
}

Rgb8 apply_orientation(Rgb8 src, int o) {
  if (o <= 1 || o > 8) return src;
  const bool swap = o >= 5;  // 5..8 transpose width/height
  Rgb8 dst;
  dst.w = swap ? src.h : src.w;
  dst.h = swap ? src.w : src.h;
  dst.px.resize(src.px.size());
  const int W = src.w, H = src.h;
  for (int y = 0; y < H; ++y) {
    const uint8_t* s = src.row(y);
    for (int x = 0; x < W; ++x) {
      int dx, dy;
      switch (o) {
        case 2:
          dx = W - 1 - x;
          dy = y;
          break;  // mirror horizontal
        case 3:
          dx = W - 1 - x;
          dy = H - 1 - y;
          break;  // rotate 180
        case 4:
          dx = x;
          dy = H - 1 - y;
          break;  // mirror vertical
        case 5:
          dx = y;
          dy = x;
          break;  // transpose
        case 6:
          dx = H - 1 - y;
          dy = x;
          break;  // rotate 90 CW
        case 7:
          dx = H - 1 - y;
          dy = W - 1 - x;
          break;  // transverse
        default:
          dx = y;
          dy = W - 1 - x;
          break;  // 8: rotate 270 CW
      }
      std::memcpy(dst.row(dy) + sz(dx) * 3, s + sz(x) * 3, 3);
    }
  }
  return dst;
}

void area_down(const uint8_t* src, int w, int rows, int f, uint8_t* dst) {
  const int ow = w / f, oh = rows / f, n = f * f;
  std::vector<uint32_t> acc(sz(ow) * 3);
  for (int y = 0; y < oh; ++y) {
    std::fill(acc.begin(), acc.end(), 0);
    for (int k = 0; k < f; ++k) {
      const uint8_t* r = src + sz(y * f + k) * sz(w) * 3;
      for (int x = 0; x < ow; ++x) {
        const uint8_t* p = r + sz(x) * sz(f) * 3;
        uint32_t* a = &acc[sz(x) * 3];
        for (size_t i = 0; i < sz(f); ++i) {
          a[0] += p[i * 3];
          a[1] += p[i * 3 + 1];
          a[2] += p[i * 3 + 2];
        }
      }
    }
    uint8_t* d = dst + sz(y) * sz(ow) * 3;
    for (size_t i = 0; i < sz(ow) * 3; ++i)
      d[i] = uint8_t((acc[i] + uint32_t(n / 2)) / uint32_t(n));
  }
}

Rgb8 area_down(const Rgb8& src, int f) {
  Rgb8 dst;
  dst.w = src.w / f;
  dst.h = src.h / f;
  dst.px.resize(sz(dst.w) * sz(dst.h) * 3);
  area_down(src.px.data(), src.w, dst.h * f, f, dst.px.data());
  return dst;
}

void PreviewAccumulator::init(int w, int h, int max_side) {
  w_ = w;
  h_ = h;
  int m = std::max(w, h);
  if (m <= max_side) {
    pw_ = w;
    ph_ = h;
  } else {
    pw_ = std::max(1, int(std::lround(double(w) * max_side / m)));
    ph_ = std::max(1, int(std::lround(double(h) * max_side / m)));
  }
  colmap_.resize(sz(w));
  colcount_.assign(sz(pw_), 0);
  rowcount_.assign(sz(ph_), 0);
  for (int x = 0; x < w; ++x) {
    const int c = int(int64_t(x) * pw_ / w);
    colmap_[sz(x)] = c;
    colcount_[sz(c)]++;
  }
  for (int y = 0; y < h; ++y) rowcount_[size_t(int64_t(y) * ph_ / h)]++;
  sum_.assign(sz(pw_) * sz(ph_) * 3, 0);
}

void PreviewAccumulator::add_rows(const uint8_t* rgb, int y0, int rows) {
  for (int i = 0; i < rows; ++i) {
    int py = int(int64_t(y0 + i) * ph_ / h_);
    uint32_t* s = sum_.data() + sz(py) * sz(pw_) * 3;
    const uint8_t* r = rgb + sz(i) * sz(w_) * 3;
    for (int x = 0; x < w_; ++x) {
      uint32_t* d = s + sz(colmap_[sz(x)]) * 3;
      const uint8_t* q = r + sz(x) * 3;
      d[0] += q[0];
      d[1] += q[1];
      d[2] += q[2];
    }
  }
}

Rgb8 PreviewAccumulator::finish() const {
  Rgb8 out;
  out.w = pw_;
  out.h = ph_;
  out.px.resize(sz(pw_) * sz(ph_) * 3);
  for (int y = 0; y < ph_; ++y)
    for (int x = 0; x < pw_; ++x) {
      uint32_t cnt = rowcount_[sz(y)] * colcount_[sz(x)];
      for (size_t c = 0; c < 3; ++c) {
        size_t i = (sz(y) * sz(pw_) + sz(x)) * 3 + c;
        out.px[i] = uint8_t(cnt ? (sum_[i] + cnt / 2) / cnt : 0);
      }
    }
  return out;
}

// ---- Lanczos-3 ----

namespace {
float lanczos3(float x) {
  x = std::fabs(x);
  if (x < 1e-6f) return 1.f;
  if (x >= 3.f) return 0.f;
  const float px = float(M_PI) * x;
  return 3.f * std::sin(px) * std::sin(px / 3.f) / (px * px);
}
}  // namespace

LanczosResampler::Axis LanczosResampler::make_axis(int in, int out) {
  Axis a;
  const double ratio = double(in) / out;
  const double scale = ratio > 1 ? ratio : 1;  // widen the kernel when downscaling
  const double support = 3 * scale;
  a.taps = int(std::ceil(support)) * 2 + 1;
  a.idx.resize(sz(out) * sz(a.taps));
  a.w.resize(sz(out) * sz(a.taps));
  for (int o = 0; o < out; ++o) {
    const size_t row = sz(o) * sz(a.taps);
    const double c = (o + 0.5) * ratio - 0.5;
    const int first = int(std::floor(c - support)) + 1;
    double sum = 0;
    for (int t = 0; t < a.taps; ++t) {
      const int j = first + t;
      const float wt = lanczos3(float((j - c) / scale));
      a.idx[row + sz(t)] = j < 0 ? 0 : (j >= in ? in - 1 : j);
      a.w[row + sz(t)] = wt;
      sum += wt;
    }
    for (int t = 0; t < a.taps; ++t) a.w[row + sz(t)] = float(a.w[row + sz(t)] / sum);
  }
  return a;
}

LanczosResampler::LanczosResampler(const Rgb8& src, int out_w, int out_h)
    : src_(src), out_w_(out_w), out_h_(out_h) {
  if (src.w == out_w && src.h == out_h) return;
  ax_ = make_axis(src.w, out_w);
  ay_ = make_axis(src.h, out_h);
  // A window of ay_.taps consecutive source rows never collides in a ring of that size.
  ring_.assign(sz(ay_.taps), std::vector<float>(sz(out_w) * 3));
  ring_y_.assign(sz(ay_.taps), -1);
}

const float* LanczosResampler::hrow(int sy) {
  const size_t slot = sz(sy) % ring_.size();
  std::vector<float>& r = ring_[slot];
  if (ring_y_[slot] != sy) {
    const uint8_t* s = src_.row(sy);
    const int T = ax_.taps;
    for (int x = 0; x < out_w_; ++x) {
      const int* ix = &ax_.idx[sz(x) * sz(T)];
      const float* wx = &ax_.w[sz(x) * sz(T)];
      float a = 0, b = 0, c = 0;
      for (int t = 0; t < T; ++t) {
        const uint8_t* p = s + sz(ix[t]) * 3;
        a += wx[t] * p[0];
        b += wx[t] * p[1];
        c += wx[t] * p[2];
      }
      r[sz(x) * 3] = a;
      r[sz(x) * 3 + 1] = b;
      r[sz(x) * 3 + 2] = c;
    }
    ring_y_[slot] = sy;
  }
  return r.data();
}

void LanczosResampler::rows(int y0, int rows, uint8_t* dst) {
  const size_t stride = sz(out_w_) * 3;
  if (ring_.empty()) {  // same size
    std::memcpy(dst, src_.row(y0), stride * sz(rows));
    return;
  }
  const int T = ay_.taps;
  std::vector<float> acc(stride);
  for (int r = 0; r < rows; ++r) {
    const int y = y0 + r;
    const int* iy = &ay_.idx[sz(y) * sz(T)];
    const float* wy = &ay_.w[sz(y) * sz(T)];
    std::fill(acc.begin(), acc.end(), 0.f);
    for (int t = 0; t < T; ++t) {
      const float* h = hrow(iy[t]);  // the T-row window fits the ring: no eviction here
      const float k = wy[t];
      for (size_t i = 0; i < stride; ++i) acc[i] += k * h[i];
    }
    uint8_t* d = dst + sz(r) * stride;
    for (size_t i = 0; i < stride; ++i) {
      const float v = acc[i] < 0.f ? 0.f : (acc[i] > 255.f ? 255.f : acc[i]);
      d[i] = uint8_t(v + 0.5f);
    }
  }
}

void blend(const uint8_t* base, const uint8_t* sr, size_t n, float strength, uint8_t* out) {
  const int s = int(strength * 256.f + 0.5f), k = 256 - s;
  for (size_t i = 0; i < n; ++i) out[i] = uint8_t((sr[i] * s + base[i] * k + 128) >> 8);
}

namespace {

// Output pixel i of n over a source of m pixels: contributions (source index, weight).
std::vector<std::vector<std::pair<int, float>>> area_weights(int m, int n) {
  std::vector<std::vector<std::pair<int, float>>> w(sz(n));
  const double s = double(m) / n;
  for (int i = 0; i < n; ++i) {
    const double a = i * s, b = (i + 1) * s;
    for (int k = int(a); k < m && k < b; ++k) {
      const double cov = std::min(b, k + 1.0) - std::max(a, double(k));
      if (cov > 0) w[sz(i)].push_back({k, float(cov / s)});
    }
  }
  return w;
}

}  // namespace

Rgb8 resize_area(const Rgb8& src, int w, int h) {
  if (w <= 0 || h <= 0 || w > src.w || h > src.h) fail(ENH_E_INTERNAL, "resize_area: bad size");
  const auto wx = area_weights(src.w, w), wy = area_weights(src.h, h);
  std::vector<float> rows(sz(w) * sz(src.h) * 3, 0.f);  // horizontal pass
  for (int y = 0; y < src.h; ++y) {
    const uint8_t* s = src.row(y);
    float* d = rows.data() + sz(y) * sz(w) * 3;
    for (int x = 0; x < w; ++x) {
      for (const auto& [k, wt] : wx[sz(x)]) {
        for (int c = 0; c < 3; ++c) d[3 * x + c] += wt * s[3 * k + c];
      }
    }
  }
  Rgb8 out;
  out.w = w;
  out.h = h;
  out.px.resize(sz(w) * sz(h) * 3);
  for (int y = 0; y < h; ++y) {
    uint8_t* o = out.row(y);
    for (int x = 0; x < w * 3; ++x) {
      float v = 0;
      for (const auto& [k, wt] : wy[sz(y)]) v += wt * rows[sz(k) * sz(w) * 3 + sz(x)];
      o[x] = uint8_t(std::clamp(v + 0.5f, 0.f, 255.f));
    }
  }
  return out;
}

}  // namespace enh
