// SPDX-License-Identifier: Apache-2.0
#include "job/events.hpp"

#include <time.h>

#include <atomic>
#include <cstdlib>
#include <cstring>

#include "dart_api_dl.h"
#include "util/error.hpp"

namespace enh {
namespace {
std::atomic<bool> g_dart_ready{false};
constexpr int64_t kProgressIntervalNs = 33'000'000;  // 30 Hz
}  // namespace

int64_t now_ns() {
  timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return int64_t(ts.tv_sec) * 1'000'000'000 + ts.tv_nsec;
}

const char* stage_name(int32_t s) {
  switch (s) {
    case kStageQueued:
      return "queued";
    case kStageDecode:
      return "decode";
    case kStageUpscale:
      return "upscale";
    case kStageFinalize:
      return "finalize";
    default:
      return "unknown";
  }
}

std::string dump_json(const nlohmann::json& j) {
  return j.dump(-1, ' ', false, nlohmann::json::error_handler_t::replace);
}

bool dart_api_ready() { return g_dart_ready.load(); }

intptr_t dart_api_init(void* data) {
  intptr_t r = Dart_InitializeApiDL(data);
  if (r == 0) g_dart_ready = true;
  return r;
}

void EventSink::set_callback(enh_event_cb cb, int64_t token) {
  std::lock_guard lk(mu_);
  cb_ = cb;
  port_ = 0;
  token_ = token;
}

void EventSink::set_port(int64_t port, int64_t token) {
  if (port != 0 && !dart_api_ready()) fail(ENH_E_INVALID, "enh_dart_init() was not called");
  std::lock_guard lk(mu_);
  cb_ = nullptr;
  port_ = port;
  token_ = token;
}

bool EventSink::attached() const {
  std::lock_guard lk(mu_);
  return cb_ || port_;
}

void EventSink::emit(int32_t type, int32_t stage, int64_t done, int64_t total,
                     const nlohmann::json& payload) {
  std::string s = dump_json(payload);
  std::lock_guard lk(mu_);
  if (port_) {
    Dart_CObject v[6];
    Dart_CObject* items[6];
    int64_t ints[5] = {token_, type, stage, done, total};
    for (int k = 0; k < 5; ++k) {
      v[k].type = Dart_CObject_kInt64;
      v[k].value.as_int64 = ints[k];
      items[k] = &v[k];
    }
    v[5].type = Dart_CObject_kString;
    v[5].value.as_string = s.data();
    items[5] = &v[5];
    Dart_CObject msg;
    msg.type = Dart_CObject_kArray;
    msg.value.as_array.length = 6;
    msg.value.as_array.values = items;
    Dart_PostCObject_DL(port_, &msg);  // false = isolate gone: dropped, the job continues (S6)
    return;
  }
  if (cb_) {
    char* p = static_cast<char*>(std::malloc(s.size() + 1));
    if (!p) return;
    std::memcpy(p, s.c_str(), s.size() + 1);
    cb_(token_, type, stage, done, total, p);  // receiver owns p -> enh_free()
  }
}

void EventSink::progress(int32_t stage, int64_t done, int64_t total, int64_t eta_ms, bool force) {
  int64_t t = now_ns();
  {
    std::lock_guard lk(mu_);
    if (!force && t - last_progress_ns_ < kProgressIntervalNs) return;
    last_progress_ns_ = t;
  }
  nlohmann::json p = {{"eta_ms", eta_ms}};
  emit(ENH_EV_PROGRESS, stage, done, total, p);
}

}  // namespace enh
