// SPDX-License-Identifier: Apache-2.0
#include "image/exif.hpp"

#include <cstring>

namespace enh {

int exif_orientation(const uint8_t* d, size_t n) {
  if (n < 14 || std::memcmp(d, "Exif\0\0", 6) != 0) return 1;
  const uint8_t* t = d + 6;  // TIFF header
  size_t tn = n - 6;
  bool le;
  if (t[0] == 'I' && t[1] == 'I') le = true;
  else if (t[0] == 'M' && t[1] == 'M') le = false;
  else return 1;
  auto u16 = [&](size_t o) -> uint32_t {
    return le ? uint32_t(t[o]) | uint32_t(t[o + 1]) << 8 : uint32_t(t[o]) << 8 | uint32_t(t[o + 1]);
  };
  auto u32 = [&](size_t o) -> uint32_t {
    return le ? u16(o) | u16(o + 2) << 16 : u16(o) << 16 | u16(o + 2);
  };
  if (u16(2) != 42) return 1;
  size_t ifd = u32(4);
  if (ifd + 2 > tn) return 1;
  uint32_t count = u16(ifd);
  for (uint32_t i = 0; i < count; ++i) {
    size_t e = ifd + 2 + size_t(i) * 12;
    if (e + 12 > tn) return 1;
    if (u16(e) == 0x0112) {  // Orientation, SHORT
      uint32_t v = u16(e + 8);
      return v >= 1 && v <= 8 ? int(v) : 1;
    }
  }
  return 1;
}

}  // namespace enh
