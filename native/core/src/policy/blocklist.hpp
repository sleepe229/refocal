// GPU driver blocklist: parsing, vendor-aware driver version decoding, matching, merging.
// Format: docs/spec/appendix/manifest.schema.json (gpu_blocklist) + 05 §11, with the
// optional extensions proposed in docs/spikes/S3.md (id, platform, driver_min, os_min,
// action "gpu_fp32", top-level "gpu_blocklist_revoke").
#pragma once

#include <cstdint>
#include <optional>
#include <regex>
#include <string>
#include <vector>

namespace enh {

// Severity order matters: merge() keeps the strongest action.
enum class Action { None = 0, GpuFp32 = 1, Cpu = 2, Disable = 3 };

const char* action_name(Action a);
std::optional<Action> parse_action(const std::string& s);

// Identity of the GPU+driver+OS the app runs on (from VkPhysicalDeviceProperties + OS).
struct GpuIdentity {
  uint32_t vendor_id = 0;
  uint32_t device_id = 0;
  std::string device_name;      // VkPhysicalDeviceProperties.deviceName
  uint32_t driver_version = 0;  // VkPhysicalDeviceProperties.driverVersion (raw, vendor-specific)
  uint32_t api_version = 0;     // VkPhysicalDeviceProperties.apiVersion (VK_MAKE_API_VERSION)
  std::string platform;         // "android" | "ios" | "linux" | "windows" | "macos"
  std::string os_version;       // android: API level ("34"); ios: "17.4.1"; linux: kernel release
};

// ---- vendors ---------------------------------------------------------------
// Canonical vendor name for a PCI/Khronos vendor id ("Qualcomm", "ARM", ...), or hex string.
std::string vendor_name(uint32_t vendor_id);
// Rule vendor field: canonical name or alias (case-insensitive), "0x13B5" hex, or "*".
bool vendor_matches(const std::string& rule_vendor, uint32_t vendor_id);

// ---- driver versions -------------------------------------------------------
// Decode raw driverVersion into comparable numeric components (vendor-specific packing):
//   NVIDIA (0x10DE):          10.8.8.6 bits  -> [major, minor, patch, build]   e.g. 580.95.5.0
//   Intel on Windows (0x8086): 18.14 bits    -> [major, minor]
//   everyone else:            VK_MAKE_VERSION 10.10.12 bits -> [major, minor, patch]
//     (Qualcomm: 512.<release>.<x>; ARM: <rX>.<pY>.<x>; Mesa/Intel-Linux/lavapipe: Mesa version)
std::vector<uint32_t> decode_driver_version(uint32_t vendor_id, uint32_t raw,
                                            const std::string& platform = "");
// Human-readable: "580.95.05" (NVIDIA), "r38p1" (ARM), "512.615.0" (Qualcomm), "25.2.3" (Mesa).
std::string format_driver_version(uint32_t vendor_id, uint32_t raw,
                                  const std::string& platform = "");
// Parse a rule version spec: "r26p0", "r26p0-01eac0", "512.615", "580.95.05", "17.4", "34".
std::optional<std::vector<uint32_t>> parse_version_spec(const std::string& spec);
// Prefix comparison: compares only the first spec.size() components of `have`
// (missing components of `have` count as 0). "580" therefore covers all 580.x.y.
// Returns -1 / 0 / +1 for have <, ==, > spec.
int compare_version_prefix(const std::vector<uint32_t>& have, const std::vector<uint32_t>& spec);

// ---- model globs -----------------------------------------------------------
bool glob_match(const std::string& pattern, const std::string& text);  // '*' and '?'

// ---- rules -----------------------------------------------------------------
struct Rule {
  std::string id;      // optional in JSON; generated "<source>#<index>" if absent
  std::string source;  // "builtin" | "manifest" | "local" | file name
  std::string vendor;
  std::string device_regex;  // ECMAScript, full match, case-insensitive
  std::string platform;      // optional: "android" | "ios" | "" (any)
  std::optional<std::vector<uint32_t>> driver_min, driver_max, os_min, os_max, api_max;
  std::string driver_min_str, driver_max_str, os_min_str, os_max_str, api_max_str;
  std::vector<std::string> models;  // globs over model ids, e.g. "face.*", "*"
  Action action = Action::Cpu;
  std::string reason;
  std::regex re;
};

struct ParseResult {
  std::vector<Rule> rules;
  std::vector<std::string> revoke;    // rule ids revoked by this source
  std::vector<std::string> errors;    // rejected rules (invalid regex, missing field, bad version)
  std::vector<std::string> warnings;  // accepted with remarks (unknown fields)
};

// Accepts either {"gpu_blocklist":[...], "gpu_blocklist_revoke":[...]} (manifest/local file)
// or a bare array of rules. Never throws: malformed JSON -> errors.
ParseResult parse_blocklist(const std::string& json_text, const std::string& source);

struct MatchResult {
  Action action = Action::None;
  std::vector<const Rule*> matched;  // all matching, non-revoked rules
};

class Blocklist {
 public:
  // Sources are merged as a union; a later source can revoke earlier rules by id
  // (manifest revoking a bad built-in rule). Local rules cannot be revoked remotely.
  void add(ParseResult pr);
  MatchResult match(const GpuIdentity& gpu, const std::string& model_id) const;
  const std::vector<Rule>& rules() const { return rules_; }
  const std::vector<std::string>& errors() const { return errors_; }

 private:
  std::vector<Rule> rules_;
  std::vector<std::string> revoked_;
  std::vector<std::string> errors_;
};

bool rule_matches(const Rule& r, const GpuIdentity& gpu, const std::string& model_id);

// Escape a literal device name for use in device_regex.
std::string regex_escape(const std::string& s);

// Built-in list compiled into the app (seed for S3; see builtin_blocklist.cpp).
const char* builtin_blocklist_json();

}  // namespace enh
