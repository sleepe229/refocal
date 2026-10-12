// Native-only stress for TSan / ASan+LSan / UBSan: emulates NativeCallable.listener (callback only
// enqueues; a separate "Dart" thread consumes and enh_free()s) and races cancel/pause/answer/
// set_callback/destroy against running pipelines. Exits non-zero on any invariant violation.
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
#include <random>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

namespace {

struct Ev {
  int64_t token;
  int32_t type;
  int64_t done;
  char* payload;
};

std::mutex g_mu;
std::condition_variable g_cv;
std::deque<Ev> g_q;
bool g_quit = false;

void listener(int64_t token, int32_t type, int32_t, int64_t done, int64_t, char* payload) {
  std::lock_guard lk(g_mu);
  g_q.push_back({token, type, done, payload});
  g_cv.notify_one();
}

struct TokenState {
  int terminals = 0;
  int after_terminal = 0;
  int64_t last_done = -1;
  int non_monotonic = 0;
};

int fails = 0;
#define CHECK(c, ...)                         \
  do {                                        \
    if (!(c)) {                               \
      std::fprintf(stderr, "FAIL: " __VA_ARGS__); \
      std::fputc('\n', stderr);               \
      ++fails;                                \
    }                                         \
  } while (0)

}  // namespace

int main(int argc, char** argv) {
  int rounds = argc > 1 ? std::atoi(argv[1]) : 400;
  std::mt19937 rng(42);

  std::unordered_map<int64_t, TokenState> st;
  std::mutex st_mu;
  std::thread dart([&] {
    for (;;) {
      std::unique_lock lk(g_mu);
      g_cv.wait(lk, [] { return g_quit || !g_q.empty(); });
      if (g_q.empty() && g_quit) return;
      Ev e = g_q.front();
      g_q.pop_front();
      lk.unlock();
      {
        std::lock_guard sl(st_mu);
        auto& s = st[e.token];
        if (s.terminals) ++s.after_terminal;
        if (e.type == ENH_EV_PROGRESS) {
          if (e.done < s.last_done) ++s.non_monotonic;
          s.last_done = e.done;
        }
        if (e.type == ENH_EV_DONE || e.type == ENH_EV_ERROR) ++s.terminals;
      }
      enh_free(e.payload);
    }
  });

  enh_session_config cfg{};
  cfg.struct_size = sizeof cfg;
  enh_session* s = nullptr;
  CHECK(enh_session_create(&cfg, &s) == ENH_OK, "session_create");

  int64_t token = 0;
  std::vector<int64_t> started_tokens;
  for (int r = 0; r < rounds; ++r) {
    int njobs = 1 + int(rng() % 4);
    std::vector<enh_job*> jobs;
    for (int k = 0; k < njobs; ++k) {
      char req[256];
      int mode = int(rng() % 6);
      std::snprintf(req, sizeof req,
                    "{\"tiles\":%d,\"events_per_tile\":%d,\"prep_us\":%d,\"infer_us\":%d,"
                    "\"post_us\":%d,\"needs_user_at\":%d,\"fail_at\":%d,\"progress_min_us\":%d}",
                    1 + int(rng() % 40), int(rng() % 50), int(rng() % 200), int(rng() % 500),
                    int(rng() % 100), mode == 3 ? int(rng() % 5) : -1, mode == 4 ? int(rng() % 10) : -1,
                    mode == 5 ? 200 : 0);
      enh_job* j = nullptr;
      CHECK(enh_job_create(s, req, &j) == ENH_OK, "job_create");
      ++token;
      CHECK(enh_job_start(j, listener, token) == ENH_OK, "job_start");
      CHECK(enh_job_start(j, listener, token) == ENH_E_INVALID, "double start must fail");
      started_tokens.push_back(token);
      jobs.push_back(j);
    }
    // Racers: random cancel / pause / answer / callback swap from other threads, then destroy.
    std::vector<std::thread> racers;
    for (auto* j : jobs) {
      int what = int(rng() % 5);
      int delay = int(rng() % 3000);
      racers.emplace_back([j, what, delay] {
        std::this_thread::sleep_for(std::chrono::microseconds(delay));
        switch (what) {
          case 0: enh_job_cancel(j); break;
          case 1: enh_job_pause(j); break;
          case 2: enh_job_answer(j, "{\"choice\":\"2x\"}"); break;
          case 3: break;  // let it run (or block on NEEDS_USER until destroy)
          case 4: enh_job_cancel(j); enh_job_cancel(j); enh_job_pause(j); break;
        }
      });
    }
    for (auto& t : racers) t.join();
    for (auto* j : jobs) {
      if (rng() % 3 == 0) std::this_thread::sleep_for(std::chrono::microseconds(rng() % 5000));
      char* stats = nullptr;
      if (enh_debug_job_stats(j, &stats) == ENH_OK) enh_free(stats);
      enh_job_destroy(j);
    }
  }

  // Callback swap barrier: after set_callback returns the old cb must never run again.
  {
    static std::atomic<int64_t> old_after_swap{0};
    static std::atomic<bool> swapped{false};
    auto old_cb = +[](int64_t t, int32_t ty, int32_t sg, int64_t d, int64_t tot, char* p) {
      if (swapped.load()) old_after_swap.fetch_add(1);
      listener(t, ty, sg, d, tot, p);
    };
    for (int i = 0; i < 50; ++i) {
      enh_job* j = nullptr;
      enh_job_create(s, "{\"tiles\":50,\"events_per_tile\":20,\"infer_us\":100}", &j);
      ++token;
      started_tokens.push_back(token);
      swapped = false;
      enh_job_start(j, old_cb, token);
      std::this_thread::sleep_for(std::chrono::microseconds(rng() % 3000));
      enh_job_set_callback(j, listener, token);
      swapped = true;
      enh_job_destroy(j);
    }
    CHECK(old_after_swap.load() == 0, "old callback ran %lld times after swap",
          (long long)old_after_swap.load());
  }

  enh_session_destroy(s);
  {
    std::lock_guard lk(g_mu);
    g_quit = true;
    g_cv.notify_one();
  }
  dart.join();

  int bad_term = 0, after = 0, nonmono = 0;
  for (auto t : started_tokens) {
    auto& x = st[t];
    if (x.terminals != 1) ++bad_term;
    after += x.after_terminal;
    nonmono += x.non_monotonic;
  }
  CHECK(bad_term == 0, "%d jobs without exactly one terminal event", bad_term);
  CHECK(after == 0, "%d events after terminal", after);
  CHECK(nonmono == 0, "%d non-monotonic progress events", nonmono);
  CHECK(enh_debug_live_payloads() == 0, "live payloads %lld", (long long)enh_debug_live_payloads());
  CHECK(enh_debug_live_jobs() == 0, "live jobs %lld", (long long)enh_debug_live_jobs());
  CHECK(enh_debug_live_threads() == 0, "live threads %lld", (long long)enh_debug_live_threads());
  std::printf("stress: %zu jobs, %d failures\n", started_tokens.size(), fails);
  return fails ? 1 : 0;
}
