// Job event sink (ADR-0005 after S6): a C callback or a Dart native port. Swapping the sink is a
// barrier: once set_*() returns, the previous sink never receives another event of this job.
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <cstdint>
#include <mutex>
#include <nlohmann/json.hpp>
#include <string>

#include "enh.h"

namespace enh {

enum Stage : int32_t {  // NOLINT(performance-enum-size): the event wire format (int32)
  kStageQueued = 0,
  kStageDecode = 1,
  kStageUpscale = 2,
  kStageFinalize = 3,
  kStageFaces = 4,      // DetectFaces + RestoreFaces (ADR-0012)
  kStageJpeg = 5,       // JPEG cleanup before SR (S9)
  kStageScratches = 6,  // scratch detection + inpainting before SR (S9)
  kStageLowLight = 7    // low-light enhancement before SR (S9)
};
const char* stage_name(int32_t stage);

// Dumps JSON with invalid UTF-8 replaced by U+FFFD (the Dart VM rejects invalid strings, S6).
std::string dump_json(const nlohmann::json& j);

bool dart_api_ready();
intptr_t dart_api_init(void* data);

class EventSink {
 public:
  void set_callback(enh_event_cb cb, int64_t token);
  void set_port(int64_t port, int64_t token);  // throws if the Dart API is not initialized
  bool attached() const;

  void emit(int32_t type, int32_t stage, int64_t done, int64_t total,
            const nlohmann::json& payload);
  // PROGRESS, coalesced to <= 30 Hz unless `force` (first/last tile).
  void progress(int32_t stage, int64_t done, int64_t total, int64_t eta_ms, bool force);

 private:
  mutable std::mutex mu_;  // held while delivering: makes set_*() a barrier
  enh_event_cb cb_ = nullptr;
  int64_t port_ = 0;
  int64_t token_ = 0;
  int64_t last_progress_ns_ = 0;
};

int64_t now_ns();

}  // namespace enh
