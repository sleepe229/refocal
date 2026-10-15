// libenh: C ABI entry points (include/enh.h).
// Jobs live in job/job.cpp, export in job/export.cpp. Benchmark/analyze and the integrity
// functions are 0.2 and still return ENH_E_INTERNAL.
// SPDX-License-Identifier: Apache-2.0
#include "enh.h"

#include <cstddef>
#include <cstdlib>
#include <cstring>
#include <new>
#include <string>
#include <vector>

#include "job/session.hpp"
#include "json_util.hpp"
#include "policy/analyze.hpp"
#include "policy/benchmark.hpp"
#include "probe.hpp"
#include "util/error.hpp"
#include "util/fs.hpp"
#include "util/integrity.hpp"
#include "util/log.hpp"

#ifndef ENH_VERSION_STRING
#define ENH_VERSION_STRING "0.0.0"
#endif

namespace {

std::string opt(const char* s) { return s ? s : ""; }

enh_status put_json(const std::string& j, char** out) {
  if (!out) return ENH_E_INVALID;
  *out = enh::heap_copy(j);
  return *out ? ENH_OK : ENH_E_OOM;
}

}  // namespace

extern "C" {

const char* enh_version(void) { return ENH_VERSION_STRING; }
int32_t enh_abi_version(void) { return ENH_ABI_VERSION; }
void enh_free(void* p) { std::free(p); }

enh_status enh_session_create(const enh_session_config* cfg, enh_session** out) {
  if (!cfg || !out) return ENH_E_INVALID;
  // Older callers may pass a smaller struct; never read past struct_size.
  if (cfg->struct_size < offsetof(enh_session_config, tier) + sizeof(cfg->tier))
    return ENH_E_INVALID;
  auto* s = new (std::nothrow) enh_session();
  if (!s) return ENH_E_OOM;
  s->models_dir = opt(cfg->models_dir);
  s->work_dir = opt(cfg->work_dir);
  s->cache_dir = opt(cfg->cache_dir);
  s->backend_pref = cfg->backend_pref;
  s->mem_budget_bytes = cfg->mem_budget_bytes;
  s->cpu_threads = cfg->cpu_threads;
  s->blocklist_json = opt(cfg->blocklist_json);
  s->tier = opt(cfg->tier);
  s->tier_level = s->tier == "T2" ? 2 : s->tier == "T1" ? 1 : 0;
  // Fields appended after ABI 1.0 are read only when the caller's struct has them.
  const char* prev_exit =
      cfg->struct_size >= offsetof(enh_session_config, previous_exit) + sizeof(void*)
          ? cfg->previous_exit
          : nullptr;
  // GPU policy (S3, ADR-0016): built-in + manifest rules, then the crash sentinel.
  s->blocklist.add(enh::parse_blocklist(enh::builtin_blocklist_json(), "builtin"));
  if (!s->blocklist_json.empty())
    s->blocklist.add(enh::parse_blocklist(s->blocklist_json, "manifest"));
  if (!s->cache_dir.empty()) {
    try {
      std::string dir = enh::fs::join(s->cache_dir, "gpu");
      enh::fs::mkdirs(dir);
      s->sentinel = std::make_unique<enh::SentinelStore>(dir);
      s->startup = s->sentinel->on_startup(enh::parse_exit_reason(opt(prev_exit)));
      s->blocklist.add(s->sentinel->local_rules());
      if (s->startup.sentinel_found) {
        ENH_LOGW("crash sentinel: %s (%s)", s->startup.key.c_str(), s->startup.note.c_str());
      }
    } catch (const std::exception& e) {
      ENH_LOGW("crash sentinel disabled: %s", e.what());
      s->sentinel.reset();
    }
  }
  *out = s;
  return ENH_OK;
}

void enh_session_destroy(enh_session* s) { delete s; }

enh_status enh_device_probe(enh_session* s, char** out_json) {
  if (!s) return ENH_E_INVALID;
  std::string j = enh::device_probe_json();
  // Append the GPU policy state: what the last crash sentinel decided and rule counts.
  const auto& r = s->startup;
  std::string pol = ",\"gpu_policy\":{\"rules\":" + std::to_string(s->blocklist.rules().size()) +
                    ",\"rule_errors\":" + std::to_string(s->blocklist.errors().size()) +
                    ",\"sentinel\":" + (s->sentinel ? "true" : "false") +
                    ",\"sentinel_found\":" + (r.sentinel_found ? "true" : "false") +
                    ",\"blocked_now\":" + (r.blocked_now ? "true" : "false") +
                    ",\"quarantined_now\":" + (r.quarantined_now ? "true" : "false") + ",\"key\":";
  enh::json_str(pol, r.key);
  pol += "}";
  j.insert(j.size() - 1, pol);
  return put_json(j, out_json);
}

enh_status enh_benchmark(enh_session* s, const char* opts_json, char** out_json) {
  if (!s || !out_json) return ENH_E_INVALID;
  try {
    const auto opts = nlohmann::json::parse(opts_json ? opts_json : "{}", nullptr, false);
    if (opts.is_discarded() || !opts.is_object()) return ENH_E_INVALID;
    return put_json(enh::run_benchmark(*s, opts).dump(), out_json);
  } catch (const enh::Error& e) {
    return e.status();
  } catch (const std::exception&) {
    return ENH_E_INTERNAL;
  }
}
enh_status enh_analyze(enh_session* s, const char* input_path, char** out_json) {
  if (!s || !input_path || !out_json) return ENH_E_INVALID;
  try {
    return put_json(enh::analyze_image(*s, input_path).dump(), out_json);
  } catch (const enh::Error& e) {
    return e.status();
  } catch (const std::exception&) {
    return ENH_E_INTERNAL;
  }
}

void enh_set_tier(enh_session* s, int32_t tier) {
  if (s && tier >= 0 && tier <= 2) s->tier_level = tier;
}

void enh_set_memory_pressure(enh_session* s, int32_t level) {
  if (s) s->memory_pressure = level;
}
void enh_set_gpu_allowed(enh_session* s, int32_t allowed) {
  if (s) s->gpu_allowed = allowed ? 1 : 0;
}
void enh_set_thermal(enh_session* s, int32_t level) {
  if (s) s->thermal = level;
}

enh_status enh_verify_file(const char* path, const char* sha256_hex) {
  if (!path || !sha256_hex) return ENH_E_INVALID;
  try {
    enh::verify_file_sha256(path, sha256_hex);
    return ENH_OK;
  } catch (const enh::Error& e) {
    return e.status();
  }
}

enh_status enh_verify_minisign(const char* msg_path, const char* sig_path,
                               const char* pubkeys_csv) {
  if (!msg_path || !sig_path || !pubkeys_csv) return ENH_E_INVALID;
  try {
    std::vector<enh::MinisignKey> keys;
    std::string csv = pubkeys_csv;
    for (size_t i = 0; i <= csv.size();) {
      size_t j = csv.find(',', i);
      if (j == std::string::npos) j = csv.size();
      if (j > i) keys.push_back(enh::parse_minisign_key(csv.substr(i, j - i)));
      i = j + 1;
    }
    if (keys.empty()) return ENH_E_INVALID;
    enh::verify_minisign(msg_path, enh::fs::read_text(sig_path), keys);
    return ENH_OK;
  } catch (const enh::Error& e) {
    return e.status();
  } catch (const std::exception&) {
    return ENH_E_INTERNAL;
  }
}

}  // extern "C"
