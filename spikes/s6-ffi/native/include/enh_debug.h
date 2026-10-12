/*
 * enh_debug.h — S6 spike test hooks (mock core only). The ABI additions found by S6
 * (enh_dart_init, enh_job_start_port/set_port/set_callback, enh_job_status) live in enh.h.
 *
 * The mock implements the job part of enh.h with a real 3-stage pipeline
 * (prep -> infer -> post, queues of depth 2, ADR-0006) but simulated work (sleeps).
 * Request JSON fields (all optional, integers):
 *   tiles             number of tiles                          (default 100)
 *   events_per_tile   PROGRESS events emitted per tile by post (default 1)
 *   prep_us/infer_us/post_us  simulated stage time per tile     (default 0/1000/0)
 *   payload_bytes     extra padding in each PROGRESS payload   (default 0)
 *   progress_min_us   coalesce PROGRESS events closer than this (default 0 = off)
 *   needs_user_at     tile index before which NEEDS_USER is raised (default -1)
 *   fail_at           tile index at which the job fails with ENH_E_BACKEND (default -1)
 *   bad_utf8          1 = STAGE payload contains invalid UTF-8 (default 0)
 *
 * SPDX-License-Identifier: Apache-2.0
 */
#ifndef ENH_DEBUG_H
#define ENH_DEBUG_H

#include "enh.h"

#ifdef __cplusplus
extern "C" {
#endif

/* CLOCK_MONOTONIC in ns: lets Dart compute native->Dart delivery latency on the same clock. */
int64_t enh_debug_now_ns(void);

/* Payloads handed to callbacks minus payloads released with enh_free(). 0 == no leak. */
int64_t enh_debug_live_payloads(void);
/* Live enh_job objects (created minus destroyed) and running worker threads. */
int64_t enh_debug_live_jobs(void);
int64_t enh_debug_live_threads(void);

/* Per-job counters as JSON (caller frees with enh_free):
 * {"emitted":N,"coalesced":N,"dropped":N,"cb_ns_total":N,"cb_ns_max":N,"cancel_ns":T,"terminal_ns":T,
 *  "tiles_done":N,"tiles_after_cancel":N} */
enh_status enh_debug_job_stats(enh_job* j, char** out_json);

#ifdef __cplusplus
}
#endif
#endif /* ENH_DEBUG_H */
