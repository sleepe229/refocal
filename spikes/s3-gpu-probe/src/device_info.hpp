#pragma once

#include <string>
#include <vector>

#include <nlohmann/json.hpp>

#include "blocklist.hpp"

namespace refocal {

struct GpuDesc {
    int index = 0;
    GpuIdentity id;
    std::string vendor;
    std::string driver_version_str;
    std::string api_version_str;
    std::string type;  // discrete | integrated | virtual | cpu | unknown
    std::string driver_name;
    bool fp16_storage = false, fp16_arithmetic = false, int8_storage = false, int8_arithmetic = false;
    unsigned long long device_local_bytes = 0, host_visible_bytes = 0;
    nlohmann::json heaps;
};

struct HostDesc {
    std::string platform;
    std::string os_version;
    std::string os_build;
    std::string device_model;  // android ro.product.model; linux DMI product
    std::string soc;           // android ro.soc.model / ro.board.platform; linux CPU model name
    std::string cpu_model;
    int cpu_count = 0, big_cpu_count = 0, little_cpu_count = 0;
    std::vector<std::string> isa;
    double ram_gb = 0;
    double ram_avail_gb = 0;
};

HostDesc probe_host();
std::vector<GpuDesc> probe_gpus();  // creates and destroys the ncnn gpu instance
nlohmann::json to_json(const GpuDesc& g);
nlohmann::json to_json(const HostDesc& h);

}  // namespace refocal
