// Crash sentinel (ADR-0016) + persistent local blocklist store.
//
// Before a GPU stage: arm() writes <state>/sentinel.json atomically (tmp + fsync + rename).
// After the stage:   disarm() removes it and resets the consecutive-hit counter of that key.
// On process start:  on_startup() turns a leftover sentinel into a "hit" for its key.
//
// Policy (see docs/spikes/S3.md):
//   exit_reason = native_crash (Android ApplicationExitInfo REASON_CRASH_NATIVE / ANR, or the
//                 probe parent observing a signal) -> permanent local rule immediately;
//   exit_reason = os_kill (LMK / user swipe / REASON_LOW_MEMORY, USER_REQUESTED ...) -> ignored;
//   exit_reason = unknown (iOS, Android 10) -> consecutive hits; hits >= block_after (2)
//                 -> permanent; otherwise, if quarantine_first_hit, the next session runs this
//                 key on CPU (satisfies NFR-REL-003 "next launch uses CPU"), then GPU is retried.
// Permanent rules pin the exact driver version (driver_min == driver_max), so a driver update
// lifts them automatically.
#pragma once

#include <cstdint>
#include <string>

#include "blocklist.hpp"

namespace enh {

enum class ExitReason { Unknown, NativeCrash, OsKill };
ExitReason parse_exit_reason(const std::string& s);
const char* exit_reason_name(ExitReason r);

struct SentinelRecord {
  GpuIdentity gpu;
  std::string model;    // e.g. "sr.general-x4v3"
  std::string backend;  // e.g. "vulkan-fp16"
  int tile = 0;
  std::string key() const;  // "<vendor>:<device>:<driver>|<model>"
};

struct StartupReport {
  bool sentinel_found = false;
  std::string key;
  ExitReason reason = ExitReason::Unknown;
  int hits = 0;
  bool blocked_now = false;      // permanent rule added in this startup
  bool quarantined_now = false;  // CPU for this session only
  std::string note;
};

struct SentinelPolicy {
  int block_after = 2;
  bool quarantine_first_hit = true;
};

class SentinelStore {
 public:
  explicit SentinelStore(std::string dir, SentinelPolicy policy = {});

  // Call once per process start, before any GPU work. Increments the session counter.
  StartupReport on_startup(ExitReason previous_exit = ExitReason::Unknown);

  void arm(const SentinelRecord& rec);
  void disarm(const SentinelRecord& rec);  // success: removes sentinel, resets hits

  // Record a crash observed directly (probe parent saw the child die by a signal).
  void record_confirmed_crash(const SentinelRecord& rec, const std::string& why,
                              Action action = Action::Cpu);

  bool quarantined(const SentinelRecord& rec) const;  // CPU for this session
  int hits(const SentinelRecord& rec) const;
  ParseResult local_rules() const;  // permanent rules, as a "local" blocklist source
  void reset();                     // "reset GPU blocklist" in settings

  std::string sentinel_path() const;
  std::string store_path() const;

 private:
  std::string dir_;
  SentinelPolicy policy_;
  long session_ = 0;
  void add_permanent(const SentinelRecord& rec, const std::string& reason,
                     Action action = Action::Cpu);
};

// Atomic file write helper (tmp + fsync + rename).
bool write_file_atomic(const std::string& path, const std::string& content);
bool read_file(const std::string& path, std::string& out);

}  // namespace enh
