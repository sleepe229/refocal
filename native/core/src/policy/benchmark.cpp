// SPDX-License-Identifier: Apache-2.0
#include "policy/benchmark.hpp"

#include <net.h>

#include <algorithm>
#include <chrono>
#include <memory>
#include <mutex>

#include "backend/backend.hpp"
#include "job/session.hpp"
#include "policy/gpu_gate.hpp"
#include "policy/gpu_identity.hpp"
#include "policy/tier.hpp"
#include "util/error.hpp"

namespace enh {
namespace {

constexpr int kTile = 128;

struct Run {
  std::string name;
  bool gpu = false, fp16 = false;
  std::string status = "error";
  double ms = 0;
  GateMetrics gate;
};

// Median of [runs] timed runs after one warm-up; the output of the last run in [out].
double time_runs(InferenceBackend& be, const ncnn::Mat& in, int runs, ncnn::Mat& out) {
  using clock = std::chrono::steady_clock;
  be.run(in, out);  // warm-up: pipelines, allocations
  std::vector<double> ms;
  for (int i = 0; i < runs; ++i) {
    const auto t0 = clock::now();
    be.run(in, out);
    ms.push_back(std::chrono::duration<double, std::milli>(clock::now() - t0).count());
  }
  std::sort(ms.begin(), ms.end());
  return ms[ms.size() / 2];
}

}  // namespace

nlohmann::json run_benchmark(enh_session& s, const nlohmann::json& opts) {
  const std::string model_id = opts.value("model", std::string("sr.general-x4v3"));
  const int runs = std::clamp(opts.value("runs", 5), 1, 50);
  const double ram_gb = opts.value("ram_bytes", 0.0) / double(1 << 30);
  // Exclusive with jobs (one job at a time, ADR-0006): a job started now waits in "queued"
  // instead of skewing the timing.
  std::lock_guard run(s.run_mu);
  const ModelInfo model = resolve_model(s.models_dir, model_id);
  const int side = kTile + 2 * model.pad;
  const ncnn::Mat in = gate_input(side, side);

  std::vector<Run> results;
  ncnn::Mat ref;
  {  // CPU: the reference for the GPU gate
    Run r{"cpu", false, true};
    auto be = make_ncnn_backend({BackendKind::cpu, 0, true, s.cpu_threads});
    be->load(model);
    r.ms = time_runs(*be, in, runs, ref);
    r.name = be->name();
    r.status = "ok";
    results.push_back(r);
  }
  const int dev = s.gpu_allowed.load() ? vulkan_default_device() : -1;
  if (dev >= 0) {
    const GpuIdentity gpu = gpu_identity(dev);
    const MatchResult m = s.blocklist.match(gpu, model_id);
    for (const bool fp16 : {true, false}) {
      Run r{"vulkan:" + gpu.device_name + (fp16 ? ":fp16" : ":fp32"), true, fp16};
      if (m.action == Action::Cpu || m.action == Action::Disable ||
          (fp16 && m.action == Action::GpuFp32)) {
        r.status = "blocked";
        results.push_back(r);
        continue;
      }
      try {
        auto be = make_ncnn_backend({BackendKind::vulkan, dev, fp16, s.cpu_threads});
        be->load(model);
        ncnn::Mat out;
        r.ms = time_runs(*be, in, runs, out);
        r.gate = compare_tiles(out, ref);
        r.status = r.gate.pass ? "ok" : "wrong_output";
      } catch (const Error&) {
        r.status = "error";
      }
      results.push_back(r);
      if (fp16 && r.status == "ok") break;  // fp32 only when fp16 fails (05 §6.2)
    }
  }

  // The fastest healthy backend decides, not "GPU first" (05 §6.3).
  const Run* best = nullptr;
  for (const Run& r : results) {
    if (r.status == "ok" && (!best || r.ms < best->ms)) best = &r;
  }
  TierInput ti;
  ti.ram_gb = ram_gb;
  if (best) {
    ti.selected_backend = best->name;
    ti.selected_is_gpu = best->gpu;
    ti.selected_tile128_ms = best->ms;
  }
  const TierDecision d = suggest_tier(ti);

  nlohmann::json backends = nlohmann::json::array();
  for (const Run& r : results) {
    nlohmann::json b = {{"name", r.name},
                        {"kind", r.gpu ? "vulkan" : "cpu"},
                        {"fp16", r.fp16},
                        {"status", r.status},
                        {"tile128_ms", r.ms}};
    if (r.gpu && r.status != "blocked" && r.status != "error") {
      b["psnr"] = r.gate.psnr;
      b["bad_frac"] = r.gate.bad_frac;
    }
    backends.push_back(b);
  }
  return {{"schema", 1},
          {"model", model_id},
          {"tile", kTile},
          {"backends", backends},
          {"selected", best ? best->name : ""},
          {"selected_is_gpu", best && best->gpu},
          {"tile128_ms", best ? best->ms : 0.0},
          {"ram_gb", ram_gb},
          {"tier", d.tier},
          {"reasons", d.reasons},
          {"below_t0_budget", d.below_t0_budget}};
}

}  // namespace enh
