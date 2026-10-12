// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <cstdint>
#include <vector>

namespace enh {

// Interleaved RGB8, row-major, no padding.
struct Rgb8 {
  int w = 0, h = 0;
  std::vector<uint8_t> px;
  size_t stride() const { return size_t(w) * 3; }
  uint8_t* row(int y) { return px.data() + size_t(y) * stride(); }
  const uint8_t* row(int y) const { return px.data() + size_t(y) * stride(); }
};

}  // namespace enh
