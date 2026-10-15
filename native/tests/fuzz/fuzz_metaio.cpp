// libFuzzer target (11 §1: 5 min per PR, 1 h nightly): EXIF/ICC parsing of untrusted input
// metadata (ADR-0018, SEC-INP-*). Must not crash, hang or leak under ASan/UBSan.
// SPDX-License-Identifier: Apache-2.0
#include <cstddef>
#include <cstdint>

#include "image/metaio.hpp"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  // The input is an APP1 payload ("Exif\0\0" + TIFF) or a bare TIFF block, as decoders hand it.
  (void)enh::exif_orientation(data, size);
  const auto tiff = enh::exif_to_tiff(data, size);
  const auto& t = tiff.empty() ? std::vector<uint8_t>(data, data + size) : tiff;
  for (const bool gps : {false, true}) {
    const auto out = enh::exif_rewrite(t.data(), t.size(), {1, 1, gps});
    // A rewrite is itself valid input: parsing it again must not fail differently.
    if (!out.empty()) (void)enh::exif_rewrite(out.data(), out.size(), {2, 3, false});
  }
  (void)enh::icc_header_valid(data, size);
  return 0;
}
