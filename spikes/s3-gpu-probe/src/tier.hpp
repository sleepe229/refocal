// Tier suggestion (05 §6.3 / ADR-0017), with S3-proposed thresholds.
//
// Thresholds are derived from NFR-PERF-001 (1 MP -> 4x compact SR, no faces: T0 40 s,
// T1 12 s, T2 4 s): 1 MP at tile 128 / pad 16 is ~108 tiles; +30% pre/post overhead
// -> ~140 "tile128 units". T2 <= 4000/140 ~ 28 ms, T1 <= 12000/140 ~ 85 ms,
// T0 <= 40000/140 ~ 285 ms. Rounded down for margin (see docs/spikes/S3.md).
#pragma once

#include <string>
#include <vector>

namespace refocal {

struct TierThresholds {
    // MemTotal / physicalMemory under-report marketing RAM (kernel + carve-outs): a "4 GB" phone
    // shows ~3.5-3.8 GB, an "8 GB" one ~7.2-7.7 GB. Thresholds sit between the classes.
    double t0_ram_gb = 3.3;    // "< 4 GB" class -> T0 regardless of speed
    double t2_ram_gb = 7.0;    // ">= 8 GB" class
    double t2_tile128_ms = 25;
    double t1_tile128_ms = 80;
    double t0_tile128_ms = 280;  // slower than this: T0 with "NFR-PERF-001 not met" warning
    // 05 §6.3 requires "soc in T2_SOCS" for T2. S3 proposes: SoC table is only a hint before the
    // first benchmark; with a benchmark, speed + RAM decide (catches Tensor G3, Xclipse, new SoCs).
    bool require_soc_for_t2 = false;
};

struct TierInput {
    double ram_gb = 0;
    std::string selected_backend;  // fastest healthy backend for compact SR ("" = none)
    bool selected_is_gpu = false;
    double selected_tile128_ms = 0;
    int soc_t2 = -1;  // 1 in T2 SoC list, 0 not, -1 unknown (bench decides)
};

struct TierDecision {
    std::string tier;
    std::vector<std::string> reasons;
    bool below_t0_budget = false;
};

TierDecision suggest_tier(const TierInput& in, const TierThresholds& th = {});

// Minimal T2 SoC hint list (used only when the benchmark has not run yet).
int soc_in_t2_list(const std::string& soc);

}  // namespace refocal
