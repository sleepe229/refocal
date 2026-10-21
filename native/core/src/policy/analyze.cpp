// SPDX-License-Identifier: Apache-2.0
#include "policy/analyze.hpp"

#include <algorithm>
#include <cmath>
#include <mutex>
#include <utility>
#include <vector>

#include "backend/backend.hpp"
#include "image/decode.hpp"
#include "image/ops.hpp"
#include "job/session.hpp"
#include "pipeline/faces.hpp"
#include "pipeline/geometry.hpp"
#include "util/fs.hpp"
#include "util/size.hpp"

namespace enh {

double estimate_noise(const Rgb8& img) {
  if (img.w < 3 || img.h < 3) return 0;
  std::vector<float> y(sz(img.w) * sz(img.h));
  for (int r = 0; r < img.h; ++r) {
    const uint8_t* p = img.row(r);
    for (int c = 0; c < img.w; ++c, p += 3) {
      y[sz(r) * sz(img.w) + sz(c)] =
          0.299f * float(p[0]) + 0.587f * float(p[1]) + 0.114f * float(p[2]);
    }
  }
  // M = [1 -2 1; -2 4 -2; 1 -2 1]: zero on locally linear image content.
  double sum = 0;
  for (int r = 1; r + 1 < img.h; ++r) {
    const float* a = &y[sz(r - 1) * sz(img.w)];
    const float* b = &y[sz(r) * sz(img.w)];
    const float* d = &y[sz(r + 1) * sz(img.w)];
    for (int c = 1; c + 1 < img.w; ++c) {
      const double v = a[c - 1] - 2 * a[c] + a[c + 1] - 2 * (b[c - 1] - 2 * b[c] + b[c + 1]) +
                       d[c - 1] - 2 * d[c] + d[c + 1];
      sum += std::abs(v);
    }
  }
  return sum * std::sqrt(M_PI / 2) / (6.0 * (img.w - 2) * (img.h - 2));
}

// ---- effective resolution (ADR-0025) ----
// An edge blurred over b px has |grad| / local range ~ 1/b; an area downscale by f narrows it to max(b f, ~1) px, so
// the steepness rises as f falls and levels off once the edge is about 1 px wide. tau was fitted
// against the downscale that gives the best SR result (LPIPS) on Kodak with known blurs.

namespace {

constexpr double kEffFactors[] = {1.0, 0.7, 0.5, 0.35, 0.25};
constexpr int kEffLevels = 5;
constexpr int kEffTile = 256;          // tiles of the full-resolution photo
constexpr int kEffTiles = 16;          // at most, the ones of most contrast (~1 MP)
constexpr float kEffMinRange = 0.06f;  // local contrast an edge needs (luma 0..1)
constexpr double kEffEdgeFrac = 0.02;  // the strongest edges: top 2% by gradient
constexpr double kEffTauIso = 0.30, kEffTauDir = 0.32;

struct Plane {
  int w = 0, h = 0;
  std::vector<float> v;
  float at(int x, int y) const { return v[index2d(x, y, w)]; }
};

// Area resample of a plane to w x h (<= its size), fractional pixel coverage. In float, not
// resize_area: the tiles are measured before any rounding to 8 bits.
std::vector<std::vector<std::pair<int, float>>> area_taps(int m, int n) {
  std::vector<std::vector<std::pair<int, float>>> t(sz(n));
  const double s = double(m) / n;
  for (int i = 0; i < n; ++i) {
    const double a = i * s, b = (i + 1) * s;
    for (int k = int(a); k < m && k < b; ++k) {
      const double cov = std::min(b, k + 1.0) - std::max(a, double(k));
      if (cov > 1e-9) t[sz(i)].push_back({k, float(cov / s)});
    }
  }
  return t;
}

Plane area_resize(const Plane& p, int w, int h) {
  if (w == p.w && h == p.h) return p;
  const auto tx = area_taps(p.w, w), ty = area_taps(p.h, h);
  std::vector<float> rows(sz(w) * sz(p.h), 0.f);
  for (int y = 0; y < p.h; ++y)
    for (int x = 0; x < w; ++x) {
      float a = 0;
      for (const auto& [k, wt] : tx[sz(x)]) a += wt * p.at(k, y);
      rows[index2d(x, y, w)] = a;
    }
  Plane o;
  o.w = w;
  o.h = h;
  o.v.assign(sz(w) * sz(h), 0.f);
  for (int y = 0; y < h; ++y)
    for (const auto& [k, wt] : ty[sz(y)])
      for (int x = 0; x < w; ++x) o.v[index2d(x, y, w)] += wt * rows[index2d(x, k, w)];
  return o;
}

// Edge samples of one plane: |grad| (Sobel / 8), |grad| / range (5x5 max - min), and the
// orientation bin (0, 45, 90, 135 degrees) of every pixel whose range exceeds kEffMinRange.
struct Edges {
  std::vector<float> g, ratio;
  std::vector<uint8_t> bin;
};

void collect_edges(const Plane& p, Edges& e) {
  const int w = p.w, h = p.h, W = w + 4;
  // The plane with a 2 px reflected border: the 5x5 window and the 3x3 Sobel index it directly.
  std::vector<float> q(sz(W) * sz(h + 4));
  for (int y = 0; y < h + 4; ++y) {
    const int sy = reflect_half(y - 2, h);
    for (int x = 0; x < W; ++x) q[index2d(x, y, W)] = p.at(reflect_half(x - 2, w), sy);
  }
  // 5x5 max/min, separably: rows first (padded height), then columns.
  std::vector<float> mx(sz(w) * sz(h + 4)), mn(sz(w) * sz(h + 4));
  for (int y = 0; y < h + 4; ++y) {
    const float* r = &q[index2d(0, y, W)];
    for (int x = 0; x < w; ++x) {
      const float* c = r + x;
      mx[index2d(x, y, w)] = std::max({c[0], c[1], c[2], c[3], c[4]});
      mn[index2d(x, y, w)] = std::min({c[0], c[1], c[2], c[3], c[4]});
    }
  }
  constexpr float kTan22 = 0.41421356f;
  for (int y = 0; y < h; ++y) {
    const float* a = &q[index2d(2, y + 1, W)];  // rows y - 1, y, y + 1 at x = 0
    const float* b = a + W;
    const float* c = b + W;
    for (int x = 0; x < w; ++x) {
      float hi = mx[index2d(x, y, w)], lo = mn[index2d(x, y, w)];
      for (int d = 1; d < 5; ++d) {
        hi = std::max(hi, mx[index2d(x, y + d, w)]);
        lo = std::min(lo, mn[index2d(x, y + d, w)]);
      }
      const float r = hi - lo;
      if (!(r > kEffMinRange)) continue;
      // Sobel: derivative [-1 0 1] along the axis, smoothing [1 2 1] across.
      const float gx =
          ((a[x + 1] - a[x - 1]) + 2 * (b[x + 1] - b[x - 1]) + (c[x + 1] - c[x - 1])) / 8.f;
      const float gy = ((c[x - 1] - a[x - 1]) + 2 * (c[x] - a[x]) + (c[x + 1] - a[x + 1])) / 8.f;
      const float g = std::sqrt(gx * gx + gy * gy), ax = std::fabs(gx), ay = std::fabs(gy);
      // atan2(gy, gx) mod pi in 45-degree bins centred on 0, 45, 90, 135.
      const uint8_t bin = ay <= kTan22 * ax ? 0 : ax <= kTan22 * ay ? 2 : (gx * gy > 0 ? 1 : 3);
      e.g.push_back(g);
      e.ratio.push_back(g / r);
      e.bin.push_back(bin);
    }
  }
}

// Median steepness over the top kEffEdgeFrac of the edges by gradient: [0] over all of them,
// [1 + b] over orientation bin b; NaN with fewer than 50 edges. Two histogram passes instead of
// sorting (the bin widths, 1/2730 of the gradient and 1/4096 of the steepness, are far below
// what moves the crossing).
struct Steepness {
  double all = 0, bins[4] = {};
};

Steepness steepness(const Edges& e) {
  constexpr int kBins = 4096;
  constexpr float kGMax = 1.5f;  // |Sobel| / 8 of a 0..1 plane is at most sqrt(2)
  std::vector<uint32_t> hg(size_t{5} * kBins, 0), hr(size_t{5} * kBins, 0);
  uint32_t n[5] = {};
  auto gbin = [&](float g) { return std::min(kBins - 1, int(g * (kBins / kGMax))); };
  for (size_t i = 0; i < e.g.size(); ++i) {
    const int k = gbin(e.g[i]), b = 1 + e.bin[i];
    ++hg[sz(k)];
    ++hg[sz(b * kBins + k)];
    ++n[0];
    ++n[b];
  }
  int thr[5];
  for (int s = 0; s < 5; ++s) {  // the bin holding the top kEffEdgeFrac
    const double want = kEffEdgeFrac * n[s];
    double above = 0;
    thr[s] = 0;
    for (int k = kBins - 1; k >= 0; --k) {
      above += hg[sz(s * kBins + k)];
      if (above >= want) {
        thr[s] = k;
        break;
      }
    }
  }
  uint32_t m[5] = {};
  for (size_t i = 0; i < e.g.size(); ++i) {
    const int k = gbin(e.g[i]), b = 1 + e.bin[i];
    const int r = std::min(kBins - 1, int(e.ratio[i] * kBins));
    if (k >= thr[0]) ++hr[sz(r)], ++m[0];
    if (k >= thr[b]) ++hr[sz(b * kBins + r)], ++m[b];
  }
  double med[5];
  for (int s = 0; s < 5; ++s) {
    med[s] = std::nan("");
    if (n[s] < 50) continue;
    uint32_t acc = 0;
    for (int r = 0; r < kBins; ++r) {
      acc += hr[sz(s * kBins + r)];
      if (2 * acc >= m[s]) {
        med[s] = (r + 0.5) / kBins;
        break;
      }
    }
  }
  return {med[0], {med[1], med[2], med[3], med[4]}};
}

// The largest factor whose steepness reaches tau, interpolated in log f; 1 without any edges.
double crossing(const double (&prof)[kEffLevels], double tau) {
  bool any = false;
  for (double v : prof) any = any || !std::isnan(v);
  if (!any) return 1.0;
  for (int i = 0; i < kEffLevels; ++i) {
    const double v = prof[i];
    if (std::isnan(v) || v < tau) continue;
    if (i == 0) return 1.0;
    const double f0 = kEffFactors[i - 1], v0 = prof[i - 1];
    const double t = (tau - v0) / std::max(v - v0, 1e-6);
    return std::exp(std::log(f0) + t * (std::log(kEffFactors[i]) - std::log(f0)));
  }
  return kEffFactors[kEffLevels - 1];
}

}  // namespace

double estimate_eff_scale(const Rgb8& img) {
  if (img.w < 16 || img.h < 16) return 1.0;
  const int tw = std::min(kEffTile, img.w), th = std::min(kEffTile, img.h);
  const std::vector<int> xs = tile_origins(img.w, tw), ys = tile_origins(img.h, th);
  auto luma = [&](int x, int y) { return luma01(img.row(y) + sz(x) * 3); };
  // Tiles by contrast: the mean |dx| + |dy| on an 8 px grid; ties keep the raster order.
  std::vector<std::pair<float, size_t>> score;
  for (size_t j = 0; j < ys.size(); ++j)
    for (size_t i = 0; i < xs.size(); ++i) {
      double s = 0;
      for (int y = ys[j]; y + 1 < ys[j] + th; y += 8)
        for (int x = xs[i]; x + 1 < xs[i] + tw; x += 8)
          s += std::fabs(luma(x + 1, y) - luma(x, y)) + std::fabs(luma(x, y + 1) - luma(x, y));
      score.push_back({float(s), j * xs.size() + i});
    }
  std::stable_sort(score.begin(), score.end(),
                   [](const auto& a, const auto& b) { return a.first > b.first; });
  if (score.size() > sz(kEffTiles)) score.resize(sz(kEffTiles));

  Edges lv[kEffLevels];
  for (const auto& [s, k] : score) {
    Plane t;
    t.w = tw;
    t.h = th;
    t.v.resize(sz(tw) * sz(th));
    const int x0 = xs[k % xs.size()], y0 = ys[k / xs.size()];
    for (int y = 0; y < th; ++y)
      for (int x = 0; x < tw; ++x) t.v[index2d(x, y, tw)] = luma(x0 + x, y0 + y);
    for (int i = 0; i < kEffLevels; ++i) {
      const double f = kEffFactors[i];
      const Plane d = area_resize(t, std::max(8, int(std::lround(tw * f))),
                                  std::max(8, int(std::lround(th * f))));
      collect_edges(d, lv[i]);
    }
  }
  double iso[kEffLevels], dir[kEffLevels];
  for (int i = 0; i < kEffLevels; ++i) {
    iso[i] = dir[i] = std::nan("");
    if (lv[i].g.size() < 200) continue;
    const Steepness st = steepness(lv[i]);
    iso[i] = st.all;
    for (double v : st.bins)
      if (!std::isnan(v)) dir[i] = std::isnan(dir[i]) ? v : std::min(dir[i], v);
  }
  return std::sqrt(crossing(iso, kEffTauIso) * crossing(dir, kEffTauDir));
}

nlohmann::json analyze_image(enh_session& s, const std::string& path,
                             const std::string& det_model) {
  ImageInfo info;
  Rgb8 img = apply_orientation(decode_image(path, &info), info.orientation);
  const int w = img.w, h = img.h;
  // Noise at a fixed analysis size: a downscale averages noise away, so a fixed size keeps
  // the estimate comparable between photos (and fast).
  constexpr int kNoiseSide = 1024;
  const double s1 = std::min(1.0, double(kNoiseSide) / std::max(w, h));
  const Rgb8 small = s1 < 1 ? resize_area(img, std::max(3, round_int(w * s1, 0, w)),
                                          std::max(3, round_int(h * s1, 0, h)))
                            : img;
  nlohmann::json faces = {
      {"count", 0}, {"largest_px", 0}, {"detector", false}, {"boxes", nlohmann::json::array()}};
  if (fs::exists(fs::join(fs::join(s.models_dir, det_model), "model.ncnn.bin"))) {
    std::lock_guard run(s.run_mu);  // with jobs: one model run at a time (ADR-0006)
    auto det = make_ncnn_backend({BackendKind::cpu, 0, false, s.cpu_threads});
    det->load(resolve_model(s.models_dir, det_model));
    const auto found = find_faces(*det, img);  // the faces a job would restore, largest first
    float largest = 0;
    nlohmann::json boxes = nlohmann::json::array();
    for (const Face& f : found) {
      largest = std::max(largest, std::max(f.w, f.h));
      // A face at the edge has its box partly outside the photo: the part inside is listed
      // (the app reads boxes as non-negative pixels of the photo).
      const float x0 = std::clamp(f.x, 0.f, float(w)), y0 = std::clamp(f.y, 0.f, float(h));
      const float x1 = std::clamp(f.x + f.w, 0.f, float(w)),
                  y1 = std::clamp(f.y + f.h, 0.f, float(h));
      boxes.push_back({std::round(x0), std::round(y0), std::round(x1 - x0), std::round(y1 - y0)});
    }
    faces = {{"count", found.size()},
             {"largest_px", int(largest)},
             {"detector", true},
             {"boxes", boxes}};
  }
  return {{"schema", 1},
          {"width", w},
          {"height", h},
          {"megapixels", double(w) * h / 1e6},
          {"noise_sigma", estimate_noise(small)},
          {"eff_scale", estimate_eff_scale(img)},  // ADR-0025: on the full resolution
          {"jpeg_quality", info.jpeg_quality},     // S9: 0 when not a JPEG
          {"faces", faces}};
}

}  // namespace enh
