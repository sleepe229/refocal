// SPDX-License-Identifier: Apache-2.0
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <mutex>
#include <nlohmann/json.hpp>

#include <cpu.h>
#include <gpu.h>
#include <net.h>

#include "backend/backend.hpp"
#include "util/error.hpp"
#include "util/fs.hpp"
#include "util/log.hpp"

namespace enh {

ModelInfo resolve_model(const std::string& models_dir, const std::string& id) {
  if (id.empty() || id.find('/') != std::string::npos || id.find("..") != std::string::npos) {
    fail(ENH_E_INVALID, "bad model id");
  }
  ModelInfo m;
  m.id = id;
  std::string dir = fs::join(models_dir, id);
  m.param_path = fs::join(dir, "model.ncnn.param");
  m.bin_path = fs::join(dir, "model.ncnn.bin");
  if (!fs::exists(m.param_path) || !fs::exists(m.bin_path)) fail(ENH_E_MODEL, "model not installed: " + id);
  std::string meta = fs::join(dir, "model.json");
  if (fs::exists(meta)) {
    auto j = nlohmann::json::parse(fs::read_text(meta), nullptr, false);
    if (j.is_discarded()) fail(ENH_E_MODEL, "bad model.json: " + id);
    m.scale = j.value("scale", 4);
    m.pad = j.value("pad", 16);
  }
  if (m.scale != 1 && m.scale != 2 && m.scale != 4) fail(ENH_E_MODEL, "unsupported model scale");
  return m;
}

int vulkan_device_count() {
#if NCNN_VULKAN
  static std::once_flag once;
  static int count = 0;
  std::call_once(once, [] {
    // Never destroyed: drivers misbehave on repeated create/destroy (S3), and the process
    // keeps one instance for its lifetime.
    if (ncnn::create_gpu_instance() == 0) count = ncnn::get_gpu_count();
  });
  return count;
#else
  return 0;
#endif
}

int vulkan_default_device() {
#if NCNN_VULKAN
  const int n = vulkan_device_count();
  if (n == 0) return -1;
  const int def = ncnn::get_default_gpu_index();
  if (def >= 0 && def < n && ncnn::get_gpu_info(def).type() != 3) return def;
  for (int i = 0; i < n; ++i)
    if (ncnn::get_gpu_info(i).type() != 3) return i;
  return -1;
#else
  return -1;
#endif
}

namespace {

class NcnnBackend final : public InferenceBackend {
 public:
  explicit NcnnBackend(const BackendConfig& cfg) : cfg_(cfg) {}

  std::string name() const override { return name_; }
  const BackendConfig& config() const override { return cfg_; }

  void load(const ModelInfo& m) override {
    ncnn::Option& o = net_.opt;
    o.lightmode = true;
    o.num_threads = cfg_.threads > 0 ? cfg_.threads : std::max(1, ncnn::get_big_cpu_count());
    o.use_bf16_storage = false;
    if (cfg_.kind == BackendKind::vulkan) {
#if NCNN_VULKAN
      if (cfg_.device >= vulkan_device_count()) fail(ENH_E_BACKEND, "Vulkan device not available");
      net_.set_vulkan_device(cfg_.device);
      o.use_vulkan_compute = true;
      o.use_fp16_storage = cfg_.fp16;
      o.use_fp16_packed = cfg_.fp16;
      o.use_fp16_arithmetic = cfg_.fp16;
      name_ = std::string("vulkan:") + ncnn::get_gpu_info(cfg_.device).device_name() +
              (cfg_.fp16 ? ":fp16" : ":fp32");
#else
      fail(ENH_E_BACKEND, "built without Vulkan");
#endif
    } else {
      o.use_vulkan_compute = false;
      name_ = "cpu:" + std::to_string(o.num_threads);
    }
    if (net_.load_param(m.param_path.c_str()) != 0) fail(ENH_E_MODEL, "load_param failed: " + m.id);
    if (net_.load_model(m.bin_path.c_str()) != 0) fail(ENH_E_MODEL, "load_model failed: " + m.id);
    if (net_.input_names().empty() || net_.output_names().empty()) fail(ENH_E_MODEL, "model has no blobs");
    in_name_ = net_.input_names().front();
    out_name_ = net_.output_names().front();
  }

  void run(const ncnn::Mat& in, ncnn::Mat& out) override {
#ifdef ENH_FAULT_INJECTION
    inject_fault();
#endif
    ncnn::Extractor ex = net_.create_extractor();
    if (ex.input(in_name_.c_str(), in) != 0) fail(ENH_E_BACKEND, "ncnn input failed");
    if (ex.extract(out_name_.c_str(), out) != 0 || out.empty()) fail(ENH_E_BACKEND, "ncnn extract failed");
    // Silent garbage is checked by the benchmark gate (S3); NaN/Inf is checked on every tile.
    if (out.elemsize != 4 || out.elempack != 1) fail(ENH_E_BACKEND, "unexpected output layout");
    for (int c = 0; c < out.c; ++c) {
      const float* ch = out.channel(c);
      for (size_t i = 0; i < size_t(out.w) * out.h; ++i)
        if (!std::isfinite(ch[i])) fail(ENH_E_NUMERIC, "non-finite model output");
    }
  }

 private:
#ifdef ENH_FAULT_INJECTION
  // ENH_FAULT=<cpu|vulkan_fp16|vulkan_fp32>:<numeric|backend>:<n> fails the n-th run (0-based)
  // of that backend. Test/CLI builds only (TEST-FAULT-*, fallback ladder).
  void inject_fault() {
    const char* f = std::getenv("ENH_FAULT");
    if (!f) return;
    std::string spec(f), kind = cfg_.kind == BackendKind::cpu ? "cpu" : cfg_.fp16 ? "vulkan_fp16" : "vulkan_fp32";
    size_t a = spec.find(':'), b = spec.find(':', a + 1);
    if (a == std::string::npos || b == std::string::npos || spec.substr(0, a) != kind) return;
    if (runs_++ != std::stoi(spec.substr(b + 1))) return;
    fail(spec.substr(a + 1, b - a - 1) == "numeric" ? ENH_E_NUMERIC : ENH_E_BACKEND, "injected fault");
  }
  int runs_ = 0;
#endif
  BackendConfig cfg_;
  ncnn::Net net_;
  std::string name_, in_name_, out_name_;
};

}  // namespace

std::unique_ptr<InferenceBackend> make_ncnn_backend(const BackendConfig& cfg) {
  return std::make_unique<NcnnBackend>(cfg);
}

}  // namespace enh
