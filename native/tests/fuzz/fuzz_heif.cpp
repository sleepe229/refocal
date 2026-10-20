// libFuzzer target: heif_meta on arbitrary containers (FR-EXP-002). The input is our own
// HeifWriter output in practice, but the parser must hold on anything: no crash, hang or leak
// under ASan/UBSan, and a rewritten file must parse again with the metadata in place.
// SPDX-License-Identifier: Apache-2.0
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>

#include "image/heif_meta.hpp"
#include "util/error.hpp"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* data, size_t size) {
  try {
    (void)enh::heif_read_meta(data, size);
  } catch (const enh::Error&) {
  }
  enh::OutputMeta meta;
  meta.icc.assign(64, 0x5A);
  meta.exif = {'M', 'M', 0, 42, 0, 0, 0, 8, 0, 0, 0, 0, 0, 0};
  meta.xmp = "<x/>";
  std::vector<uint8_t> out;
  try {
    out = enh::heif_attach_meta(std::vector<uint8_t>(data, data + size), meta);
  } catch (const enh::Error&) {
    return 0;
  }
  const auto info = enh::heif_read_meta(out.data(), out.size());  // must not throw
  if (info.icc != meta.icc || info.exif_tiff != meta.exif || info.xmp != meta.xmp) {
    (void)std::fprintf(stderr, "metadata lost: icc %d exif %d xmp %d\n", info.icc == meta.icc,
                       info.exif_tiff == meta.exif, info.xmp == meta.xmp);
    std::abort();
  }
  return 0;
}
