/*
 * enh.h — public C ABI of the Refocal native core (reference version for the spec).
 * Source of truth: native/include/enh.h (docs/spec/appendix/enh.h is kept identical, checked in CI).
 *
 * Conventions:
 *  - All strings are UTF-8, NUL-terminated.
 *  - Strings/buffers returned by the core through char** out_json are heap-allocated and MUST be
 *    released with enh_free(). Event payloads delivered to a Dart port are copied by the VM
 *    (nothing to free); payloads passed to an enh_event_cb are owned by the receiver -> enh_free().
 *  - All strings (requests, results, events) are valid UTF-8; the core replaces invalid bytes
 *    (e.g. from file paths) with U+FFFD, because the Dart VM rejects such messages.
 *  - Structs carry struct_size for forward compatibility.
 *  - Complex parameters/results are JSON with a "schema" field (current: 1).
 *  - All functions except enh_job_start() return quickly; heavy work runs on the core worker thread.
 *  - Thread-safety: enh_session_* and enh_job_* may be called from any thread;
 *    enh_job_cancel/pause and enh_set_* are non-blocking (never wait for the worker, O(1)).
 *  - Status codes are int32_t, not an enum type: enum size is implementation-defined across the
 *    FFI boundary, and newer cores may return codes unknown to older bindings (treat as INTERNAL).
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#ifndef ENH_H
#define ENH_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(__GNUC__) || defined(__clang__)
#pragma GCC visibility push(default) /* the core is built with -fvisibility=hidden */
#endif

#define ENH_ABI_VERSION 2

typedef struct enh_session enh_session;
typedef struct enh_job enh_job;

typedef int32_t enh_status;
enum {
  ENH_OK = 0,
  ENH_E_CANCELLED = 1,
  ENH_E_PAUSED = 2,
  ENH_E_OOM = 3,
  ENH_E_BACKEND = 4,
  ENH_E_DEVICE_LOST = 5,
  ENH_E_IO = 6,
  ENH_E_DISK_FULL = 7,
  ENH_E_MODEL = 8,      /* missing/corrupted/unsupported model */
  ENH_E_INVALID = 9,    /* invalid argument / request JSON */
  ENH_E_NUMERIC = 10,   /* NaN/Inf in model output */
  ENH_E_SIGNATURE = 11, /* signature/hash verification failed */
  ENH_E_LIMIT = 12,     /* input exceeds size limits */
  ENH_E_INTERNAL = 99
};

typedef enum {
  ENH_BACKEND_AUTO = 0,
  ENH_BACKEND_NCNN_VULKAN = 1,
  ENH_BACKEND_NCNN_CPU = 2,
  ENH_BACKEND_COREML = 3,
  ENH_BACKEND_ORT_QNN = 4
} enh_backend;

typedef struct {
  uint32_t struct_size;       /* = sizeof(enh_session_config) */
  const char* models_dir;     /* AppSupport/models */
  const char* work_dir;       /* AppSupport/jobs */
  const char* cache_dir;      /* compiled models, pipeline caches */
  int32_t backend_pref;       /* enh_backend */
  int64_t mem_budget_bytes;   /* 0 = auto (tier cap & OS available) */
  int32_t cpu_threads;        /* 0 = auto */
  const char* blocklist_json; /* merged GPU blocklist, may be NULL */
  const char* tier;           /* "T0" | "T1" | "T2" | NULL (auto) */
  /* How the previous process ended (crash sentinel, ADR-0016): "native_crash" (Android
   * ApplicationExitInfo REASON_CRASH_NATIVE/ANR), "os_kill" (LMK, user swipe) or NULL (unknown,
   * e.g. iOS). Added after ABI 1.0 — read only when struct_size covers it. */
  const char* previous_exit;
} enh_session_config;

typedef enum {
  ENH_EV_STAGE = 1,      /* payload: {"stage":"restore_faces"} */
  ENH_EV_PROGRESS = 2,   /* done/total in tiles; payload: {"eta_ms":1234} */
  ENH_EV_FALLBACK = 3,   /* payload: {"from":"vulkan","to":"cpu","reason":"device_lost"} */
  ENH_EV_WARNING = 4,    /* payload: {"code":"face_skipped","face":2} */
  ENH_EV_NEEDS_USER = 5, /* payload: {"code":"downscale_required","options":["2x","faces_only"]} */
  ENH_EV_DONE = 6,       /* payload: result bundle JSON */
  ENH_EV_ERROR = 7       /* payload: {"status":3,"message":"..."} */
} enh_event_type;

/*
 * Event callback for C/C++ consumers (refocal-cli, tests). Invoked from core threads while the
 * job's sink lock is held: it must not block and must not call back into this job.
 * payload_json is owned by the receiver -> enh_free().
 * Dart does NOT use this (a NativeCallable called after its isolate died aborts the process,
 * S6); Dart uses enh_job_start_port().
 *
 * Event order per job: STAGE/PROGRESS/... then exactly one terminal event (DONE or ERROR);
 * nothing after it. PROGRESS is coalesced to <= 30 Hz.
 */
typedef void (*enh_event_cb)(int64_t job_token, int32_t type, int32_t stage, int64_t done,
                             int64_t total, char* payload_json);

/* ---- library ---- */
const char* enh_version(void); /* static string, do not free */
int32_t enh_abi_version(void); /* == ENH_ABI_VERSION */
void enh_free(void* p);

/* ---- log (PRIV-LOG-001/002) ----
 * The core and the app write one log: logcat/stderr, and a file once enh_log_open() was called.
 * Photo paths and URIs are replaced by "<path>" / "<uri>" before a line is written anywhere.
 * The file rotates to "<path>.1" when it would exceed max_bytes (each file <= max_bytes). */
enum { ENH_LOG_DEBUG = 0, ENH_LOG_INFO = 1, ENH_LOG_WARN = 2, ENH_LOG_ERROR = 3 };
enh_status enh_log_open(const char* path, int64_t max_bytes);
void enh_log_write(int32_t level, const char* message); /* below the minimum level: dropped */
void enh_log_set_level(int32_t min_level);              /* default ENH_LOG_INFO */

/* Dart integration: pass NativeApi.initializeApiDLData once per process; returns 0 on success. */
intptr_t enh_dart_init(void* api_dl_data);

/* ---- session ---- */
enh_status enh_session_create(const enh_session_config* cfg, enh_session** out);
void enh_session_destroy(enh_session* s);

enh_status enh_device_probe(enh_session* s, char** out_json);
enh_status enh_benchmark(enh_session* s, const char* opts_json, char** out_json);
enh_status enh_analyze(enh_session* s, const char* input_path, char** out_json);

/* Runtime signals from the platform layer */
void enh_set_memory_pressure(enh_session* s, int32_t level); /* 0 none .. 3 critical */
void enh_set_gpu_allowed(enh_session* s, int32_t allowed);   /* iOS lifecycle gate */
/* Thermal level (NFR-THERM-002): 0 nominal, 1 light, 2 fair, 3 serious, 4 critical (Android
 * PowerManager NONE/LIGHT/MODERATE/SEVERE/CRITICAL+; iOS nominal 0, fair 2, serious 3, critical 4).
 * serious: a pause between tiles and half the CPU threads; critical: the job waits before its next
 * tile until the level is fair or lower (WARNING "thermal_wait", then "thermal_resumed"). */
void enh_set_thermal(enh_session* s, int32_t level);

/* ---- jobs ---- */
enh_status enh_job_create(enh_session* s, const char* request_json, enh_job** out);
enh_status enh_job_resume(enh_session* s, const char* job_dir, enh_job** out);
enh_status enh_job_start(enh_job* j, enh_event_cb cb, int64_t job_token); /* async */
/* Dart: events are posted (Dart_PostCObject) to dart_port as
 * [job_token, type, stage, done, total, payload_json]. Posting to a closed port is a no-op. */
enh_status enh_job_start_port(enh_job* j, int64_t dart_port, int64_t job_token); /* async */
/* Re-attach a running job to a new sink (e.g. after the Flutter engine was recreated).
 * Once these return, the previous sink never receives another event of this job. */
enh_status enh_job_set_port(enh_job* j, int64_t dart_port, int64_t job_token);
enh_status enh_job_set_callback(enh_job* j, enh_event_cb cb, int64_t job_token);
enh_status enh_job_answer(enh_job* j, const char* answer_json); /* reply to NEEDS_USER */
void enh_job_pause(enh_job* j);     /* terminal ERROR {status: ENH_E_PAUSED, done: N} follows */
void enh_job_cancel(enh_job* j);    /* terminal ERROR {status: ENH_E_CANCELLED} within <= 1 tile */
int32_t enh_job_status(enh_job* j); /* terminal status, or -1 while running */
/* Blocks until the worker has stopped (up to one tile on a running job). Call it after the
 * terminal event; never on the UI thread for a running job. */
void enh_job_destroy(enh_job* j);

/* ---- export ---- */
enh_status enh_export(enh_session* s, const char* job_dir, const char* output_json,
                      const char* dst_path, char** out_json);

/* ---- integrity ---- */
enh_status enh_verify_file(const char* path, const char* sha256_hex);
enh_status enh_verify_minisign(const char* msg_path, const char* sig_path, const char* pubkeys_csv);

#if defined(__GNUC__) || defined(__clang__)
#pragma GCC visibility pop
#endif

#ifdef __cplusplus
}
#endif
#endif /* ENH_H */
