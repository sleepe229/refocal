// libenh: C ABI entry points (include/enh.h).
// Skeleton (M0): library, session and device probe are real; the job pipeline, export and
// integrity functions return ENH_E_INTERNAL until they land in 0.1 (see docs/spec/13).
// SPDX-License-Identifier: Apache-2.0
#include "enh.h"

#include <cstdlib>
#include <cstring>
#include <new>
#include <string>

#include "json_util.hpp"
#include "probe.hpp"

#ifndef ENH_VERSION_STRING
#define ENH_VERSION_STRING "0.0.0"
#endif

struct enh_session {
  std::string models_dir, work_dir, cache_dir, tier, blocklist_json;
  int32_t backend_pref = ENH_BACKEND_AUTO;
  int64_t mem_budget_bytes = 0;
  int32_t cpu_threads = 0;
};

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

intptr_t enh_dart_init(void*) { return -1; }  // 0.1: Dart_InitializeApiDL (ADR-0005)

enh_status enh_session_create(const enh_session_config* cfg, enh_session** out) {
  if (!cfg || !out) return ENH_E_INVALID;
  // Older callers may pass a smaller struct; never read past struct_size.
  if (cfg->struct_size < offsetof(enh_session_config, tier) + sizeof(cfg->tier)) return ENH_E_INVALID;
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
  *out = s;
  return ENH_OK;
}

void enh_session_destroy(enh_session* s) { delete s; }

enh_status enh_device_probe(enh_session* s, char** out_json) {
  if (!s) return ENH_E_INVALID;
  return put_json(enh::device_probe_json(), out_json);
}

enh_status enh_benchmark(enh_session*, const char*, char**) { return ENH_E_INTERNAL; }
enh_status enh_analyze(enh_session*, const char*, char**) { return ENH_E_INTERNAL; }

void enh_set_memory_pressure(enh_session*, int32_t) {}
void enh_set_gpu_allowed(enh_session*, int32_t) {}
void enh_set_thermal(enh_session*, int32_t) {}

enh_status enh_job_create(enh_session*, const char*, enh_job**) { return ENH_E_INTERNAL; }
enh_status enh_job_resume(enh_session*, const char*, enh_job**) { return ENH_E_INTERNAL; }
enh_status enh_job_start(enh_job*, enh_event_cb, int64_t) { return ENH_E_INTERNAL; }
enh_status enh_job_start_port(enh_job*, int64_t, int64_t) { return ENH_E_INTERNAL; }
enh_status enh_job_set_port(enh_job*, int64_t, int64_t) { return ENH_E_INTERNAL; }
enh_status enh_job_set_callback(enh_job*, enh_event_cb, int64_t) { return ENH_E_INTERNAL; }
enh_status enh_job_answer(enh_job*, const char*) { return ENH_E_INTERNAL; }
void enh_job_pause(enh_job*) {}
void enh_job_cancel(enh_job*) {}
int32_t enh_job_status(enh_job*) { return ENH_E_INVALID; }
void enh_job_destroy(enh_job*) {}

enh_status enh_export(enh_session*, const char*, const char*, const char*, char**) {
  return ENH_E_INTERNAL;
}
enh_status enh_verify_file(const char*, const char*) { return ENH_E_INTERNAL; }
enh_status enh_verify_minisign(const char*, const char*, const char*) { return ENH_E_INTERNAL; }

}  // extern "C"
