// Correctness-checked microbenchmark of one (model, backend) pair.
#pragma once

#include <string>
#include <vector>

#include <nlohmann/json.hpp>

namespace refocal {

struct ModelSpec {
    std::string id;         // "sr.general-x4v3" | "face.gfpgan-1.4"
    std::string param, bin;
    std::string input_file;   // raw float32 CHW
    int c = 3, h = 0, w = 0;
    std::string golden_file;  // raw float32 CHW
    int oc = 3, oh = 0, ow = 0;
    float lo = 0.f, hi = 1.f;  // value range mapped to 0..255 for 8-bit metrics
    bool face = false;         // CPU path: winograd/sgemm off (S1 memory finding)
    bool tile128 = false;      // also time a 128x128 crop (05 §6.2 tile size)
};

struct BackendSpec {
    std::string name;  // "vk0-fp16", "vk1-fp32", "cpu-fp16", "cpu-fp32"
    int gpu = -1;      // -1 = CPU
    bool fp16 = true;
};
bool parse_backend(const std::string& s, BackendSpec& out);

struct Gate {
    double min_psnr = 35.0;        // ADR-0017 / 05 §6.2
    double max_bad_frac = 1e-3;    // share of 8-bit values off by > bad_level (S3 proposal)
    int bad_level = 16;
};

struct BenchConfig {
    int threads = 0;  // 0 = big cores
    int warmup = 1;
    int runs = 5;
    double max_run_ms = 0;  // >0: if the warm-up run is slower, stop with status "too_slow" (NFR-PERF-009 budget)
    std::string corrupt;  // synthetic corruption: zero|noise|nan|block32|half|swap_rb|offset
    Gate gate;
};

struct Metrics {
    double psnr = 0;
    double bad_frac = 0;
    int max_abs_u8 = 0;
    long nonfinite = 0;
};
Metrics compare_u8(const std::vector<float>& out, const std::vector<float>& ref, float lo, float hi, int bad_level);
void apply_corruption(std::vector<float>& v, int c, int h, int w, const std::string& mode);

bool load_f32(const std::string& path, size_t count, std::vector<float>& out);

// Runs warm-up + timed runs + correctness check in the current process.
nlohmann::json run_bench(const ModelSpec& m, const BackendSpec& b, const BenchConfig& cfg);

// Calibration: run compact SR over a full W x H image as tile x tile crops (pad px overlap),
// sequentially, inference only (no pre/post). Links microbenchmark ms to NFR-PERF-001 seconds.
nlohmann::json run_tiled(const ModelSpec& m, const BackendSpec& b, int threads, int W, int H, int tile, int pad);

}  // namespace refocal
