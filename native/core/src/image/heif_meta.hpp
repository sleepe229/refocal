// HEIF metadata (ADR-0003 amendment of 0.3, ADR-0013, ADR-0018): Android's HeifWriter writes
// neither an ICC profile nor XMP. heif_attach_meta rewrites the ISOBMFF `meta` box of such a file:
//  - the ICC profile as a `colr` (prof) property of the primary item and of its grid tiles
//    (`dimg`), replacing any prof/rICC association they had (an nclx `colr` stays);
//  - EXIF ("Exif\0\0" + TIFF, header offset 6) and XMP (`mime` application/rdf+xml) items with a
//    `cdsc` reference to the primary item; existing Exif and XMP items are dropped;
//  - item data in `idat`; `iloc` is rewritten (version 1, 64-bit fields) and absolute offsets
//    behind the `meta` box move by its growth.
// Files with a `moov` box (image sequences) are refused: their chunk offsets would move too.
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

#include "image/image.hpp"

namespace enh {

// SEC-INP-002-style bound for the container we parse (our own HeifWriter output, <= 50 MP).
inline constexpr size_t kHeifMaxBytes = size_t(512) << 20;

// Returns the rewritten file. Throws Error(ENH_E_INVALID) on a malformed or unsupported file;
// never reads outside [in].
std::vector<uint8_t> heif_attach_meta(const std::vector<uint8_t>& in, const OutputMeta& meta);

// What a reader finds for the primary item (tests, the CLI, the fuzzer): its prof/rICC `colr`
// payload, the TIFF block of its Exif item and its XMP packet (empty if absent), and the item
// data of every item still resolving to bytes of the file. Throws Error(ENH_E_INVALID).
struct HeifMetaInfo {
  uint32_t primary = 0;
  std::vector<uint8_t> icc, exif_tiff;
  std::string xmp;
  size_t items = 0;
  std::vector<uint32_t> icc_items;  // items the prof colr is associated with
};
HeifMetaInfo heif_read_meta(const uint8_t* data, size_t n);

// The bytes of item [id] (empty if it has no location resolving within the file). Throws as above.
std::vector<uint8_t> heif_item_data(const uint8_t* data, size_t n, uint32_t id);

}  // namespace enh
