// SPDX-License-Identifier: Apache-2.0
#include "policy/analyze.hpp"

#include <algorithm>
#include <cmath>
#include <mutex>

#include "backend/backend.hpp"
#include "image/decode.hpp"
#include "image/ops.hpp"
#include "job/session.hpp"
#include "pipeline/faces.hpp"
#include "util/fs.hpp"
#include "util/size.hpp"

namespace enh {

double estimate_noise(const Rgb8& img) {
  if (img.w < 3 || img.h < 3) return 0;
  std::vector<float> y(sz(img.w) * sz(img.h));
  for (int r = 0; r < img.h; ++r) {
    const uint8_t* p = img.row(r);
    for (int c = 0; c < img.w; ++c, p += 3) {
      y[sz(r) * sz(img.w) + sz(c)] = 0.299f * p[0] + 0.587f * p[1] + 0.114f * p[2];
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

nlohmann::json analyze_image(enh_session& s, const std::string& path,
                             const std::string& det_model) {
  ImageInfo info;
  Rgb8 img = apply_orientation(decode_image(path, &info), info.orientation);
  const int w = img.w, h = img.h;
  // Noise at a fixed analysis size: a downscale averages noise away, so a fixed size keeps
  // the estimate comparable between photos (and fast).
  constexpr int kNoiseSide = 1024;
  const double s1 = std::min(1.0, double(kNoiseSide) / std::max(w, h));
  const Rgb8 small =
      s1 < 1 ? resize_area(img, std::max(3, int(w * s1 + 0.5)), std::max(3, int(h * s1 + 0.5)))
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
          {"jpeg_quality", info.jpeg_quality},  // S9: 0 when not a JPEG
          {"faces", faces}};
}

}  // namespace enh
