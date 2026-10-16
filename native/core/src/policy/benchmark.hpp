// Device micro-benchmark (ADR-0017, 05 §6.2): compact SR on a 128 px tile per backend, timed
// (1 warm-up + N runs, median) and, for GPU backends, checked against the CPU output with the
// GPU gate (no NaN/Inf, PSNR >= 35 dB, bad_frac <= 0.1%). The fastest healthy backend and the
// device RAM give the tier (05 §6.3, suggest_tier). JSON in and out (enh_benchmark).
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <nlohmann/json.hpp>

struct enh_session;

namespace enh {

// opts: {"model": "sr.general-x4v3", "runs": 5, "ram_bytes": <platform total RAM>}.
// Result: {"schema": 1, "model", "backends": [{"name", "kind", "fp16", "status": ok |
// wrong_output | error | blocked, "tile128_ms", "psnr", "bad_frac"}], "selected", "tier",
// "reasons": [...], "below_t0_budget"}.
nlohmann::json run_benchmark(enh_session& s, const nlohmann::json& opts);

}  // namespace enh
