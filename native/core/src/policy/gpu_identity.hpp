// SPDX-License-Identifier: Apache-2.0
#pragma once

#include "policy/blocklist.hpp"

namespace enh {

// Identity of Vulkan device `index` for blocklist matching and the crash sentinel.
GpuIdentity gpu_identity(int index);

}  // namespace enh
