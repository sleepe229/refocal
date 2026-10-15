// libFuzzer target (11 §1): probe and decode of an untrusted image file through the core's own
// decoders (JPEG, PNG, WebP; HEIC/AVIF use the platform decoder, not on the host), with the
// limits of SEC-INP-002. Errors are enh::Error; anything else (crash, leak, UB) is a finding.
// SPDX-License-Identifier: Apache-2.0
#include <unistd.h>

#include <cstdint>
#include <cstdio>
#include <string>

#include "image/decode.hpp"
#include "util/error.hpp"

namespace {

// The decoders read files (ADR-0010: inbox copies). One file per process, rewritten each run.
const std::string& input_path() {
  static const std::string p = [] {
    char tmpl[] = "/tmp/enh-fuzz-XXXXXX";
    const int fd = ::mkstemp(tmpl);
    if (fd >= 0) ::close(fd);
    return std::string(tmpl);
  }();
  return p;
}

}  // namespace

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  const std::string& path = input_path();
  FILE* f = std::fopen(path.c_str(), "wb");
  if (!f) return 0;
  std::fwrite(data, 1, size, f);
  std::fclose(f);
  try {
    const enh::ImageInfo info = enh::probe_image(path);
    // Keep each run small: the limits allow 200 MP, which the fuzzer would spend its time on.
    if (int64_t(info.w) * info.h > 4'000'000) return 0;
    enh::ImageInfo decoded;
    enh::SourceMeta meta;
    const enh::Rgb8 img = enh::decode_image(path, &decoded, &meta);
    if (img.w != decoded.w || img.h != decoded.h || img.px.size() != img.stride() * img.h) {
      __builtin_trap();  // the decoder reported a size it did not produce
    }
  } catch (const enh::Error&) {
    // rejected input: expected
  }
  return 0;
}
