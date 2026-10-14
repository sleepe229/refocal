// metaio (ADR-0003, ADR-0018): EXIF read/rewrite and the XMP AI marker, without exiv2 (GPL).
// EXIF is handled as a bare TIFF block (no "Exif\0\0" prefix): JPEG APP1 carries the prefix,
// PNG eXIf and the WebP EXIF chunk usually do not.
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace enh {

// SEC-INP-002: EXIF/XMP/ICC blocks larger than this are ignored.
inline constexpr size_t kMaxMetaBytes = 1 << 20;

// Both accept an EXIF block as any container stores it: with the "Exif\0\0" prefix (JPEG APP1,
// some PNG eXIf / WebP EXIF writers) or as a bare TIFF block.
// Orientation 1..8; 1 if absent or not valid EXIF.
int exif_orientation(const uint8_t* exif, size_t n);
// The bare TIFF block (empty if it is not one).
std::vector<uint8_t> exif_to_tiff(const uint8_t* exif, size_t n);

struct ExifPolicy {
  int width = 0, height = 0;  // of the result: PixelX/YDimension
  bool keep_gps = false;      // PRIV-META-001: GPS is removed by default
};

// Rewrites the source EXIF for the result (FR-META-001/002/007, PRIV-META-002):
//  - Orientation = 1 (it is baked into the pixels), PixelX/YDimension = result size;
//  - the thumbnail (IFD1), MakerNote, body/lens serial numbers, ImageUniqueID, embedded
//    XMP/ICC/strip data and unknown offset tags are dropped; GPS unless keep_gps;
//  - date, camera, exposure and the rest are kept byte for byte, in the source byte order.
// Returns a TIFF block, or empty if the input is not valid EXIF. Never throws on bad input.
std::vector<uint8_t> exif_rewrite(const uint8_t* tiff, size_t n, const ExifPolicy& p);

// Reads one tag from IFD0, the Exif or the GPS IFD (tests and the CLI). -1 if absent.
// Integer types only; for others returns the byte count.
int64_t exif_get(const std::vector<uint8_t>& tiff, uint16_t ifd_pointer_tag, uint16_t tag);
inline constexpr uint16_t kIfd0 = 0;
inline constexpr uint16_t kExifIfd = 0x8769;
inline constexpr uint16_t kGpsIfd = 0x8825;

// ICC profile header sanity (ICC.1 §7.2): size field equals the block size, "acsp" signature,
// v4 profiles 4-byte aligned. Source profiles failing it are dropped on read, so every encoder
// can embed what it gets (libpng refuses to write such a profile).
bool icc_header_valid(const uint8_t* icc, size_t n);

// XMP packet with Iptc4xmpExt:DigitalSourceType = compositeWithTrainedAlgorithmicMedia and
// xmp:CreatorTool (FR-META-004).
std::string ai_marker_xmp(const std::string& creator_tool);
inline constexpr const char* kXmpNamespace = "http://ns.adobe.com/xap/1.0/";
inline constexpr const char* kDigitalSourceType =
    "http://cv.iptc.org/newscodes/digitalsourcetype/compositeWithTrainedAlgorithmicMedia";

}  // namespace enh
