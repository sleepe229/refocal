// GPU correctness gate (ADR-0017, S3): before a Vulkan precision is used for a model on a given
// device+driver, one tile of the working shape runs on the CPU and on the GPU and the outputs are
// compared. Silent garbage (S1: GFPGAN fp16 at 10 dB without a single NaN; S2: ncnn Vulkan errors
// up to 164/255 at large shapes) is caught here; the verdict is cached per key.
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <map>
#include <mutex>
#include <string>

namespace ncnn {
class Mat;
}

namespace enh {

struct GateMetrics {
  double psnr = 0;
  double bad_frac = 1;  // share of 8-bit values off by more than 16 levels
  int max_abs = 255;
  long nonfinite = 0;
  bool pass = false;
};

// S3 thresholds: no NaN/Inf, PSNR >= 35 dB, bad_frac <= 0.1%.
GateMetrics compare_tiles(const ncnn::Mat& out, const ncnn::Mat& ref);

// Deterministic textured tile (gradients, edges, noise) in [0,1], CHW 3 x h x w.
ncnn::Mat gate_input(int w, int h);

class GateCache {
 public:
  explicit GateCache(std::string path);
  // "ok" | "bad" | "" (unknown)
  std::string get(const std::string& key) const;
  void put(const std::string& key, const std::string& verdict, const GateMetrics& m);

 private:
  std::string path_;
  mutable std::mutex mu_;
};

}  // namespace enh
