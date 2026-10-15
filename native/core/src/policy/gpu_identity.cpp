// SPDX-License-Identifier: Apache-2.0
#include "policy/gpu_identity.hpp"

#include <gpu.h>
#include <sys/utsname.h>

#if defined(__ANDROID__)
#include <sys/system_properties.h>
#endif

namespace enh {

GpuIdentity gpu_identity(int index) {
  GpuIdentity g;
#if defined(__ANDROID__)
  g.platform = "android";
  char sdk[PROP_VALUE_MAX] = {0};
  __system_property_get("ro.build.version.sdk", sdk);
  g.os_version = sdk;
#elif defined(__APPLE__)
  g.platform = "ios";
#else
  g.platform = "linux";
  utsname u;
  if (uname(&u) == 0) g.os_version = u.release;
#endif
#if NCNN_VULKAN
  if (index >= 0 && index < ncnn::get_gpu_count()) {
    const ncnn::GpuInfo& i = ncnn::get_gpu_info(index);
    g.vendor_id = i.vendor_id();
    g.device_id = i.device_id();
    g.device_name = i.device_name();
    g.driver_version = i.driver_version();
    g.api_version = i.api_version();
  }
#else
  (void)index;
#endif
  return g;
}

}  // namespace enh
