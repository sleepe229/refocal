// libFuzzer target (11 §1): the .rfpack reader (SEC-INP-005) on untrusted archives. Must not
// crash, hang or leak under ASan/UBSan, and never unpack more than the directory allows.
// SPDX-License-Identifier: Apache-2.0
#include <cstddef>
#include <cstdint>
#include <cstdlib>

#include "util/error.hpp"
#include "util/zip.hpp"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  const enh::MemoryZipSource src(data, size);
  try {
    for (const enh::ZipEntry& e : enh::zip_entries(src)) {
      uint64_t n = 0;
      try {
        enh::zip_extract(src, e, [&](const uint8_t*, size_t k) { n += k; });
      } catch (const enh::Error&) {
      }
      if (n > e.size) std::abort();  // past the declared size
    }
  } catch (const enh::Error&) {
  }
  return 0;
}
