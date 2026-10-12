// Inference backend interface (03 §4.3). Tensors are ncnn::Mat (CHW float), which every
// backend can produce/consume; Core ML (iOS) converts at its boundary.
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <memory>
#include <string>

namespace ncnn {
class Mat;
}

namespace enh {

enum class BackendKind { cpu, vulkan };

struct BackendConfig {
  BackendKind kind = BackendKind::cpu;
  int device = 0;     // Vulkan device index
  bool fp16 = true;   // Vulkan: fp16 storage+arithmetic; false = fp32 (fallback, S3)
  int threads = 0;    // CPU threads, 0 = big cores
};

struct ModelInfo {
  std::string id, param_path, bin_path;
  int scale = 4;      // spatial scale of the network
  int pad = 16;       // tile pad (S2: 16 for compact)
};

// Resolves models_dir/<id>/model.ncnn.{param,bin} (+ optional model.json {scale, pad}).
ModelInfo resolve_model(const std::string& models_dir, const std::string& id);

class InferenceBackend {
 public:
  virtual ~InferenceBackend() = default;
  virtual std::string name() const = 0;
  virtual const BackendConfig& config() const = 0;
  // Throws enh::Error: ENH_E_MODEL (load), ENH_E_BACKEND (run), ENH_E_NUMERIC (NaN/Inf output).
  virtual void load(const ModelInfo& m) = 0;
  virtual void run(const ncnn::Mat& in, ncnn::Mat& out) = 0;
};

std::unique_ptr<InferenceBackend> make_ncnn_backend(const BackendConfig& cfg);

// Vulkan availability (creates the process-wide Vulkan instance on first call).
int vulkan_device_count();
// ncnn's preferred device (discrete GPU first); 0 when there is only one.
int vulkan_default_device();

}  // namespace enh
