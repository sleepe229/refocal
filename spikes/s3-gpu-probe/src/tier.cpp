#include "tier.hpp"

#include <algorithm>
#include <cctype>
#include <cstdio>

namespace refocal {

int soc_in_t2_list(const std::string& soc_in) {
    std::string s = soc_in;
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return std::toupper(c); });
    if (s.empty()) return -1;
    // Snapdragon 8 Gen 2 / 8 Gen 3 / 8 Elite (+ "for Galaxy"), Dimensity 9200/9300/9400, Tensor G3/G4
    static const char* t2[] = {"SM8550", "SM8650", "SM8750", "KALAMA", "PINEAPPLE",
                               "MT6985", "MT6989", "MT6991", "ZUMA", "ZUMAPRO"};
    for (const char* k : t2)
        if (s.find(k) != std::string::npos) return 1;
    bool android_like = s.find("SM") == 0 || s.find("MT") == 0 || s.find("QTI") != std::string::npos ||
                        s.find("MEDIATEK") != std::string::npos || s.find("EXYNOS") != std::string::npos ||
                        s.find("GOOGLE") != std::string::npos || s.find("S5E") != std::string::npos;
    return android_like ? 0 : -1;
}

TierDecision suggest_tier(const TierInput& in, const TierThresholds& th) {
    TierDecision d;
    char buf[160];
    if (in.selected_backend.empty()) {
        d.tier = "T0";
        d.reasons.push_back("no healthy backend for compact SR");
        d.below_t0_budget = true;
        return d;
    }
    double ms = in.selected_tile128_ms;
    if (ms > th.t0_tile128_ms) {
        d.below_t0_budget = true;
        std::snprintf(buf, sizeof buf, "%s tile128 %.1f ms > %.0f ms: NFR-PERF-001 T0 budget not met",
                      in.selected_backend.c_str(), ms, th.t0_tile128_ms);
        d.reasons.push_back(buf);
    }
    if (in.ram_gb < th.t0_ram_gb) {
        d.tier = "T0";
        std::snprintf(buf, sizeof buf, "RAM %.1f GB < %.1f GB", in.ram_gb, th.t0_ram_gb);
        d.reasons.push_back(buf);
        return d;
    }
    if (ms > th.t1_tile128_ms) {
        d.tier = "T0";
        std::snprintf(buf, sizeof buf, "best backend %s: tile128 %.1f ms > T1 limit %.0f ms", in.selected_backend.c_str(),
                      ms, th.t1_tile128_ms);
        d.reasons.push_back(buf);
        return d;
    }
    bool t2_speed = ms <= th.t2_tile128_ms;
    bool t2_ram = in.ram_gb >= th.t2_ram_gb;
    bool soc_ok = !th.require_soc_for_t2 || in.soc_t2 != 0;
    if (t2_speed && t2_ram && soc_ok) {
        d.tier = "T2";
        std::snprintf(buf, sizeof buf, "RAM %.1f GB >= %.1f, %s tile128 %.1f ms <= %.0f ms%s", in.ram_gb, th.t2_ram_gb,
                      in.selected_backend.c_str(), ms, th.t2_tile128_ms,
                      in.soc_t2 < 0 ? " (SoC not in table: benchmark decides)" : "");
        d.reasons.push_back(buf);
        return d;
    }
    d.tier = "T1";
    std::snprintf(buf, sizeof buf, "%s tile128 %.1f ms <= T1 limit %.0f ms", in.selected_backend.c_str(), ms,
                  th.t1_tile128_ms);
    d.reasons.push_back(buf);
    if (!t2_ram) d.reasons.push_back("RAM below T2 threshold");
    if (!t2_speed) d.reasons.push_back("slower than T2 limit");
    if (!soc_ok) d.reasons.push_back("SoC known and not in T2 list (require_soc_for_t2)");
    return d;
}

}  // namespace refocal
