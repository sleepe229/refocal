// Image sizes, coordinates and buffer indices are ints that are never negative: decode.cpp
// (check_limits) and the tile geometry check sizes where they enter. sz() is the explicit step
// from such an int to size_t for memory and indexing (-Wsign-conversion), checked in debug builds.
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <cassert>
#include <cstddef>

namespace enh {

constexpr size_t sz(int v) {
  assert(v >= 0);
  return static_cast<size_t>(v);
}

// The index of (x, y) in a row-major buffer [w] elements wide.
constexpr size_t index2d(int x, int y, int w) { return sz(y) * sz(w) + sz(x); }

}  // namespace enh
