// Ported from spike S3 (spikes/s3-gpu-probe/tests); benchmark metrics stay with the 0.2 bench.
#include <cmath>

#include "mini_test.hpp"
#include "policy/blocklist.hpp"
#include "policy/tier.hpp"

using namespace enh;

static constexpr uint32_t vkver(uint32_t a, uint32_t b, uint32_t c) {
  return (a << 22) | (b << 12) | c;
}
static constexpr uint32_t nvver(uint32_t a, uint32_t b, uint32_t c, uint32_t d = 0) {
  return (a << 22) | (b << 14) | (c << 6) | d;
}

static GpuIdentity gpu(uint32_t vendor, const std::string& name, uint32_t drv,
                       const std::string& platform = "android", const std::string& os = "34") {
  GpuIdentity g;
  g.vendor_id = vendor;
  g.device_name = name;
  g.driver_version = drv;
  g.platform = platform;
  g.os_version = os;
  g.api_version = vkver(1, 3, 0);
  return g;
}

static Blocklist load(const std::string& json, const std::string& src = "manifest") {
  Blocklist bl;
  bl.add(parse_blocklist(json, src));
  return bl;
}

// The exact example from 05 §11.
static const char* kSpecExample = R"({
  "gpu_blocklist": [
    {"vendor": "ARM", "device_regex": "Mali-G52.*", "driver_max": "r26p0",
     "models": ["face.*"], "reason": "fp16 NaN in modulated conv", "action": "cpu"},
    {"vendor": "ImgTec", "device_regex": "PowerVR.*", "models": ["*"], "action": "cpu"}
  ]
})";

TEST("spec example parses") {
  auto pr = parse_blocklist(kSpecExample, "manifest");
  CHECK_EQ(pr.rules.size(), 2u);
  CHECK(pr.errors.empty());
  CHECK(pr.warnings.empty());
  CHECK_EQ(pr.rules[0].id, std::string("manifest#0"));
}

TEST("ARM Mali rXpY: driver_max r26p0") {
  auto bl = load(kSpecExample);
  CHECK(bl.match(gpu(0x13B5, "Mali-G52 MC2", vkver(26, 0, 0)), "face.gfpgan-1.4").action ==
        Action::Cpu);
  CHECK(bl.match(gpu(0x13B5, "Mali-G52 MC2", vkver(25, 1, 0)), "face.gfpgan-1.4").action ==
        Action::Cpu);
  CHECK(bl.match(gpu(0x13B5, "Mali-G52 MC2", vkver(26, 0, 7)), "face.gfpgan-1.4").action ==
        Action::Cpu);  // patch ignored
  CHECK(bl.match(gpu(0x13B5, "Mali-G52 MC2", vkver(26, 1, 0)), "face.gfpgan-1.4").action ==
        Action::None);
  CHECK(bl.match(gpu(0x13B5, "Mali-G52 MC2", vkver(38, 1, 0)), "face.gfpgan-1.4").action ==
        Action::None);
  CHECK(bl.match(gpu(0x13B5, "Mali-G52 MC2", vkver(26, 0, 0)), "sr.general-x4v3").action ==
        Action::None);
  CHECK(bl.match(gpu(0x13B5, "Mali-G57 MC2", vkver(20, 0, 0)), "face.gfpgan-1.4").action ==
        Action::None);
  CHECK_EQ(format_driver_version(0x13B5, vkver(38, 1, 0)), std::string("r38p1"));
}

TEST("PowerVR wildcard models") {
  auto bl = load(kSpecExample);
  CHECK(bl.match(gpu(0x1010, "PowerVR Rogue GE8320", vkver(1, 13, 0)), "sr.general-x4v3").action ==
        Action::Cpu);
  CHECK(bl.match(gpu(0x1010, "PowerVR B-Series BXM-8-256", 0), "face.gfpgan-1.4").action ==
        Action::Cpu);
  // vendor mismatch: same name pattern but reported by another vendor id
  CHECK(bl.match(gpu(0x5143, "PowerVR fake", 0), "sr.general-x4v3").action == Action::None);
}

TEST("Qualcomm Adreno 512.<release>") {
  uint32_t raw = vkver(512, 615, 0);
  CHECK((decode_driver_version(0x5143, raw) == std::vector<uint32_t>{512, 615, 0}));
  CHECK_EQ(format_driver_version(0x5143, raw), std::string("512.615.0"));
  auto mk = [](const char* max) {
    return load(
        std::string(
            R"([{"vendor":"Qualcomm","device_regex":"Adreno \\(TM\\) 6[0-9]{2}","driver_max":")") +
        max + R"(","models":["*"],"action":"cpu"}])");
  };
  auto g = gpu(0x5143, "Adreno (TM) 640", raw);
  CHECK(mk("512.600").match(g, "sr.general-x4v3").action == Action::None);
  CHECK(mk("512.615").match(g, "sr.general-x4v3").action == Action::Cpu);
  CHECK(mk("512.700").match(g, "sr.general-x4v3").action == Action::Cpu);
  CHECK(mk("512").match(g, "sr.general-x4v3").action == Action::Cpu);
  CHECK(mk("512.700").match(gpu(0x5143, "Adreno (TM) 740", raw), "sr.general-x4v3").action ==
        Action::None);
}

TEST("NVIDIA 10.8.8.6 packing") {
  uint32_t raw = nvver(580, 95, 5);
  CHECK((decode_driver_version(0x10DE, raw) == std::vector<uint32_t>{580, 95, 5, 0}));
  CHECK_EQ(format_driver_version(0x10DE, raw), std::string("580.95.05"));
  auto mk = [](const char* max) {
    return load(std::string(R"([{"vendor":"NVIDIA","device_regex":".*RTX.*","driver_max":")") +
                max + R"(","models":["*"],"action":"disable"}])");
  };
  auto g = gpu(0x10DE, "NVIDIA GeForce RTX 3060", raw, "linux", "6.8.0");
  CHECK(mk("580.95.05").match(g, "x").action == Action::Disable);
  CHECK(mk("580.82").match(g, "x").action == Action::None);
  CHECK(mk("581").match(g, "x").action == Action::Disable);
  // standard decoding would give 145.380.320 for the same raw value: vendor-aware decoding matters
  CHECK((decode_driver_version(0x1002, raw) != decode_driver_version(0x10DE, raw)));
}

TEST("Intel: Windows 18.14 vs Linux Mesa") {
  uint32_t win = (101u << 14) | 4255u;
  CHECK((decode_driver_version(0x8086, win, "windows") == std::vector<uint32_t>{101, 4255}));
  CHECK_EQ(format_driver_version(0x8086, vkver(25, 2, 3), "linux"), std::string("25.2.3"));
}

TEST("Apple: os_max prefix semantics, unknown OS") {
  auto bl =
      load(R"([{"vendor":"Apple","device_regex":"Apple A12.*","platform":"ios","os_max":"17.4",
                       "models":["face.*"],"action":"cpu"}])");
  CHECK(bl.match(gpu(0x106B, "Apple A12 GPU", 0, "ios", "17.3.1"), "face.gfpgan-1.4").action ==
        Action::Cpu);
  CHECK(bl.match(gpu(0x106B, "Apple A12 GPU", 0, "ios", "17.4.1"), "face.gfpgan-1.4").action ==
        Action::Cpu);
  CHECK(bl.match(gpu(0x106B, "Apple A12 GPU", 0, "ios", "17.5"), "face.gfpgan-1.4").action ==
        Action::None);
  CHECK(bl.match(gpu(0x106B, "Apple A12 GPU", 0, "ios", ""), "face.gfpgan-1.4").action ==
        Action::None);
  CHECK(bl.match(gpu(0x106B, "Apple A12 GPU", 0, "android", "17.3"), "face.gfpgan-1.4").action ==
        Action::None);
}

TEST("os_min / driver_min ranges (Android API level)") {
  auto bl = load(R"([{"vendor":"Samsung","device_regex":".*Xclipse.*","os_min":"34","os_max":"35",
                       "driver_min":"2.0","models":["*"],"action":"gpu_fp32"}])");
  CHECK(bl.match(gpu(0x144D, "Samsung Xclipse 940", vkver(2, 0, 1), "android", "34"), "sr.x")
            .action == Action::GpuFp32);
  CHECK(bl.match(gpu(0x144D, "Samsung Xclipse 940", vkver(2, 0, 1), "android", "33"), "sr.x")
            .action == Action::None);
  CHECK(bl.match(gpu(0x144D, "Samsung Xclipse 940", vkver(2, 0, 1), "android", "36"), "sr.x")
            .action == Action::None);
  CHECK(bl.match(gpu(0x144D, "Samsung Xclipse 940", vkver(1, 9, 0), "android", "34"), "sr.x")
            .action == Action::None);
}

TEST("api_max (Vulkan apiVersion as driver age, like ncnn quirks)") {
  auto bl = load(
      R"([{"vendor":"Qualcomm","device_regex":"Adreno.*","api_max":"1.1.86","models":["*"],"action":"cpu"}])");
  auto g = gpu(0x5143, "Adreno (TM) 630", vkver(512, 400, 0));
  g.api_version = vkver(1, 1, 66);
  CHECK(bl.match(g, "x").action == Action::Cpu);
  g.api_version = vkver(1, 1, 87);
  CHECK(bl.match(g, "x").action == Action::None);
}

TEST("device_regex: full match, case-insensitive") {
  auto bl = load(R"([{"vendor":"ARM","device_regex":"Mali-G52","models":["*"],"action":"cpu"},
                       {"vendor":"ARM","device_regex":"mali-g7[0-9].*","models":["*"],"action":"cpu"}])");
  CHECK(bl.match(gpu(0x13B5, "Mali-G52 MC2", 0), "x").action == Action::None);  // no implicit .*
  CHECK(bl.match(gpu(0x13B5, "Mali-G52", 0), "x").action == Action::Cpu);
  CHECK(bl.match(gpu(0x13B5, "Mali-G76 MP10", 0), "x").action == Action::Cpu);
}

TEST("regex_escape round trip") {
  std::string name = "Adreno (TM) 740";
  auto bl = load(std::string(R"([{"vendor":"Qualcomm","device_regex":")") + [&] {
    std::string e = regex_escape(name), j;
    for (char c : e) {
      if (c == '\\')
        j += "\\\\";
      else
        j += c;
    }
    return j;
  }() + R"(","models":["*"],"action":"cpu"}])");
  CHECK(bl.errors().empty());
  CHECK(bl.match(gpu(0x5143, name, 0), "x").action == Action::Cpu);
  CHECK(bl.match(gpu(0x5143, "Adreno (TM) 7400", 0), "x").action == Action::None);
  CHECK(bl.match(gpu(0x5143, "Adreno TM 740", 0), "x").action == Action::None);
}

TEST("vendor matching: aliases, hex, wildcard") {
  CHECK(vendor_matches("ARM", 0x13B5));
  CHECK(vendor_matches("mali", 0x13B5));
  CHECK(vendor_matches("0x13b5", 0x13B5));
  CHECK(vendor_matches("*", 0x1234));
  CHECK(vendor_matches("Qualcomm", 0x5143));
  CHECK(vendor_matches("PowerVR", 0x1010));
  CHECK(vendor_matches("llvmpipe", 0x10005));
  CHECK(!vendor_matches("ARM", 0x5143));
  CHECK(!vendor_matches("0xZZ", 0x13B5));
  CHECK_EQ(vendor_name(0x10005), std::string("Mesa"));
  CHECK_EQ(vendor_name(0xABCD), std::string("0xABCD"));
}

TEST("model globs") {
  CHECK(glob_match("face.*", "face.gfpgan-1.4"));
  CHECK(glob_match("*", "anything"));
  CHECK(glob_match("sr.?eneral*", "sr.general-x4v3"));
  CHECK(glob_match("sr.general-x4v3", "sr.general-x4v3"));
  CHECK(!glob_match("face.*", "facex"));
  CHECK(!glob_match("face.*", "sr.face"));
  CHECK(glob_match("*codeformer", "face.codeformer"));
}

TEST("version spec parsing") {
  CHECK((parse_version_spec("r38p1-01eac0") == std::optional<std::vector<uint32_t>>({38, 1})));
  CHECK((parse_version_spec("R26P0") == std::optional<std::vector<uint32_t>>({26, 0})));
  CHECK((parse_version_spec("r26") == std::optional<std::vector<uint32_t>>({26})));
  CHECK((parse_version_spec("34") == std::optional<std::vector<uint32_t>>({34})));
  CHECK((parse_version_spec("512.615.0") == std::optional<std::vector<uint32_t>>({512, 615, 0})));
  CHECK(!parse_version_spec(""));
  CHECK(!parse_version_spec("1..2"));
  CHECK(!parse_version_spec("1.2."));
  CHECK(!parse_version_spec("abc"));
  CHECK(!parse_version_spec("v1.2"));
  CHECK_EQ(compare_version_prefix({26, 1, 0}, {26, 0}), 1);
  CHECK_EQ(compare_version_prefix({26}, {26, 0, 0}), 0);
  CHECK_EQ(compare_version_prefix({25, 9}, {26}), -1);
}

TEST("invalid rules rejected, valid ones kept, no throw") {
  auto pr = parse_blocklist(R"({"gpu_blocklist":[
        {"vendor":"ARM","device_regex":"Mali-G5[","models":["*"],"action":"cpu"},
        {"vendor":"ARM","models":["*"],"action":"cpu"},
        {"vendor":"ARM","device_regex":".*","models":[],"action":"cpu"},
        {"vendor":"ARM","device_regex":".*","models":["*"],"action":"explode"},
        {"vendor":"ARM","device_regex":".*","models":["*"],"action":"cpu","driver_max":"latest"},
        {"vendor":"ARM","device_regex":".*","models":[1],"action":"cpu"},
        "nonsense",
        {"vendor":"ARM","device_regex":".*","models":["*"],"action":"cpu","extra":1}
    ]})",
                            "manifest");
  CHECK_EQ(pr.rules.size(), 1u);
  CHECK_EQ(pr.errors.size(), 7u);
  CHECK_EQ(pr.warnings.size(), 1u);
  auto bad = parse_blocklist("{not json", "manifest");
  CHECK(bad.rules.empty());
  CHECK_EQ(bad.errors.size(), 1u);
  auto notarr = parse_blocklist(R"({"gpu_blocklist":{}})", "manifest");
  CHECK_EQ(notarr.errors.size(), 1u);
  auto empty = parse_blocklist(R"({"version":1})", "manifest");  // manifest without the key
  CHECK(empty.rules.empty() && empty.errors.empty());
}

TEST("merge: severity, revoke built-in from manifest, local not revocable") {
  Blocklist bl;
  bl.add(parse_blocklist(builtin_blocklist_json(), "builtin"));
  CHECK(bl.errors().empty());
  auto pvr = gpu(0x1010, "PowerVR Rogue GE8320", 0);
  CHECK(bl.match(pvr, "sr.general-x4v3").action == Action::Cpu);
  bl.add(parse_blocklist(R"({"gpu_blocklist":[
            {"id":"m-1","vendor":"ARM","device_regex":"Mali-G52.*","models":["face.*"],"action":"disable"},
            {"id":"m-2","vendor":"ARM","device_regex":"Mali-G52.*","models":["*"],"action":"gpu_fp32"}],
          "gpu_blocklist_revoke":["bi-powervr-all","local-x"]})",
                         "manifest"));
  CHECK(bl.match(pvr, "sr.general-x4v3").action == Action::None);
  auto g52 = gpu(0x13B5, "Mali-G52 MC2", vkver(26, 0, 0));
  auto m = bl.match(g52, "face.gfpgan-1.4");
  CHECK(m.action == Action::Disable);  // builtin cpu + manifest disable + gpu_fp32 -> strongest
  CHECK_EQ(m.matched.size(), 3u);
  CHECK(bl.match(g52, "sr.general-x4v3").action == Action::GpuFp32);
  bl.add(parse_blocklist(
      R"({"gpu_blocklist":[{"id":"local-x","vendor":"ARM","device_regex":"Mali-G52.*",
            "models":["sr.*"],"action":"cpu"}]})",
      "local"));
  CHECK(bl.match(g52, "sr.general-x4v3").action ==
        Action::Cpu);  // revoke list does not touch local
}

TEST("builtin: software rasterizers routed to CPU") {
  Blocklist bl;
  bl.add(parse_blocklist(builtin_blocklist_json(), "builtin"));
  CHECK(bl.match(gpu(0x10005, "llvmpipe (LLVM 20.1.2, 256 bits)", vkver(25, 0, 7), "linux"),
                 "sr.general-x4v3")
            .action == Action::Cpu);
  CHECK(bl.match(gpu(0x1AE0, "SwiftShader Device (Subzero)", 0), "sr.general-x4v3").action ==
        Action::Cpu);
  CHECK(bl.match(gpu(0x10DE, "NVIDIA GeForce RTX 3060", nvver(580, 95, 5), "linux"),
                 "face.gfpgan-1.4")
            .action == Action::None);
}

TEST("tier rules") {
  TierThresholds th;
  CHECK_EQ(suggest_tier({3.0, "vk0-fp16", true, 10, -1}, th).tier, std::string("T0"));  // RAM
  CHECK_EQ(suggest_tier({16, "vk0-fp16", true, 10, -1}, th).tier, std::string("T2"));
  CHECK_EQ(suggest_tier({16, "vk0-fp16", true, 10, 0}, th).tier,
           std::string("T2"));  // SoC is a hint
  th.require_soc_for_t2 = true;
  CHECK_EQ(suggest_tier({16, "vk0-fp16", true, 10, 0}, th).tier, std::string("T1"));
  th.require_soc_for_t2 = false;
  CHECK_EQ(suggest_tier({5.5, "vk0-fp16", true, 10, 1}, th).tier, std::string("T1"));  // RAM < T2
  CHECK_EQ(suggest_tier({16, "vk0-fp16", true, 60, -1}, th).tier, std::string("T1"));
  CHECK_EQ(suggest_tier({16, "cpu-fp16", false, 150, -1}, th).tier, std::string("T0"));
  auto slow = suggest_tier({16, "cpu-fp16", false, 400, -1}, th);
  CHECK(slow.tier == "T0" && slow.below_t0_budget);
  CHECK(suggest_tier({16, "", false, 0, -1}, th).tier == "T0");
  CHECK_EQ(soc_in_t2_list("Qualcomm SM8650"), 1);
  CHECK_EQ(soc_in_t2_list("Mediatek MT6877"), 0);
  CHECK_EQ(soc_in_t2_list("12th Gen Intel(R) Core(TM) i5-12400"), -1);
}

int main() { return mini::run_all(); }
