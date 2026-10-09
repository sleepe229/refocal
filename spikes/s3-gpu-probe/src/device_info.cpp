#include "device_info.hpp"

#include <cstdio>
#include <cstring>
#include <fstream>
#include <sys/utsname.h>

#include <cpu.h>
#include <gpu.h>

#if defined(__ANDROID__)
#include <sys/system_properties.h>
#endif

namespace refocal {
namespace {

std::string trim(std::string s) {
    while (!s.empty() && (s.back() == '\n' || s.back() == ' ' || s.back() == '\t')) s.pop_back();
    size_t i = 0;
    while (i < s.size() && (s[i] == ' ' || s[i] == '\t')) ++i;
    return s.substr(i);
}

std::string read_first_line(const char* path) {
    std::ifstream f(path);
    std::string l;
    std::getline(f, l);
    return trim(l);
}

[[maybe_unused]] std::string prop(const char* name) {
#if defined(__ANDROID__)
    char v[PROP_VALUE_MAX] = {0};
    __system_property_get(name, v);
    return v;
#else
    (void)name;
    return "";
#endif
}

void meminfo(double& total_gb, double& avail_gb) {
    std::ifstream f("/proc/meminfo");
    std::string k;
    unsigned long long v;
    std::string unit;
    while (f >> k >> v >> unit) {
        if (k == "MemTotal:") total_gb = v / 1024.0 / 1024.0;
        if (k == "MemAvailable:") avail_gb = v / 1024.0 / 1024.0;
    }
}

std::string ver_str(uint32_t v) {
    char b[32];
    std::snprintf(b, sizeof b, "%u.%u.%u", (v >> 22) & 0x7F, (v >> 12) & 0x3FF, v & 0xFFF);
    return b;
}

}  // namespace

HostDesc probe_host() {
    HostDesc h;
    struct utsname u {};
    uname(&u);
#if defined(__ANDROID__)
    h.platform = "android";
    h.os_version = prop("ro.build.version.sdk");  // API level, used by os_min/os_max
    h.os_build = prop("ro.build.fingerprint");
    h.device_model = prop("ro.product.manufacturer") + " " + prop("ro.product.model");
    h.soc = prop("ro.soc.model");  // API 31+
    if (h.soc.empty()) h.soc = prop("ro.board.platform");
    if (h.soc.empty()) h.soc = prop("ro.hardware");
    std::string socm = prop("ro.soc.manufacturer");
    if (!socm.empty()) h.soc = socm + " " + h.soc;
#else
    h.platform = "linux";
    h.os_version = u.release;
    h.os_build = std::string(u.sysname) + " " + u.release + " " + u.version;
    h.device_model = read_first_line("/sys/class/dmi/id/product_name");
#endif
    {
        std::ifstream f("/proc/cpuinfo");
        std::string l;
        while (std::getline(f, l)) {
            if (l.rfind("model name", 0) == 0 || l.rfind("Hardware", 0) == 0) {
                h.cpu_model = trim(l.substr(l.find(':') + 1));
                break;
            }
        }
    }
    if (h.soc.empty()) h.soc = h.cpu_model;
    h.cpu_count = ncnn::get_cpu_count();
    h.big_cpu_count = ncnn::get_big_cpu_count();
    h.little_cpu_count = ncnn::get_little_cpu_count();
#if defined(__aarch64__) || defined(__arm__)
    if (ncnn::cpu_support_arm_neon()) h.isa.push_back("neon");
    if (ncnn::cpu_support_arm_asimdhp()) h.isa.push_back("asimdhp(fp16)");
    if (ncnn::cpu_support_arm_asimddp()) h.isa.push_back("asimddp(dotprod)");
    if (ncnn::cpu_support_arm_asimdfhm()) h.isa.push_back("asimdfhm");
    if (ncnn::cpu_support_arm_bf16()) h.isa.push_back("bf16");
    if (ncnn::cpu_support_arm_i8mm()) h.isa.push_back("i8mm");
    if (ncnn::cpu_support_arm_sve()) h.isa.push_back("sve");
    if (ncnn::cpu_support_arm_sve2()) h.isa.push_back("sve2");
#elif defined(__x86_64__) || defined(__i386__)
    if (ncnn::cpu_support_x86_avx()) h.isa.push_back("avx");
    if (ncnn::cpu_support_x86_fma()) h.isa.push_back("fma");
    if (ncnn::cpu_support_x86_f16c()) h.isa.push_back("f16c");
    if (ncnn::cpu_support_x86_avx2()) h.isa.push_back("avx2");
    if (ncnn::cpu_support_x86_avx_vnni()) h.isa.push_back("avx_vnni");
    if (ncnn::cpu_support_x86_avx512()) h.isa.push_back("avx512");
#endif
    meminfo(h.ram_gb, h.ram_avail_gb);
    return h;
}

std::vector<GpuDesc> probe_gpus() {
    std::vector<GpuDesc> out;
    if (ncnn::create_gpu_instance() != 0) return out;
    HostDesc host = probe_host();
    int n = ncnn::get_gpu_count();
    for (int i = 0; i < n; ++i) {
        const ncnn::GpuInfo& gi = ncnn::get_gpu_info(i);
        GpuDesc g;
        g.index = i;
        g.id.vendor_id = gi.vendor_id();
        g.id.device_id = gi.device_id();
        g.id.device_name = gi.device_name();
        g.id.driver_version = gi.driver_version();
        g.id.api_version = gi.api_version();
        g.id.platform = host.platform;
        g.id.os_version = host.os_version;
        g.vendor = vendor_name(g.id.vendor_id);
        g.driver_version_str = format_driver_version(g.id.vendor_id, g.id.driver_version, host.platform);
        g.api_version_str = ver_str(g.id.api_version);
        switch (gi.type()) {
            case 0: g.type = "discrete"; break;
            case 1: g.type = "integrated"; break;
            case 2: g.type = "virtual"; break;
            case 3: g.type = "cpu"; break;
            default: g.type = "unknown";
        }
        if (gi.driver_name()) g.driver_name = gi.driver_name();
        g.fp16_storage = gi.support_fp16_storage();
        g.fp16_arithmetic = gi.support_fp16_arithmetic();
        g.int8_storage = gi.support_int8_storage();
        g.int8_arithmetic = gi.support_int8_arithmetic();
        const VkPhysicalDeviceMemoryProperties& mp = gi.physicalDeviceMemoryProperties();
        g.heaps = nlohmann::json::array();
        for (uint32_t h = 0; h < mp.memoryHeapCount; ++h) {
            bool dl = mp.memoryHeaps[h].flags & VK_MEMORY_HEAP_DEVICE_LOCAL_BIT;
            g.heaps.push_back({{"size_mb", mp.memoryHeaps[h].size / (1024 * 1024)}, {"device_local", dl}});
            if (dl) g.device_local_bytes += mp.memoryHeaps[h].size;
        }
        for (uint32_t t = 0; t < mp.memoryTypeCount; ++t) {
            if (mp.memoryTypes[t].propertyFlags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) {
                g.host_visible_bytes = mp.memoryHeaps[mp.memoryTypes[t].heapIndex].size;
                break;
            }
        }
        out.push_back(g);
    }
    ncnn::destroy_gpu_instance();
    return out;
}

nlohmann::json to_json(const GpuDesc& g) {
    char vid[16], did[16], drv[16];
    std::snprintf(vid, sizeof vid, "0x%04X", g.id.vendor_id);
    std::snprintf(did, sizeof did, "0x%08X", g.id.device_id);
    std::snprintf(drv, sizeof drv, "0x%08X", g.id.driver_version);
    return {{"index", g.index},
            {"name", g.id.device_name},
            {"vendor", g.vendor},
            {"vendor_id", vid},
            {"device_id", did},
            {"type", g.type},
            {"driver_name", g.driver_name},
            {"driver_version_raw", drv},
            {"driver_version", g.driver_version_str},
            {"api_version", g.api_version_str},
            {"fp16_storage", g.fp16_storage},
            {"fp16_arithmetic", g.fp16_arithmetic},
            {"int8_storage", g.int8_storage},
            {"int8_arithmetic", g.int8_arithmetic},
            {"device_local_mb", g.device_local_bytes / (1024 * 1024)},
            {"memory_heaps", g.heaps}};
}

nlohmann::json to_json(const HostDesc& h) {
    return {{"platform", h.platform},   {"os_version", h.os_version},     {"os_build", h.os_build},
            {"device_model", h.device_model}, {"soc", h.soc},             {"cpu_model", h.cpu_model},
            {"cpu_count", h.cpu_count}, {"big_cpu_count", h.big_cpu_count}, {"little_cpu_count", h.little_cpu_count},
            {"isa", h.isa},             {"ram_gb", h.ram_gb},             {"ram_avail_gb", h.ram_avail_gb}};
}

}  // namespace refocal
