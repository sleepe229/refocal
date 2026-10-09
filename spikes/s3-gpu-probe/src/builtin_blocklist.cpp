#include "blocklist.hpp"

namespace refocal {

// Seed built-in list after S3 (desktop only). Entries marked "unverified" come from the
// spec example (05 §11) and must be confirmed or removed by S3b on real devices.
const char* builtin_blocklist_json() {
    return R"JSON({
  "gpu_blocklist": [
    {"id": "bi-sw-llvmpipe", "vendor": "Mesa", "device_regex": "llvmpipe.*", "models": ["*"],
     "action": "cpu", "reason": "software rasterizer: on the same CPU ~2x (fp32) to ~13x (fp16) slower than ncnn CPU (S3); bench alone costs 20+ s"},
    {"id": "bi-sw-swiftshader", "vendor": "Google", "device_regex": "SwiftShader.*", "models": ["*"],
     "action": "cpu", "reason": "software rasterizer (Android emulator); same class as llvmpipe (S3)"},
    {"id": "bi-mali-g52-face", "vendor": "ARM", "device_regex": "Mali-G52.*", "driver_max": "r26p0",
     "models": ["face.*"], "action": "cpu", "reason": "unverified seed from 05 §11 (fp16 NaN in modulated conv) -> S3b"},
    {"id": "bi-powervr-all", "vendor": "ImgTec", "device_regex": "PowerVR.*", "models": ["*"],
     "action": "cpu", "reason": "unverified seed from 05 §11 -> S3b"}
  ]
})JSON";
}

}  // namespace refocal
