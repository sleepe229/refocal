// refocal-cli: the native core on the desktop — golden tests, perf runs, bug reproduction.
// Uses the public C ABI for jobs (same path as the app) and core internals only for compare.
//
//   refocal-cli probe
//   refocal-cli run --models DIR --work DIR --input IN --out OUT.jpg [--model ID] [--scale 4|2|1]
//                   [--fast2] [--tile N] [--backend auto|cpu|vulkan] [--threads N] [--quality Q]
//                   [--job-id ID] [--resume] [--json] [--cache DIR] [--tier T0|T1|T2]
//                   [--no-exif] [--keep-gps] [--no-ai-marker]
//   refocal-cli compare A B [--min-psnr DB]   (exit 1 if below)
// IN, A, B: JPEG, PNG or WebP (HEIC/AVIF need the platform decoder: Android only).
//
// SPDX-License-Identifier: Apache-2.0
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

#include "enh.h"
#include "image/decode.hpp"
#include "util/error.hpp"
#include "util/fs.hpp"

using json = nlohmann::json;

namespace {

struct Args {
  std::vector<std::string> pos;
  std::string get(const std::string& k, const std::string& def = "") const {
    for (size_t i = 0; i + 1 < pos.size(); ++i)
      if (pos[i] == k) return pos[i + 1];
    return def;
  }
  bool has(const std::string& k) const {
    for (auto& p : pos)
      if (p == k) return true;
    return false;
  }
};

int usage() {
  std::fprintf(stderr,
               "usage:\n  refocal-cli probe\n"
               "  refocal-cli run --models DIR --work DIR --input IN --out OUT.jpg [--model ID]\n"
               "              [--scale 4|2|1] [--fast2] [--tile N] [--backend auto|cpu|vulkan]\n"
               "              [--threads N] [--quality Q] [--job-id ID] [--resume] [--json]\n"
               "              [--cache DIR] [--tier T0|T1|T2] [--no-exif] [--keep-gps] [--no-ai-marker]\n"
               "  refocal-cli compare A B [--min-psnr DB]\n");
  return 2;
}

struct Sink {
  std::mutex mu;
  std::condition_variable cv;
  bool done = false;
  int32_t status = -1;
  json result;
  bool json_out = false;
};
Sink g_sink;

void on_event(int64_t, int32_t type, int32_t, int64_t done, int64_t total, char* p) {
  json j = json::parse(p, nullptr, false);
  enh_free(p);
  if (g_sink.json_out) std::printf("%s\n", json{{"type", type}, {"done", done}, {"total", total}, {"payload", j}}.dump().c_str());
  std::lock_guard lk(g_sink.mu);
  switch (type) {
    case ENH_EV_STAGE:
      if (!g_sink.json_out) std::fprintf(stderr, "stage %s\n", j.value("stage", "?").c_str());
      break;
    case ENH_EV_PROGRESS:
      if (!g_sink.json_out)
        std::fprintf(stderr, "\r%lld/%lld tiles, eta %.1f s   ", (long long)done, (long long)total,
                     j.value("eta_ms", int64_t(-1)) / 1000.0);
      break;
    case ENH_EV_FALLBACK:
      std::fprintf(stderr, "\nfallback %s -> %s (%s)\n", j.value("from", "").c_str(),
                   j.value("to", "").c_str(), j.value("reason", "").c_str());
      break;
    case ENH_EV_WARNING:
      std::fprintf(stderr, "\nwarning %s\n", j.value("code", "").c_str());
      break;
    case ENH_EV_NEEDS_USER:
      std::fprintf(stderr, "\nneeds user: %s (rerun with a smaller --scale or --fast2)\n", j.dump().c_str());
      break;
    case ENH_EV_DONE:
      g_sink.done = true;
      g_sink.status = ENH_OK;
      g_sink.result = j;
      break;
    case ENH_EV_ERROR:
      g_sink.done = true;
      g_sink.status = j.value("status", int(ENH_E_INTERNAL));
      g_sink.result = j;
      break;
  }
  g_sink.cv.notify_all();
}

int cmd_probe() {
  enh_session_config cfg{};
  cfg.struct_size = sizeof cfg;
  enh_session* s = nullptr;
  if (enh_session_create(&cfg, &s) != ENH_OK) return 1;
  char* out = nullptr;
  int rc = enh_device_probe(s, &out) == ENH_OK ? 0 : 1;
  if (out) std::printf("%s\n", json::parse(out).dump(2).c_str());
  enh_free(out);
  enh_session_destroy(s);
  return rc;
}

int cmd_run(const Args& a) {
  std::string models = a.get("--models"), work = a.get("--work"), input = a.get("--input"),
              out = a.get("--out");
  if (models.empty() || work.empty() || input.empty() || out.empty()) return usage();
  g_sink.json_out = a.has("--json");
  enh::fs::mkdirs(work);
  enh_session_config cfg{};
  cfg.struct_size = sizeof cfg;
  cfg.models_dir = models.c_str();
  cfg.work_dir = work.c_str();
  std::string backend = a.get("--backend", "auto");
  cfg.backend_pref = backend == "cpu" ? ENH_BACKEND_NCNN_CPU
                     : backend == "vulkan" ? ENH_BACKEND_NCNN_VULKAN
                                           : ENH_BACKEND_AUTO;
  cfg.cpu_threads = std::atoi(a.get("--threads", "0").c_str());
  std::string cache = a.get("--cache");  // crash sentinel + GPU gate verdicts
  cfg.cache_dir = cache.empty() ? nullptr : cache.c_str();
  std::string tier = a.get("--tier");
  cfg.tier = tier.empty() ? nullptr : tier.c_str();
  enh_session* s = nullptr;
  if (enh_session_create(&cfg, &s) != ENH_OK) return 1;

  std::string job_id = a.get("--job-id", "cli");
  enh_job* j = nullptr;
  enh_status st;
  if (a.has("--resume")) {
    st = enh_job_resume(s, enh::fs::join(work, job_id).c_str(), &j);
  } else {
    json req = {{"schema", 1},
                {"job_id", job_id},
                {"input", input},
                {"sr_model", a.get("--model", "sr.general-x4v3")},
                {"scale", std::atoi(a.get("--scale", "4").c_str())},
                {"fast2", a.has("--fast2")},
                {"tile", std::atoi(a.get("--tile", "0").c_str())},
                {"backend", backend}};
    st = enh_job_create(s, req.dump().c_str(), &j);
  }
  if (st != ENH_OK) {
    std::fprintf(stderr, "job create failed: %d\n", st);
    enh_session_destroy(s);
    return 1;
  }
  auto t0 = std::chrono::steady_clock::now();
  enh_job_start(j, on_event, 1);
  {
    std::unique_lock lk(g_sink.mu);
    g_sink.cv.wait(lk, [] { return g_sink.done; });
  }
  enh_job_destroy(j);
  std::fprintf(stderr, "\n");
  int rc = 0;
  if (g_sink.status != ENH_OK) {
    std::fprintf(stderr, "job failed: %s\n", g_sink.result.dump().c_str());
    rc = 1;
  } else {
    char* ex = nullptr;
    std::string opt = json{{"format", "jpeg"},
                           {"quality", std::atoi(a.get("--quality", "92").c_str())},
                           {"metadata",
                            {{"exif", !a.has("--no-exif")},
                             {"gps", a.has("--keep-gps")},
                             {"ai_marker", !a.has("--no-ai-marker")}}}}
                          .dump();
    if (enh_export(s, enh::fs::join(work, job_id).c_str(), opt.c_str(), out.c_str(), &ex) != ENH_OK) {
      std::fprintf(stderr, "export failed\n");
      rc = 1;
    }
    double sec = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    json summary = g_sink.result;
    summary["export"] = ex ? json::parse(ex) : json();
    summary["wall_s"] = sec;
    enh_free(ex);
    if (!g_sink.json_out) std::printf("%s\n", summary.dump(2).c_str());
  }
  enh_session_destroy(s);
  return rc;
}

int cmd_compare(const Args& a) {
  if (a.pos.size() < 3) return usage();
  try {
    enh::Rgb8 x = enh::decode_image(a.pos[1]), y = enh::decode_image(a.pos[2]);
    if (x.w != y.w || x.h != y.h) {
      std::fprintf(stderr, "size mismatch: %dx%d vs %dx%d\n", x.w, x.h, y.w, y.h);
      return 1;
    }
    double se = 0;
    int maxd = 0;
    for (size_t i = 0; i < x.px.size(); ++i) {
      int d = int(x.px[i]) - int(y.px[i]);
      se += double(d) * d;
      maxd = std::max(maxd, std::abs(d));
    }
    double mse = se / double(x.px.size());
    double psnr = mse == 0 ? 99.0 : 10 * std::log10(255.0 * 255.0 / mse);
    std::printf("{\"psnr_db\": %.2f, \"max_abs\": %d, \"width\": %d, \"height\": %d}\n", psnr, maxd, x.w, x.h);
    std::string min = a.get("--min-psnr");
    return !min.empty() && psnr < std::atof(min.c_str()) ? 1 : 0;
  } catch (const std::exception& e) {
    std::fprintf(stderr, "%s\n", e.what());
    return 1;
  }
}

}  // namespace

int main(int argc, char** argv) {
  Args a;
  for (int i = 1; i < argc; ++i) a.pos.emplace_back(argv[i]);
  if (a.pos.empty()) return usage();
  if (a.pos[0] == "probe") return cmd_probe();
  if (a.pos[0] == "run") return cmd_run(a);
  if (a.pos[0] == "compare") return cmd_compare(a);
  return usage();
}
