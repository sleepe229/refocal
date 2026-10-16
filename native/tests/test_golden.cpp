// TEST-ML-001: the bundled SR model on ncnn CPU against its PyTorch fp32 output on a golden tile
// (tools/models/golden.lock): PSNR >= 40 dB. Vulkan joins where a GPU exists (>= 35 dB). Without
// the weights (they are not in git) the test is skipped: tools/models/fetch.sh with
// DEST=<build>/golden and LOCK=tools/models/golden.lock puts them there. The RRDBNet packs
// (sr.x4plus, sr.x4plus-anime6b) are checked the same way when tools/models/fetch_pack.py has
// put them there with their golden pair (tools/models/convert_rrdb.py).
// TEST-ML-005 (NFR-REL-006): the same input, recipe and backend give a byte-identical result.
//   test_golden GOLDEN_DIR      (GOLDEN_DIR/sr.general-x4v3/{model.ncnn.*, golden_*.f32})
// SPDX-License-Identifier: Apache-2.0
#include <net.h>
#include <unistd.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <nlohmann/json.hpp>
#include <string>
#include <vector>

#include "backend/backend.hpp"
#include "enh.h"
#include "image/image.hpp"
#include "image/jpeg.hpp"
#include "mini_test.hpp"
#include "util/fs.hpp"

using namespace enh;

namespace {

constexpr int kSkip = 77;  // ctest SKIP_RETURN_CODE
constexpr int kIn = 160, kScale = 4, kOut = kIn * kScale;
constexpr int kRrdbIn = 96;  // convert_rrdb.py GOLDEN_IN

std::vector<float> read_f32(const std::string& path, size_t n) {
  std::vector<float> v(n);
  FILE* f = std::fopen(path.c_str(), "rb");
  if (!f) return {};
  const size_t got = std::fread(v.data(), sizeof(float), n, f);
  std::fclose(f);
  return got == n ? v : std::vector<float>{};
}

double psnr(const ncnn::Mat& out, const std::vector<float>& ref) {
  const int n = out.w * out.h;
  double se = 0;
  for (int c = 0; c < 3; ++c) {
    const float* o = out.channel(c);
    const float* r = ref.data() + size_t(c) * n;
    for (int i = 0; i < n; ++i) {
      const double d = std::fmin(std::fmax(o[i], 0.f), 1.f) - r[i];
      se += d * d;
    }
  }
  const double mse = se / (3.0 * n);
  return mse == 0 ? 99 : 10 * std::log10(1 / mse);
}

// PSNR of [m] on the [size]x[size] tile [in] against [ref] (its fp32 output, x[m.scale]).
double run(const BackendConfig& cfg, const ModelInfo& m, int size, const std::vector<float>& in,
           const std::vector<float>& ref) {
  auto be = make_ncnn_backend(cfg);
  be->load(m);
  ncnn::Mat x(size, size, 3);
  for (int c = 0; c < 3; ++c) {
    std::copy_n(in.data() + size_t(c) * size * size, size * size,
                static_cast<float*>(x.channel(c)));
  }
  ncnn::Mat y;
  be->run(x, y);
  const int out = size * m.scale;
  CHECK(y.w == out && y.h == out && y.c == 3);
  if (y.w != out || y.h != out || y.c != 3) return 0;
  const double db = psnr(y, ref);
  std::printf("golden %s %s: %.2f dB\n", m.id.c_str(), be->name().c_str(), db);
  return db;
}

// TEST-ML-001 for an RRDBNet pack, when its weights and golden pair are in [root].
void rrdb(const std::string& root, const std::string& id) {
  const std::string dir = fs::join(root, id);
  const int out = kRrdbIn * kScale;
  const auto in = read_f32(fs::join(dir, "golden_in_3x96x96.f32"), size_t(3) * kRrdbIn * kRrdbIn);
  const auto ref = read_f32(fs::join(dir, "golden_out_3x384x384.f32"), size_t(3) * out * out);
  if (in.empty() || ref.empty() || !fs::exists(fs::join(dir, "model.ncnn.bin"))) {
    std::printf("golden %s: not in %s, skipped\n", id.c_str(), root.c_str());
    return;
  }
  const ModelInfo m = resolve_model(root, id);
  CHECK(m.scale == kScale);
  CHECK(run({BackendKind::cpu, 0, true, 0}, m, kRrdbIn, in, ref) >= 40);
}

// Runs a job to its end on [s]; its result's bands, concatenated, and its recipe hash.
std::pair<std::vector<uint8_t>, std::string> job(enh_session* s, const std::string& jobs_dir,
                                                 const nlohmann::json& req) {
  const std::string r = req.dump();
  enh_job* j = nullptr;
  CHECK(enh_job_create(s, r.c_str(), &j) == ENH_OK);
  if (!j) return {};
  CHECK(enh_job_start(
            j, [](int64_t, int32_t, int32_t, int64_t, int64_t, char* p) { enh_free(p); }, 1) ==
        ENH_OK);
  for (int i = 0; i < 3000 && enh_job_status(j) < 0; ++i) usleep(20000);
  CHECK(enh_job_status(j) == ENH_OK);
  enh_job_destroy(j);
  const std::string dir = fs::join(jobs_dir, req["job_id"].get<std::string>());
  const auto res = nlohmann::json::parse(fs::read_text(fs::join(dir, "result.json")));
  std::vector<uint8_t> all;
  for (size_t b = 0; b < res["band_rows"].size(); ++b) {
    char name[32];
    std::snprintf(name, sizeof name, "bands/%04zu.raw", b);
    const auto d = fs::read_all(fs::join(dir, name));
    all.insert(all.end(), d.begin(), d.end());
  }
  return {all, res["recipe_hash"].get<std::string>()};
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
  CHECK(run({BackendKind::cpu, 0, true, 0}, m, kIn, in, ref) >= 40);
  if (vulkan_default_device() >= 0) {
    CHECK(run({BackendKind::vulkan, vulkan_default_device(), true, 0}, m, kIn, in, ref) >= 35);
  }
  rrdb(argv[1], "sr.x4plus");
  rrdb(argv[1], "sr.x4plus-anime6b");
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

  // TEST-ML-005: a 320x240 input from the golden tile, several 128 px tiles, 4 CPU threads.
  {
    const std::string work = fs::join(argv[1], "determinism");
    fs::remove_tree(work);
    fs::mkdirs(fs::join(work, "jobs"));
    Rgb8 img;
    img.w = 320;
    img.h = 240;
    img.px.resize(size_t(img.w) * img.h * 3);
    for (int y = 0; y < img.h; ++y)
      for (int x = 0; x < img.w; ++x)
        for (int c = 0; c < 3; ++c)
          img.px[(size_t(y) * img.w + x) * 3 + c] = uint8_t(
              std::lround(255 * in[size_t(c) * kIn * kIn + size_t(y % kIn) * kIn + x % kIn]));
    const std::string input = fs::join(work, "in.jpg");
    jpeg_encode(input, img, 90);
    enh_session_config dc{};
    dc.struct_size = sizeof dc;
    dc.models_dir = argv[1];
    const std::string jobs_dir = fs::join(work, "jobs");
    dc.work_dir = jobs_dir.c_str();
    dc.backend_pref = ENH_BACKEND_NCNN_CPU;
    dc.cpu_threads = 4;
    enh_session* ds = nullptr;
    CHECK(enh_session_create(&dc, &ds) == ENH_OK);
    if (ds) {
      nlohmann::json q = {
          {"schema", 1}, {"input", input}, {"sr_model", "sr.general-x4v3"}, {"tile", 128}};
      q["job_id"] = "a";
      const auto a = job(ds, jobs_dir, q);
      q["job_id"] = "b";
      const auto b = job(ds, jobs_dir, q);
      CHECK(!a.first.empty() && a.first.size() == size_t(1280) * 960 * 3);
      CHECK(a.first == b.first);
      CHECK(a.second == b.second);
      std::printf("determinism: %zu bytes, identical: %s\n", a.first.size(),
                  a.first == b.first ? "yes" : "NO");
      enh_session_destroy(ds);
    }
  }
  std::printf("%d checks, %d failures\n", mini::checks(), mini::failures());
  return mini::failures() ? 1 : 0;
}
