// enh_device_probe: CPU and Vulkan device description (inputs for DeviceCaps / tiers, ADR-0017).
// SPDX-License-Identifier: Apache-2.0
#include "probe.hpp"

#include <cpu.h>
#include <gpu.h>

#include "json_util.hpp"

namespace enh {

std::string device_probe_json() {
  std::string j = "{\"schema\":1,\"cpu\":{";
  j += "\"count\":" + std::to_string(ncnn::get_cpu_count());
  j += ",\"big\":" + std::to_string(ncnn::get_big_cpu_count());
  j += ",\"little\":" + std::to_string(ncnn::get_little_cpu_count());
  j += "},\"gpus\":[";
#if NCNN_VULKAN
  int n = ncnn::get_gpu_count();
  for (int i = 0; i < n; ++i) {
    const ncnn::GpuInfo& g = ncnn::get_gpu_info(i);
    if (i) j += ',';
    j += "{\"index\":" + std::to_string(i) + ",\"name\":";
    json_str(j, g.device_name());
    j += ",\"vendor_id\":" + std::to_string(g.vendor_id());
    j += ",\"device_id\":" + std::to_string(g.device_id());
    j += ",\"driver_version\":" + std::to_string(g.driver_version());
    j += ",\"api_version\":" + std::to_string(g.api_version());
    j += ",\"type\":" + std::to_string(g.type());
    j += ",\"fp16_storage\":" + std::string(g.support_fp16_storage() ? "true" : "false");
    j += ",\"int8_storage\":" + std::string(g.support_int8_storage() ? "true" : "false");
    j += '}';
  }
#endif
  j += "],\"vulkan_built\":";
  j += NCNN_VULKAN ? "true" : "false";
  j += '}';
  return j;
}

}  // namespace enh
