// Ported from spike S3 (spikes/s3-gpu-probe/tests).
#include <unistd.h>

#include <cstdio>
#include <cstdlib>
#include <string>

#include "mini_test.hpp"
#include "policy/blocklist.hpp"
#include "policy/sentinel.hpp"

using namespace enh;

static std::string tmpdir() {
  const char* base = std::getenv("TMPDIR");  // adb shell: /data/local/tmp
  std::string t =
      std::string(base && *base ? base : (access("/tmp", W_OK) == 0 ? "/tmp" : "/data/local/tmp")) +
      "/refocal-sentinel-XXXXXX";
  const char* dir = mkdtemp(t.data());
  if (!dir) {
    std::perror("mkdtemp");
    std::exit(1);
  }
  return dir;
}

static SentinelRecord rec(const std::string& model = "face.gfpgan-1.4",
                          uint32_t drv = (38u << 22) | (1u << 12)) {
  SentinelRecord r;
  r.gpu.vendor_id = 0x13B5;
  r.gpu.device_id = 0x74021000;
  r.gpu.device_name = "Mali-G52 MC2";
  r.gpu.driver_version = drv;
  r.gpu.platform = "android";
  r.gpu.os_version = "30";
  r.model = model;
  r.backend = "vk0-fp16";
  r.tile = 256;
  return r;
}

static Action local_action(const SentinelStore& s, const SentinelRecord& r) {
  Blocklist bl;
  bl.add(s.local_rules());
  return bl.match(r.gpu, r.model).action;
}

TEST("clean start: nothing found") {
  SentinelStore s(tmpdir());
  auto rep = s.on_startup();
  CHECK(!rep.sentinel_found);
}

TEST("unknown exit: hit 1 quarantines one session, hit 2 blocks permanently") {
  std::string d = tmpdir();
  auto r = rec();
  {
    SentinelStore s(d);
    s.on_startup();
    s.arm(r);  // ... process dies here
  }
  {
    SentinelStore s(d);
    auto rep = s.on_startup();
    CHECK(rep.sentinel_found && rep.hits == 1 && rep.quarantined_now && !rep.blocked_now);
    CHECK(s.quarantined(r));
    CHECK(local_action(s, r) == Action::None);
  }
  {
    SentinelStore s(d);
    s.on_startup();  // session after quarantine: GPU retried
    CHECK(!s.quarantined(r));
    s.arm(r);  // crashes again
  }
  {
    SentinelStore s(d);
    auto rep = s.on_startup();
    CHECK(rep.hits == 2 && rep.blocked_now);
    CHECK(local_action(s, r) == Action::Cpu);
    CHECK(local_action(s, rec("sr.general-x4v3")) == Action::None);  // other model unaffected
    CHECK(local_action(s, rec("face.gfpgan-1.4", (38u << 22) | (2u << 12))) ==
          Action::None);  // driver update lifts
    auto pr = s.local_rules();
    CHECK_EQ(pr.rules.size(), 1u);
    CHECK(pr.errors.empty());
    CHECK_EQ(pr.rules[0].driver_max_str, std::string("r38p1"));
  }
}

TEST("success between crashes resets the counter (consecutive semantics)") {
  std::string d = tmpdir();
  auto r = rec();
  {
    SentinelStore s(d);
    s.on_startup();
    s.arm(r);
  }
  {
    SentinelStore s(d);
    CHECK(s.on_startup().hits == 1);
  }
  {
    SentinelStore s(d);
    s.on_startup();
    s.arm(r);
    s.disarm(r);
    CHECK_EQ(s.hits(r), 0);
    s.arm(r);
  }
  {
    SentinelStore s(d);
    auto rep = s.on_startup();
    CHECK(rep.hits == 1 && !rep.blocked_now);
  }
}

TEST("os_kill not counted; native_crash blocks immediately") {
  std::string d = tmpdir();
  auto r = rec();
  {
    SentinelStore s(d);
    s.on_startup();
    s.arm(r);
  }
  {
    SentinelStore s(d);
    auto rep = s.on_startup(ExitReason::OsKill);
    CHECK(rep.sentinel_found && rep.hits == 0);
    CHECK(!s.quarantined(r));
    s.arm(r);
  }
  {
    SentinelStore s(d);
    auto rep = s.on_startup(ExitReason::NativeCrash);
    CHECK(rep.blocked_now && rep.hits == 1);
    CHECK(local_action(s, r) == Action::Cpu);
  }
}

TEST("strict ADR-0016 policy: no quarantine after first hit") {
  std::string d = tmpdir();
  auto r = rec();
  SentinelPolicy p;
  p.quarantine_first_hit = false;
  {
    SentinelStore s(d, p);
    s.on_startup();
    s.arm(r);
  }
  {
    SentinelStore s(d, p);
    auto rep = s.on_startup();
    CHECK(rep.hits == 1 && !rep.quarantined_now);
    CHECK(!s.quarantined(r));
  }
}

TEST("corrupt sentinel ignored, reset clears everything") {
  std::string d = tmpdir();
  write_file_atomic(d + "/sentinel.json", "{garbage");
  SentinelStore s(d);
  auto rep = s.on_startup();
  CHECK(rep.sentinel_found && rep.hits == 0);
  auto r = rec();
  s.record_confirmed_crash(r, "test");
  CHECK(local_action(s, r) == Action::Cpu);
  s.reset();
  CHECK(local_action(s, r) == Action::None);
}

int main() { return mini::run_all(); }
