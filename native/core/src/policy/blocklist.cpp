#include "blocklist.hpp"

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <nlohmann/json.hpp>
#include <set>

#include "util/format.hpp"

namespace enh {
namespace {

std::string lower(std::string s) {
  std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return std::tolower(c); });
  return s;
}

struct VendorAlias {
  uint32_t id;
  const char* canonical;
  std::vector<const char*> aliases;
};

const std::vector<VendorAlias>& vendor_table() {
  static const std::vector<VendorAlias> t = {
      {0x5143, "Qualcomm", {"qualcomm", "qcom", "adreno"}},
      {0x13B5, "ARM", {"arm", "mali"}},
      {0x1010, "ImgTec", {"imgtec", "imagination", "powervr", "img"}},
      {0x106B, "Apple", {"apple"}},
      {0x144D, "Samsung", {"samsung", "xclipse"}},
      {0x1002, "AMD", {"amd", "ati", "radeon"}},
      {0x10DE, "NVIDIA", {"nvidia"}},
      {0x8086, "Intel", {"intel"}},
      {0x10005, "Mesa", {"mesa", "llvmpipe", "lavapipe"}},
      {0x1AE0, "Google", {"google", "swiftshader"}},
      {0x14E4, "Broadcom", {"broadcom", "videocore"}},
      {0x19E5, "Huawei", {"huawei", "maleoon"}},
      {0x1E3E, "Moore Threads", {"moore threads"}},
  };
  return t;
}

}  // namespace

const char* action_name(Action a) {
  switch (a) {
    case Action::None:
      return "none";
    case Action::GpuFp32:
      return "gpu_fp32";
    case Action::Cpu:
      return "cpu";
    case Action::Disable:
      return "disable";
  }
  return "?";
}

std::optional<Action> parse_action(const std::string& s) {
  if (s == "cpu") return Action::Cpu;
  if (s == "disable") return Action::Disable;
  if (s == "gpu_fp32") return Action::GpuFp32;
  return std::nullopt;
}

std::string vendor_name(uint32_t vendor_id) {
  for (const auto& v : vendor_table())
    if (v.id == vendor_id) return v.canonical;
  return strf("0x%04X", vendor_id);
}

bool vendor_matches(const std::string& rule_vendor, uint32_t vendor_id) {
  if (rule_vendor == "*" || rule_vendor.empty()) return true;
  std::string rv = lower(rule_vendor);
  if (rv.rfind("0x", 0) == 0) {
    try {
      return std::stoul(rv, nullptr, 16) == vendor_id;
    } catch (...) {
      return false;
    }
  }
  for (const auto& v : vendor_table()) {
    if (v.id != vendor_id) continue;
    if (lower(v.canonical) == rv) return true;
    for (const char* a : v.aliases)
      if (rv == a) return true;
  }
  return false;
}

std::vector<uint32_t> decode_driver_version(uint32_t vendor_id, uint32_t v,
                                            const std::string& platform) {
  if (vendor_id == 0x10DE)  // NVIDIA: 10.8.8.6
    return {v >> 22, (v >> 14) & 0xFF, (v >> 6) & 0xFF, v & 0x3F};
  if (vendor_id == 0x8086 && platform == "windows")  // Intel Windows: 18.14
    return {v >> 14, v & 0x3FFF};
  // VK_MAKE_VERSION (legacy 10.10.12, keeps Qualcomm's 512 major intact)
  return {v >> 22, (v >> 12) & 0x3FF, v & 0xFFF};
}

std::string format_driver_version(uint32_t vendor_id, uint32_t raw, const std::string& platform) {
  auto c = decode_driver_version(vendor_id, raw, platform);
  if (vendor_id == 0x13B5) return strf("r%up%u", c[0], c[1]);
  if (vendor_id == 0x10DE) return strf("%u.%u.%02u", c[0], c[1], c[2]);
  std::string s;
  for (size_t i = 0; i < c.size(); ++i) s += (i ? "." : "") + std::to_string(c[i]);
  return s;
}

std::optional<std::vector<uint32_t>> parse_version_spec(const std::string& spec_in) {
  std::string spec = lower(spec_in);
  std::vector<uint32_t> out;
  if (spec.empty()) return std::nullopt;
  // ARM "rXpY[-suffix]"
  if (spec[0] == 'r' && spec.size() > 1 && std::isdigit((unsigned char)spec[1])) {
    size_t p = spec.find('p');
    if (p == std::string::npos) {
      try {
        out.push_back((uint32_t)std::stoul(spec.substr(1)));
      } catch (...) {
        return std::nullopt;
      }
      return out;
    }
    try {
      out.push_back((uint32_t)std::stoul(spec.substr(1, p - 1)));
      out.push_back((uint32_t)std::stoul(spec.substr(p + 1)));  // stops at '-'
    } catch (...) {
      return std::nullopt;
    }
    return out;
  }
  // dotted numeric "512.615.0"
  size_t i = 0;
  while (i < spec.size()) {
    if (!std::isdigit((unsigned char)spec[i])) return std::nullopt;
    size_t j = i;
    while (j < spec.size() && std::isdigit((unsigned char)spec[j])) ++j;
    try {
      out.push_back((uint32_t)std::stoul(spec.substr(i, j - i)));
    } catch (...) {
      return std::nullopt;
    }
    if (j == spec.size()) break;
    if (spec[j] != '.') return std::nullopt;
    i = j + 1;
    if (i == spec.size()) return std::nullopt;
  }
  if (out.empty()) return std::nullopt;
  return out;
}

int compare_version_prefix(const std::vector<uint32_t>& have, const std::vector<uint32_t>& spec) {
  for (size_t i = 0; i < spec.size(); ++i) {
    uint32_t h = i < have.size() ? have[i] : 0;
    if (h < spec[i]) return -1;
    if (h > spec[i]) return 1;
  }
  return 0;
}

bool glob_match(const std::string& p, const std::string& t) {
  size_t pi = 0, ti = 0, star = std::string::npos, mark = 0;
  while (ti < t.size()) {
    if (pi < p.size() && (p[pi] == '?' || p[pi] == t[ti])) {
      ++pi;
      ++ti;
    } else if (pi < p.size() && p[pi] == '*') {
      star = pi++;
      mark = ti;
    } else if (star != std::string::npos) {
      pi = star + 1;
      ti = ++mark;
    } else {
      return false;
    }
  }
  while (pi < p.size() && p[pi] == '*') ++pi;
  return pi == p.size();
}

std::string regex_escape(const std::string& s) {
  static const std::string special = R"(\^$.|?*+()[]{})";
  std::string out;
  for (char c : s) {
    if (special.find(c) != std::string::npos) out += '\\';
    out += c;
  }
  return out;
}

ParseResult parse_blocklist(const std::string& text, const std::string& source) {
  using nlohmann::json;
  ParseResult pr;
  json doc = json::parse(text, nullptr, /*allow_exceptions=*/false, /*ignore_comments=*/true);
  if (doc.is_discarded()) {
    pr.errors.push_back(source + ": malformed JSON");
    return pr;
  }
  json arr;
  if (doc.is_array()) {
    arr = doc;
  } else if (doc.is_object()) {
    if (doc.contains("gpu_blocklist")) arr = doc["gpu_blocklist"];
    if (doc.contains("gpu_blocklist_revoke") && doc["gpu_blocklist_revoke"].is_array())
      for (auto& r : doc["gpu_blocklist_revoke"])
        if (r.is_string()) pr.revoke.push_back(r.get<std::string>());
  }
  if (arr.is_null()) return pr;
  if (!arr.is_array()) {
    pr.errors.push_back(source + ": gpu_blocklist is not an array");
    return pr;
  }
  static const std::set<std::string> known = {
      "id",     "vendor", "device_regex", "platform", "driver_min", "driver_max",
      "os_min", "os_max", "api_max",      "models",   "action",     "reason"};
  int idx = -1;
  for (auto& e : arr) {
    ++idx;
    std::string where = source + "#" + std::to_string(idx);
    if (!e.is_object()) {
      pr.errors.push_back(where + ": not an object");
      continue;
    }
    auto str = [&](const char* k) -> std::optional<std::string> {
      if (!e.contains(k)) return std::nullopt;
      if (!e[k].is_string()) return std::string("\x01");  // marker: wrong type
      return e[k].get<std::string>();
    };
    Rule r;
    r.source = source;
    for (auto it = e.begin(); it != e.end(); ++it)
      if (!known.count(it.key()))
        pr.warnings.push_back(where + ": unknown field '" + it.key() + "' ignored");
    auto id = str("id");
    r.id = id && *id != "\x01" ? *id : where;
    auto vendor = str("vendor"), dre = str("device_regex"), action = str("action");
    if (!vendor || !dre || !action || !e.contains("models")) {
      pr.errors.push_back(where +
                          ": missing required field (vendor, device_regex, models, action)");
      continue;
    }
    if (*vendor == "\x01" || *dre == "\x01" || *action == "\x01") {
      pr.errors.push_back(where + ": wrong field type");
      continue;
    }
    r.vendor = *vendor;
    r.device_regex = *dre;
    auto act = parse_action(*action);
    if (!act) {
      pr.errors.push_back(where + ": unknown action '" + *action + "'");
      continue;
    }
    r.action = *act;
    if (!e["models"].is_array() || e["models"].empty()) {
      pr.errors.push_back(where + ": models must be a non-empty array");
      continue;
    }
    bool bad = false;
    for (auto& m : e["models"]) {
      if (!m.is_string()) {
        bad = true;
        break;
      }
      r.models.push_back(m.get<std::string>());
    }
    if (bad) {
      pr.errors.push_back(where + ": models must be strings");
      continue;
    }
    try {
      r.re = std::regex(r.device_regex, std::regex::ECMAScript | std::regex::icase);
    } catch (const std::regex_error& ex) {
      pr.errors.push_back(where + ": invalid device_regex '" + r.device_regex + "': " + ex.what());
      continue;
    }
    auto ver = [&](const char* k, std::optional<std::vector<uint32_t>>& dst, std::string& raw) {
      auto s = str(k);
      if (!s) return true;
      raw = *s;
      dst = parse_version_spec(*s);
      if (!dst) {
        pr.errors.push_back(where + ": bad version in " + k + ": '" + *s + "'");
        return false;
      }
      return true;
    };
    if (!ver("driver_min", r.driver_min, r.driver_min_str) ||
        !ver("driver_max", r.driver_max, r.driver_max_str) ||
        !ver("os_min", r.os_min, r.os_min_str) || !ver("os_max", r.os_max, r.os_max_str) ||
        !ver("api_max", r.api_max, r.api_max_str))
      continue;
    if (auto p = str("platform"); p && *p != "\x01") r.platform = lower(*p);
    if (auto rs = str("reason"); rs && *rs != "\x01") r.reason = *rs;
    pr.rules.push_back(std::move(r));
  }
  return pr;
}

bool rule_matches(const Rule& r, const GpuIdentity& g, const std::string& model_id) {
  if (!vendor_matches(r.vendor, g.vendor_id)) return false;
  if (!r.platform.empty() && r.platform != "*" && r.platform != lower(g.platform)) return false;
  if (!std::regex_match(g.device_name, r.re)) return false;
  if (r.driver_min || r.driver_max) {
    auto have = decode_driver_version(g.vendor_id, g.driver_version, g.platform);
    if (r.driver_min && compare_version_prefix(have, *r.driver_min) < 0) return false;
    if (r.driver_max && compare_version_prefix(have, *r.driver_max) > 0) return false;
  }
  if (r.api_max) {  // Vulkan apiVersion as driver-age proxy (what ncnn's own quirk table uses)
    uint32_t a = g.api_version;
    std::vector<uint32_t> have = {(a >> 22) & 0x7F, (a >> 12) & 0x3FF, a & 0xFFF};
    if (compare_version_prefix(have, *r.api_max) > 0) return false;
  }
  if (r.os_min || r.os_max) {
    auto have = parse_version_spec(g.os_version);
    if (!have) return false;  // unknown OS version: a bounded rule does not apply
    if (r.os_min && compare_version_prefix(*have, *r.os_min) < 0) return false;
    if (r.os_max && compare_version_prefix(*have, *r.os_max) > 0) return false;
  }
  for (const auto& m : r.models)
    if (glob_match(m, model_id)) return true;
  return false;
}

void Blocklist::add(ParseResult pr) {
  for (auto& e : pr.errors) errors_.push_back(e);
  for (auto& id : pr.revoke) revoked_.push_back(id);
  for (auto& r : pr.rules) rules_.push_back(std::move(r));
}

MatchResult Blocklist::match(const GpuIdentity& gpu, const std::string& model_id) const {
  MatchResult m;
  for (const auto& r : rules_) {
    bool revoked =
        r.source != "local" && std::find(revoked_.begin(), revoked_.end(), r.id) != revoked_.end();
    if (revoked || !rule_matches(r, gpu, model_id)) continue;
    m.matched.push_back(&r);
    if (static_cast<int>(r.action) > static_cast<int>(m.action)) m.action = r.action;
  }
  return m;
}

}  // namespace enh
