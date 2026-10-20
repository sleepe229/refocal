// SPDX-License-Identifier: Apache-2.0
#include "policy/gpu_gate.hpp"

#include <mat.h>

#include <algorithm>
#include <cmath>
#include <nlohmann/json.hpp>

#include "image/image.hpp"
#include "util/fs.hpp"

namespace enh {
namespace {

int to_u8(float v) {
  if (!std::isfinite(v)) return 0;  // counted as nonfinite; float->int of NaN is UB
  v = v < 0.f ? 0.f : (v > 1.f ? 1.f : v);
  return round_int(double(v * 255.f), 0, 255);
}

}  // namespace

GateMetrics compare_tiles(const ncnn::Mat& out, const ncnn::Mat& ref) {
  GateMetrics m;
  if (out.w != ref.w || out.h != ref.h || out.c != ref.c || out.elemsize != 4 ||
      ref.elemsize != 4) {
    return m;  // shape mismatch: fail
  }
  double se = 0;
  long bad = 0, n = 0;
  m.max_abs = 0;
  for (int c = 0; c < out.c; ++c) {
    const float* a = out.channel(c);
    const float* b = ref.channel(c);
    for (int i = 0; i < out.w * out.h; ++i, ++n) {
      if (!std::isfinite(a[i])) ++m.nonfinite;
      int d = std::abs(to_u8(a[i]) - to_u8(b[i]));
      se += double(d) * d;
      if (d > 16) ++bad;
      m.max_abs = std::max(m.max_abs, d);
    }
  }
  double mse = n ? se / double(n) : 1e9;
  m.psnr = mse <= 0 ? 99.0 : std::min(99.0, 10.0 * std::log10(255.0 * 255.0 / mse));
  m.bad_frac = n ? double(bad) / double(n) : 1.0;
  m.pass = m.nonfinite == 0 && m.psnr >= 35.0 && m.bad_frac <= 1e-3;
  return m;
}

ncnn::Mat gate_input(int w, int h) {
  ncnn::Mat in(w, h, 3);
  uint32_t r = 0x9E3779B9u;
  for (int c = 0; c < 3; ++c) {
    float* p = in.channel(c);
    for (int y = 0; y < h; ++y)
      for (int x = 0; x < w; ++x) {
        r = r * 1664525u + 1013904223u;
        float grad = float(x + y * (c + 1)) / float(w + h * 3);
        float edge = ((x / 13 + y / 17 + c) % 2) ? 0.25f : 0.f;
        float noise = float(r >> 24) / 255.f * 0.2f;
        p[y * w + x] = std::min(1.f, grad * 0.55f + edge + noise);
      }
  }
  return in;
}

GateCache::GateCache(std::string path) : path_(std::move(path)) {}

std::string GateCache::get(const std::string& key) const {
  std::lock_guard lk(mu_);
  if (!fs::exists(path_)) return "";
  auto j = nlohmann::json::parse(fs::read_text(path_), nullptr, false);
  if (j.is_discarded() || !j.contains(key)) return "";
  return j[key].value("verdict", "");
}

void GateCache::put(const std::string& key, const std::string& verdict, const GateMetrics& m) {
  std::lock_guard lk(mu_);
  nlohmann::json j = nlohmann::json::object();
  if (fs::exists(path_)) {
    auto old = nlohmann::json::parse(fs::read_text(path_), nullptr, false);
    if (!old.is_discarded() && old.is_object()) j = old;
  }
  j[key] = {{"verdict", verdict},
            {"psnr", m.psnr},
            {"bad_frac", m.bad_frac},
            {"max_abs", m.max_abs},
            {"nonfinite", m.nonfinite}};
  fs::write_atomic(path_, j.dump(2) + "\n");
}

}  // namespace enh
