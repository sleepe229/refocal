// SPDX-License-Identifier: Apache-2.0
#include "image/ops.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace enh {

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
        case 2: dx = W - 1 - x; dy = y; break;              // mirror horizontal
        case 3: dx = W - 1 - x; dy = H - 1 - y; break;      // rotate 180
        case 4: dx = x; dy = H - 1 - y; break;              // mirror vertical
        case 5: dx = y; dy = x; break;                      // transpose
        case 6: dx = H - 1 - y; dy = x; break;              // rotate 90 CW
        case 7: dx = H - 1 - y; dy = W - 1 - x; break;      // transverse
        default: dx = y; dy = W - 1 - x; break;             // 8: rotate 270 CW
      }
      std::memcpy(dst.row(dy) + size_t(dx) * 3, s + size_t(x) * 3, 3);
    }
  }
  return dst;
}

void area_down(const uint8_t* src, int w, int rows, int f, uint8_t* dst) {
  const int ow = w / f, oh = rows / f, n = f * f;
  std::vector<uint32_t> acc(size_t(ow) * 3);
  for (int y = 0; y < oh; ++y) {
    std::fill(acc.begin(), acc.end(), 0);
    for (int k = 0; k < f; ++k) {
      const uint8_t* r = src + size_t(y * f + k) * w * 3;
      for (int x = 0; x < ow; ++x) {
        const uint8_t* p = r + size_t(x) * f * 3;
        for (int i = 0; i < f; ++i) {
          acc[x * 3] += p[i * 3];
          acc[x * 3 + 1] += p[i * 3 + 1];
          acc[x * 3 + 2] += p[i * 3 + 2];
        }
      }
    }
    uint8_t* d = dst + size_t(y) * ow * 3;
    for (int i = 0; i < ow * 3; ++i) d[i] = uint8_t((acc[i] + uint32_t(n / 2)) / uint32_t(n));
  }
}

Rgb8 area_down(const Rgb8& src, int f) {
  Rgb8 dst;
  dst.w = src.w / f;
  dst.h = src.h / f;
  dst.px.resize(size_t(dst.w) * dst.h * 3);
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
  colmap_.resize(size_t(w));
  colcount_.assign(size_t(pw_), 0);
  rowcount_.assign(size_t(ph_), 0);
  for (int x = 0; x < w; ++x) {
    colmap_[x] = int(int64_t(x) * pw_ / w);
    colcount_[colmap_[x]]++;
  }
  for (int y = 0; y < h; ++y) rowcount_[size_t(int64_t(y) * ph_ / h)]++;
  sum_.assign(size_t(pw_) * ph_ * 3, 0);
}

void PreviewAccumulator::add_rows(const uint8_t* rgb, int y0, int rows) {
  for (int i = 0; i < rows; ++i) {
    int py = int(int64_t(y0 + i) * ph_ / h_);
    uint32_t* s = sum_.data() + size_t(py) * pw_ * 3;
    const uint8_t* r = rgb + size_t(i) * w_ * 3;
    for (int x = 0; x < w_; ++x) {
      uint32_t* d = s + colmap_[x] * 3;
      d[0] += r[x * 3];
      d[1] += r[x * 3 + 1];
      d[2] += r[x * 3 + 2];
    }
  }
}

Rgb8 PreviewAccumulator::finish() const {
  Rgb8 out;
  out.w = pw_;
  out.h = ph_;
  out.px.resize(size_t(pw_) * ph_ * 3);
  for (int y = 0; y < ph_; ++y)
    for (int x = 0; x < pw_; ++x) {
      uint32_t cnt = rowcount_[y] * colcount_[x];
      for (int c = 0; c < 3; ++c) {
        size_t i = (size_t(y) * pw_ + x) * 3 + c;
        out.px[i] = uint8_t(cnt ? (sum_[i] + cnt / 2) / cnt : 0);
      }
    }
  return out;
}

}  // namespace enh
