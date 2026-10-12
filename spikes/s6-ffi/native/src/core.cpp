// S6 mock native core: job part of enh.h with a real prep -> infer -> post pipeline
// (bounded queues of depth 2, ADR-0006) and simulated work. See enh_debug.h for the request format.
// SPDX-License-Identifier: Apache-2.0
#include "enh_debug.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <time.h>

#ifdef ENH_WITH_DART_PORT
#include "dart_api_dl.h"
#endif

namespace {

std::atomic<int64_t> g_live_payloads{0};
std::atomic<int64_t> g_live_jobs{0};
std::atomic<int64_t> g_live_threads{0};

int64_t now_ns() {
  timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return int64_t(ts.tv_sec) * 1000000000 + ts.tv_nsec;
}

void sleep_us(int64_t us) {
  if (us > 0) std::this_thread::sleep_for(std::chrono::microseconds(us));
}

char* dup_counted(const std::string& s) {
  char* p = static_cast<char*>(std::malloc(s.size() + 1));
  if (!p) return nullptr;
  std::memcpy(p, s.data(), s.size() + 1);
  g_live_payloads.fetch_add(1, std::memory_order_relaxed);
  return p;
}

// Minimal "parser": request JSON is flat {"key":int,...}; good enough for a mock.
int64_t get_int(const char* json, const char* key, int64_t def) {
  std::string needle = std::string("\"") + key + "\"";
  const char* p = std::strstr(json, needle.c_str());
  if (!p) return def;
  p = std::strchr(p + needle.size(), ':');
  if (!p) return def;
  return std::strtoll(p + 1, nullptr, 10);
}

// Bounded FIFO with close(); pop() returns nullopt once closed and drained.
class BoundedQueue {
 public:
  explicit BoundedQueue(size_t cap) : cap_(cap) {}
  bool push(int v) {
    std::unique_lock lk(mu_);
    cv_.wait(lk, [&] { return closed_ || q_.size() < cap_; });
    if (closed_) return false;
    q_.push_back(v);
    cv_.notify_all();
    return true;
  }
  std::optional<int> pop() {
    std::unique_lock lk(mu_);
    cv_.wait(lk, [&] { return closed_ || !q_.empty(); });
    if (q_.empty()) return std::nullopt;
    int v = q_.front();
    q_.pop_front();
    cv_.notify_all();
    return v;
  }
  void close() {
    std::lock_guard lk(mu_);
    closed_ = true;
    cv_.notify_all();
  }

 private:
  std::mutex mu_;
  std::condition_variable cv_;
  std::deque<int> q_;
  size_t cap_;
  bool closed_ = false;
};

struct Params {
  int64_t tiles, events_per_tile, prep_us, infer_us, post_us, payload_bytes, progress_min_us,
      needs_user_at, fail_at, bad_utf8;
};

}  // namespace

struct enh_session {
  int64_t mem_budget;
};

struct enh_job {
  Params p{};
  std::atomic<bool> started{false};
  std::atomic<bool> cancel{false}, pause{false}, failed{false};
  std::atomic<int32_t> status{-1};

  std::mutex cb_mu;  // held while invoking cb, so set_callback() is a hard barrier
  enh_event_cb cb = nullptr;
  int64_t port = 0;  // Dart native port (variant B); 0 = ILLEGAL_PORT
  int64_t token = 0;

  std::mutex nu_mu;
  std::condition_variable nu_cv;
  bool answered = false;

  BoundedQueue q1{2}, q2{2};
  std::thread runner;

  std::atomic<int64_t> emitted{0}, coalesced{0}, dropped{0}, cb_ns_total{0}, cb_ns_max{0};
  std::atomic<int64_t> cancel_ns{0}, terminal_ns{0}, tiles_done{0}, tiles_after_cancel{0};
  int64_t last_progress_ns = 0;  // post thread only

  bool stop() const {
    return cancel.load(std::memory_order_acquire) || pause.load(std::memory_order_acquire) ||
           failed.load(std::memory_order_acquire);
  }

  void emit(int32_t type, int32_t stage, int64_t done, int64_t total, const std::string& payload) {
    std::lock_guard lk(cb_mu);
    int64_t t0 = now_ns();
#ifdef ENH_WITH_DART_PORT
    if (port) {
      // Variant B: the VM copies the message into the receiving isolate; the payload never
      // crosses the boundary as a pointer, so there is nothing for Dart to free. Posting to a
      // closed port (ReceivePort.close, isolate killed, hot restart) just returns false.
      Dart_CObject v[6];
      Dart_CObject* items[6];
      int64_t ints[5] = {token, type, stage, done, total};
      for (int k = 0; k < 5; ++k) {
        v[k].type = Dart_CObject_kInt64;
        v[k].value.as_int64 = ints[k];
        items[k] = &v[k];
      }
      v[5].type = Dart_CObject_kString;
      v[5].value.as_string = const_cast<char*>(payload.c_str());
      items[5] = &v[5];
      Dart_CObject msg;
      msg.type = Dart_CObject_kArray;
      msg.value.as_array.length = 6;
      msg.value.as_array.values = items;
      if (!Dart_PostCObject_DL(port, &msg)) dropped.fetch_add(1, std::memory_order_relaxed);
      account(now_ns() - t0);
      return;
    }
#endif
    if (!cb) {  // detached: nobody to hand the payload to
      dropped.fetch_add(1, std::memory_order_relaxed);
      return;
    }
    char* p = dup_counted(payload);
    cb(token, type, stage, done, total, p);
    account(now_ns() - t0);
  }

  void account(int64_t dt) {
    emitted.fetch_add(1, std::memory_order_relaxed);
    cb_ns_total.fetch_add(dt, std::memory_order_relaxed);
    int64_t m = cb_ns_max.load(std::memory_order_relaxed);
    while (dt > m && !cb_ns_max.compare_exchange_weak(m, dt)) {
    }
  }

  void request_stop() {
    int64_t zero = 0;
    cancel_ns.compare_exchange_strong(zero, now_ns());
    q1.close();
    q2.close();
    std::lock_guard lk(nu_mu);
    nu_cv.notify_all();
  }

  void run() {
    g_live_threads.fetch_add(1);
    std::thread infer([this] {
      g_live_threads.fetch_add(1);
      while (auto t = q1.pop()) {
        if (stop()) break;
        sleep_us(p.infer_us);  // a GPU dispatch cannot be interrupted mid-tile
        if (*t == p.fail_at) {
          failed.store(true, std::memory_order_release);
          request_stop();
          break;
        }
        if (!q2.push(*t)) break;
      }
      q2.close();
      g_live_threads.fetch_sub(1);
    });
    std::thread post([this] {
      g_live_threads.fetch_add(1);
      emit(ENH_EV_STAGE, 1, 0, p.tiles,
           p.bad_utf8 ? "{\"stage\":\"up\xff\xfescale\"}" : "{\"stage\":\"upscale\"}");
      while (auto t = q2.pop()) {
        if (stop()) break;
        sleep_us(p.post_us);
        int64_t done = *t + 1;
        tiles_done.store(done, std::memory_order_release);
        if (cancel_ns.load(std::memory_order_acquire)) tiles_after_cancel.fetch_add(1);
        for (int64_t e = 0; e < p.events_per_tile; ++e) {
          int64_t now = now_ns();
          bool last = done == p.tiles && e + 1 == p.events_per_tile;
          if (p.progress_min_us > 0 && !last &&
              now - last_progress_ns < p.progress_min_us * 1000) {
            coalesced.fetch_add(1, std::memory_order_relaxed);
            continue;
          }
          last_progress_ns = now;
          std::string payload = "{\"t_ns\":" + std::to_string(now) +
                                ",\"seq\":" + std::to_string(*t * p.events_per_tile + e);
          if (p.payload_bytes > 0) payload += ",\"pad\":\"" + std::string(p.payload_bytes, 'x') + "\"";
          payload += "}";
          emit(ENH_EV_PROGRESS, 1, done, p.tiles, payload);
        }
      }
      g_live_threads.fetch_sub(1);
    });

    for (int64_t i = 0; i < p.tiles; ++i) {
      if (stop()) break;
      if (i == p.needs_user_at) {
        emit(ENH_EV_NEEDS_USER, 0, i, p.tiles,
             "{\"code\":\"downscale_required\",\"options\":[\"2x\",\"faces_only\"]}");
        std::unique_lock lk(nu_mu);
        nu_cv.wait(lk, [&] { return answered || stop(); });
        if (stop()) break;
      }
      sleep_us(p.prep_us);
      if (!q1.push(int(i))) break;
    }
    q1.close();
    infer.join();
    post.join();

    int64_t done = tiles_done.load();
    terminal_ns.store(now_ns());
    if (done == p.tiles) {
      status.store(ENH_OK);
      emit(ENH_EV_DONE, 0, done, p.tiles, "{\"schema\":1,\"tiles\":" + std::to_string(done) + "}");
    } else {
      int32_t st = failed ? ENH_E_BACKEND : cancel ? ENH_E_CANCELLED : ENH_E_PAUSED;
      status.store(st);
      emit(ENH_EV_ERROR, 0, done, p.tiles,
           "{\"status\":" + std::to_string(st) + ",\"done\":" + std::to_string(done) + "}");
    }
    g_live_threads.fetch_sub(1);
  }
};

extern "C" {

const char* enh_version(void) { return "0.0.0-s6-mock"; }
int32_t enh_abi_version(void) { return ENH_ABI_VERSION; }

void enh_free(void* p) {
  if (!p) return;
  std::free(p);
  g_live_payloads.fetch_sub(1, std::memory_order_relaxed);
}

enh_status enh_session_create(const enh_session_config* cfg, enh_session** out) {
  if (!out) return ENH_E_INVALID;
  if (cfg && cfg->struct_size < sizeof(uint32_t)) return ENH_E_INVALID;
  *out = new enh_session{cfg && cfg->struct_size >= sizeof(enh_session_config) ? cfg->mem_budget_bytes : 0};
  return ENH_OK;
}

void enh_session_destroy(enh_session* s) { delete s; }

enh_status enh_job_create(enh_session* s, const char* req, enh_job** out) {
  if (!s || !req || !out) return ENH_E_INVALID;
  auto* j = new enh_job();
  j->p = Params{get_int(req, "tiles", 100),     get_int(req, "events_per_tile", 1),
                get_int(req, "prep_us", 0),     get_int(req, "infer_us", 1000),
                get_int(req, "post_us", 0),     get_int(req, "payload_bytes", 0),
                get_int(req, "progress_min_us", 0), get_int(req, "needs_user_at", -1),
                get_int(req, "fail_at", -1), get_int(req, "bad_utf8", 0)};
  if (j->p.tiles <= 0 || j->p.events_per_tile < 0) {
    delete j;
    return ENH_E_INVALID;
  }
  g_live_jobs.fetch_add(1);
  *out = j;
  return ENH_OK;
}

static enh_status start_impl(enh_job* j, enh_event_cb cb, int64_t port, int64_t token) {
  if (!j || (!cb && !port)) return ENH_E_INVALID;
  bool expected = false;
  if (!j->started.compare_exchange_strong(expected, true)) return ENH_E_INVALID;
  {
    std::lock_guard lk(j->cb_mu);
    j->cb = cb;
    j->port = port;
    j->token = token;
  }
  j->runner = std::thread([j] { j->run(); });
  return ENH_OK;
}

enh_status enh_job_start(enh_job* j, enh_event_cb cb, int64_t token) {
  return start_impl(j, cb, 0, token);
}

enh_status enh_job_answer(enh_job* j, const char* answer_json) {
  if (!j || !answer_json) return ENH_E_INVALID;
  std::lock_guard lk(j->nu_mu);
  j->answered = true;
  j->nu_cv.notify_all();
  return ENH_OK;
}

void enh_job_cancel(enh_job* j) {
  if (!j) return;
  j->cancel.store(true, std::memory_order_release);
  j->request_stop();
}

void enh_job_pause(enh_job* j) {
  if (!j) return;
  j->pause.store(true, std::memory_order_release);
  j->request_stop();
}

// Blocks until the worker has stopped: after return no callback for this job will ever run.
void enh_job_destroy(enh_job* j) {
  if (!j) return;
  enh_job_cancel(j);
  if (j->runner.joinable()) j->runner.join();
  delete j;
  g_live_jobs.fetch_sub(1);
}

enh_status enh_job_set_callback(enh_job* j, enh_event_cb cb, int64_t token) {
  if (!j) return ENH_E_INVALID;
  std::lock_guard lk(j->cb_mu);
  j->cb = cb;
  j->port = 0;
  j->token = token;
  return ENH_OK;
}

#ifdef ENH_WITH_DART_PORT
intptr_t enh_dart_init(void* api_dl_data) { return Dart_InitializeApiDL(api_dl_data); }

enh_status enh_job_start_port(enh_job* j, int64_t port, int64_t token) {
  return port ? start_impl(j, nullptr, port, token) : ENH_E_INVALID;
}

enh_status enh_job_set_port(enh_job* j, int64_t port, int64_t token) {
  if (!j) return ENH_E_INVALID;
  std::lock_guard lk(j->cb_mu);
  j->cb = nullptr;
  j->port = port;
  j->token = token;
  return ENH_OK;
}
#endif

int32_t enh_job_status(enh_job* j) { return j ? j->status.load() : ENH_E_INVALID; }

int64_t enh_debug_now_ns(void) { return now_ns(); }
int64_t enh_debug_live_payloads(void) { return g_live_payloads.load(); }
int64_t enh_debug_live_jobs(void) { return g_live_jobs.load(); }
int64_t enh_debug_live_threads(void) { return g_live_threads.load(); }

enh_status enh_debug_job_stats(enh_job* j, char** out) {
  if (!j || !out) return ENH_E_INVALID;
  char buf[512];
  std::snprintf(buf, sizeof buf,
                "{\"emitted\":%lld,\"coalesced\":%lld,\"dropped\":%lld,\"cb_ns_total\":%lld,\"cb_ns_max\":%lld,"
                "\"cancel_ns\":%lld,\"terminal_ns\":%lld,\"tiles_done\":%lld,"
                "\"tiles_after_cancel\":%lld}",
                (long long)j->emitted.load(), (long long)j->coalesced.load(), (long long)j->dropped.load(),
                (long long)j->cb_ns_total.load(), (long long)j->cb_ns_max.load(),
                (long long)j->cancel_ns.load(), (long long)j->terminal_ns.load(),
                (long long)j->tiles_done.load(), (long long)j->tiles_after_cancel.load());
  *out = dup_counted(buf);
  return *out ? ENH_OK : ENH_E_OOM;
}

}  // extern "C"
