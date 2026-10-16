// TEST-ML-001: the bundled SR model on ncnn CPU against its PyTorch fp32 output on a golden tile
// (tools/models/golden.lock): PSNR >= 40 dB. Vulkan joins where a GPU exists (>= 35 dB). Without
// the weights (they are not in git) the test is skipped: tools/models/fetch.sh with
// DEST=<build>/golden and LOCK=tools/models/golden.lock puts them there.
//   test_golden GOLDEN_DIR      (GOLDEN_DIR/sr.general-x4v3/{model.ncnn.*, golden_*.f32})
// SPDX-License-Identifier: Apache-2.0
#include <net.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <nlohmann/json.hpp>
#include <string>
#include <vector>

#include "backend/backend.hpp"
#include "enh.h"
#include "mini_test.hpp"
#include "util/fs.hpp"

using namespace enh;

namespace {

constexpr int kSkip = 77;  // ctest SKIP_RETURN_CODE
constexpr int kIn = 160, kScale = 4, kOut = kIn * kScale;

std::vector<float> read_f32(const std::string& path, size_t n) {
  std::vector<float> v(n);
  FILE* f = std::fopen(path.c_str(), "rb");
  if (!f) return {};
  const size_t got = std::fread(v.data(), sizeof(float), n, f);
  std::fclose(f);
  return got == n ? v : std::vector<float>{};
}

double psnr(const ncnn::Mat& out, const std::vector<float>& ref) {
  double se = 0;
  for (int c = 0; c < 3; ++c) {
    const float* o = out.channel(c);
    const float* r = ref.data() + size_t(c) * kOut * kOut;
    for (int i = 0; i < kOut * kOut; ++i) {
      const double d = std::fmin(std::fmax(o[i], 0.f), 1.f) - r[i];
      se += d * d;
    }
  }
  const double mse = se / (3.0 * kOut * kOut);
  return mse == 0 ? 99 : 10 * std::log10(1 / mse);
}

double run(const BackendConfig& cfg, const ModelInfo& m, const std::vector<float>& in,
           const std::vector<float>& ref) {
  auto be = make_ncnn_backend(cfg);
  be->load(m);
  ncnn::Mat x(kIn, kIn, 3);
  for (int c = 0; c < 3; ++c) {
    std::copy_n(in.data() + size_t(c) * kIn * kIn, kIn * kIn, static_cast<float*>(x.channel(c)));
  }
  ncnn::Mat y;
  be->run(x, y);
  CHECK(y.w == kOut && y.h == kOut && y.c == 3);
  if (y.w != kOut || y.h != kOut || y.c != 3) return 0;
  const double db = psnr(y, ref);
  std::printf("golden %s: %.2f dB\n", be->name().c_str(), db);
  return db;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 2) return kSkip;
  const std::string dir = fs::join(argv[1], "sr.general-x4v3");
  const auto in = read_f32(fs::join(dir, "golden_in_3x160x160.f32"), size_t(3) * kIn * kIn);
  const auto ref =
      read_f32(fs::join(dir, "golden_out_dn050_3x640x640.f32"), size_t(3) * kOut * kOut);
  if (in.empty() || ref.empty() || !fs::exists(fs::join(dir, "model.ncnn.bin"))) {
    std::printf("golden: no weights in %s, skipped\n", dir.c_str());
    return kSkip;
  }
  const ModelInfo m = resolve_model(argv[1], "sr.general-x4v3");
  CHECK(m.scale == kScale);
  CHECK(run({BackendKind::cpu, 0, true, 0}, m, in, ref) >= 40);
  if (vulkan_default_device() >= 0) {
    CHECK(run({BackendKind::vulkan, vulkan_default_device(), true, 0}, m, in, ref) >= 35);
  }
  // ADR-0017 micro-benchmark on the real weights: CPU always runs; a tier comes out.
  enh_session_config cfg{};
  cfg.struct_size = sizeof cfg;
  cfg.models_dir = argv[1];
  cfg.work_dir = argv[1];
  enh_session* s = nullptr;
  CHECK(enh_session_create(&cfg, &s) == ENH_OK);
  char* out = nullptr;
  CHECK(enh_benchmark(s, R"({"runs": 3, "ram_bytes": 8589934592})", &out) == ENH_OK);
  if (out) {
    const auto b = nlohmann::json::parse(out);
    enh_free(out);
    std::printf("benchmark: %s\n", b.dump().c_str());
    CHECK(b["backends"][0]["kind"] == "cpu" && b["backends"][0]["status"] == "ok");
    CHECK(b["tile128_ms"].get<double>() > 0);
    const std::string tier = b["tier"];
    CHECK(tier == "T0" || tier == "T1" || tier == "T2");
  }
  enh_session_destroy(s);
  std::printf("%d checks, %d failures\n", mini::checks(), mini::failures());
  return mini::failures() ? 1 : 0;
}
