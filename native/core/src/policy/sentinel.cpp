#include "sentinel.hpp"

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

#include <cstdio>
#include <ctime>
#include <nlohmann/json.hpp>

#include "util/format.hpp"

using nlohmann::json;

namespace enh {

ExitReason parse_exit_reason(const std::string& s) {
  if (s == "native_crash" || s == "crash" || s == "anr") return ExitReason::NativeCrash;
  if (s == "os_kill" || s == "low_memory" || s == "user") return ExitReason::OsKill;
  return ExitReason::Unknown;
}

const char* exit_reason_name(ExitReason r) {
  switch (r) {
    case ExitReason::Unknown:
      return "unknown";
    case ExitReason::NativeCrash:
      return "native_crash";
    case ExitReason::OsKill:
      return "os_kill";
  }
  return "?";
}

std::string SentinelRecord::key() const {
  return strf("%04x:%08x:%08x|", gpu.vendor_id, gpu.device_id, gpu.driver_version) + model;
}

bool write_file_atomic(const std::string& path, const std::string& content) {
  std::string tmp = path + ".tmp";
  int fd = ::open(tmp.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
  if (fd < 0) return false;
  size_t off = 0;
  while (off < content.size()) {
    ssize_t n = ::write(fd, content.data() + off, content.size() - off);
    if (n <= 0) {
      ::close(fd);
      return false;
    }
    off += (size_t)n;
  }
  ::fsync(fd);  // the process may die a few ms later inside the driver
  ::close(fd);
  return ::rename(tmp.c_str(), path.c_str()) == 0;
}

bool read_file(const std::string& path, std::string& out) {
  FILE* f = std::fopen(path.c_str(), "rb");
  if (!f) return false;
  out.clear();
  char buf[65536];
  size_t n = sizeof buf;
  while (n == sizeof buf) {  // a short read is the end or an error: never read past it
    n = std::fread(buf, 1, sizeof buf, f);
    out.append(buf, n);
  }
  const bool ok = !std::ferror(f);  // the end, not an error: the whole file
  (void)std::fclose(f);             // read only
  return ok;
}

namespace {

json load_store(const std::string& path) {
  std::string s;
  if (read_file(path, s)) {
    json j = json::parse(s, nullptr, false);
    if (j.is_object()) return j;
  }
  return json{{"session", 0}, {"hits", json::object()}, {"gpu_blocklist", json::array()}};
}

void save_store(const std::string& path, const json& j) {
  write_file_atomic(path, j.dump(2) + "\n");
}

json gpu_json(const GpuIdentity& g) {
  return {{"vendor_id", g.vendor_id},     {"device_id", g.device_id},
          {"device_name", g.device_name}, {"driver_version", g.driver_version},
          {"api_version", g.api_version}, {"platform", g.platform},
          {"os_version", g.os_version}};
}

GpuIdentity gpu_from_json(const json& j) {
  GpuIdentity g;
  g.vendor_id = j.value("vendor_id", 0u);
  g.device_id = j.value("device_id", 0u);
  g.device_name = j.value("device_name", "");
  g.driver_version = j.value("driver_version", 0u);
  g.api_version = j.value("api_version", 0u);
  g.platform = j.value("platform", "");
  g.os_version = j.value("os_version", "");
  return g;
}

}  // namespace

SentinelStore::SentinelStore(std::string dir, SentinelPolicy policy)
    : dir_(std::move(dir)), policy_(policy) {
  ::mkdir(dir_.c_str(), 0755);
  session_ = load_store(store_path()).value("session", 0L);
}

std::string SentinelStore::sentinel_path() const { return dir_ + "/sentinel.json"; }
std::string SentinelStore::store_path() const { return dir_ + "/local_blocklist.json"; }

void SentinelStore::add_permanent(const SentinelRecord& rec, const std::string& reason,
                                  Action action) {
  json st = load_store(store_path());
  std::string ver =
      format_driver_version(rec.gpu.vendor_id, rec.gpu.driver_version, rec.gpu.platform);
  std::string id = "local-" + rec.key() + "-" + action_name(action);
  for (auto& r : st["gpu_blocklist"])
    if (r.value("id", "") == id) return;  // already blocked
  st["gpu_blocklist"].push_back({{"id", id},
                                 {"vendor", vendor_name(rec.gpu.vendor_id)},
                                 {"device_regex", regex_escape(rec.gpu.device_name)},
                                 {"driver_min", ver},
                                 {"driver_max", ver},
                                 {"models", {rec.model}},
                                 {"action", action_name(action)},
                                 {"reason", reason}});
  save_store(store_path(), st);
}

StartupReport SentinelStore::on_startup(ExitReason reason) {
  StartupReport rep;
  json st = load_store(store_path());
  session_ = st.value("session", 0L) + 1;
  st["session"] = session_;
  save_store(store_path(), st);

  std::string s;
  if (!read_file(sentinel_path(), s)) return rep;
  rep.sentinel_found = true;
  rep.reason = reason;
  json sj = json::parse(s, nullptr, false);
  ::unlink(sentinel_path().c_str());
  if (!sj.is_object() || !sj.contains("gpu")) {
    rep.note = "corrupt sentinel ignored";
    return rep;
  }
  SentinelRecord rec;
  rec.gpu = gpu_from_json(sj["gpu"]);
  rec.model = sj.value("model", "");
  rec.backend = sj.value("backend", "");
  rec.tile = sj.value("tile", 0);
  rep.key = rec.key();

  if (reason == ExitReason::OsKill) {
    rep.note = "process was killed by the OS during a GPU stage: not counted";
    return rep;
  }
  st = load_store(store_path());
  if (!st["hits"].is_object()) st["hits"] = json::object();
  json& h = st["hits"][rep.key];
  if (!h.is_object()) h = json::object();
  int count = h.value("count", 0) + 1;
  h["count"] = count;
  h["last_backend"] = rec.backend;
  h["last_tile"] = rec.tile;
  h["last_exit_reason"] = exit_reason_name(reason);
  h["last_time"] = (long)std::time(nullptr);
  rep.hits = count;
  bool block = reason == ExitReason::NativeCrash || count >= policy_.block_after;
  if (!block && policy_.quarantine_first_hit) {
    h["quarantine_session"] = session_;
    rep.quarantined_now = true;
    rep.note = "first hit: CPU for this session, GPU will be retried next session";
  }
  save_store(store_path(), st);
  if (block) {
    add_permanent(rec, std::string("crash sentinel: ") + exit_reason_name(reason) +
                           ", hits=" + std::to_string(count) + ", backend=" + rec.backend +
                           ", tile=" + std::to_string(rec.tile));
    rep.blocked_now = true;
    rep.note = "permanently blocked for this driver version";
  }
  return rep;
}

void SentinelStore::arm(const SentinelRecord& rec) {
  json j = {{"gpu", gpu_json(rec.gpu)},
            {"driver",
             format_driver_version(rec.gpu.vendor_id, rec.gpu.driver_version, rec.gpu.platform)},
            {"model", rec.model},
            {"backend", rec.backend},
            {"tile", rec.tile},
            {"session", session_},
            {"time", (long)std::time(nullptr)}};
  write_file_atomic(sentinel_path(), j.dump() + "\n");
}

void SentinelStore::disarm(const SentinelRecord& rec) {
  ::unlink(sentinel_path().c_str());
  json st = load_store(store_path());
  if (st["hits"].contains(rec.key())) {  // consecutive semantics: success resets the counter
    st["hits"].erase(rec.key());
    save_store(store_path(), st);
  }
}

void SentinelStore::record_confirmed_crash(const SentinelRecord& rec, const std::string& why,
                                           Action action) {
  ::unlink(sentinel_path().c_str());
  add_permanent(rec, "probe: " + why + ", backend=" + rec.backend, action);
}

bool SentinelStore::quarantined(const SentinelRecord& rec) const {
  json st = load_store(store_path());
  if (!st["hits"].contains(rec.key())) return false;
  return st["hits"][rec.key()].value("quarantine_session", -1L) == session_;
}

int SentinelStore::hits(const SentinelRecord& rec) const {
  json st = load_store(store_path());
  if (!st["hits"].contains(rec.key())) return 0;
  return st["hits"][rec.key()].value("count", 0);
}

ParseResult SentinelStore::local_rules() const {
  json st = load_store(store_path());
  json doc = {{"gpu_blocklist", st["gpu_blocklist"]}};
  return parse_blocklist(doc.dump(), "local");
}

void SentinelStore::reset() {
  ::unlink(sentinel_path().c_str());
  ::unlink(store_path().c_str());
  session_ = 0;
}

}  // namespace enh
