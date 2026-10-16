// Session state shared by jobs.
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>

#include "enh.h"
#include "policy/blocklist.hpp"
#include "policy/sentinel.hpp"

struct enh_session {
  std::string models_dir, work_dir, cache_dir, tier, blocklist_json;
  int32_t backend_pref = ENH_BACKEND_AUTO;
  int64_t mem_budget_bytes = 0;
  int32_t cpu_threads = 0;

  // Runtime signals from the platform layer.
  std::atomic<int32_t> memory_pressure{0};
  // Memory warnings so far: enh_set_memory_pressure calls at level >= 2 (NFR-MEM-004).
  std::atomic<uint32_t> memory_warnings{0};
  std::atomic<int32_t> thermal{0};
  std::atomic<int32_t> gpu_allowed{1};
  // Device tier (ADR-0017): 0 T0, 1 T1, 2 T2; from the config, then enh_set_tier (benchmark).
  std::atomic<int32_t> tier_level{0};

  // One running job at a time (ADR-0006); later jobs wait in STAGE "queued".
  std::timed_mutex run_mu;

  // GPU policy (S3): built-in + manifest blocklist + local rules from the crash sentinel.
  enh::Blocklist blocklist;
  std::unique_ptr<enh::SentinelStore> sentinel;  // null without cache_dir
  enh::StartupReport startup;
};
