// Minimal EXIF reader: the orientation tag only (0.1 scope; full metaio is 0.3).
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <cstddef>
#include <cstdint>

namespace enh {

// `app1` is the payload of a JPEG APP1 marker ("Exif\0\0" + TIFF). Returns 1..8, 1 if absent.
int exif_orientation(const uint8_t* app1, size_t n);

}  // namespace enh
