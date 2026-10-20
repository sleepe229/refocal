// SPDX-License-Identifier: Apache-2.0
#include "image/decode.hpp"

#include <cstdio>
#include <cstring>

#include "image/jpeg.hpp"
#include "image/metaio.hpp"
#include "util/error.hpp"
#include "util/fs.hpp"

namespace enh {
namespace {

void check_limits(const std::string& path, const ImageInfo& i) {
  if (i.w <= 0 || i.h <= 0) fail(ENH_E_INVALID, "image has no pixels");
  if (i.w > kMaxSide || i.h > kMaxSide || double(i.w) * i.h > kMaxPixels) {
    fail(ENH_E_LIMIT, "image is larger than " + std::to_string(kMaxSide) + " px or 200 MP");
  }
  if (fs::file_size(path) > kMaxFileBytes) fail(ENH_E_LIMIT, "file is larger than 200 MB");
}

bool is_core_format(const std::string& f) { return f == "jpeg" || f == "png" || f == "webp"; }

}  // namespace

std::string sniff_format(const std::string& path) {
  unsigned char b[32] = {};
  FILE* f = std::fopen(path.c_str(), "rb");
  if (!f) fail(ENH_E_IO, "cannot open input");
  const size_t n = std::fread(b, 1, sizeof b, f);
  (void)std::fclose(f);  // read only
  if (n >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return "jpeg";
  if (n >= 8 && std::memcmp(b, "\x89PNG\r\n\x1a\n", 8) == 0) return "png";
  if (n >= 12 && std::memcmp(b, "RIFF", 4) == 0 && std::memcmp(b + 8, "WEBP", 4) == 0)
    return "webp";
  if (n >= 12 && std::memcmp(b + 4, "ftyp", 4) == 0) {
    const std::string brand(reinterpret_cast<char*>(b + 8), 4);
    if (brand == "avif" || brand == "avis") return "avif";
    if (brand == "heic" || brand == "heix" || brand == "hevc" || brand == "hevx" ||
        brand == "heim" || brand == "heis" || brand == "mif1" || brand == "msf1") {
      return "heif";
    }
  }
  if (n >= 6 && (std::memcmp(b, "GIF87a", 6) == 0 || std::memcmp(b, "GIF89a", 6) == 0))
    return "gif";
  if (n >= 2 && b[0] == 'B' && b[1] == 'M') return "bmp";
  return "";
}

ImageInfo probe_image(const std::string& path) {
  const std::string fmt = sniff_format(path);
  ImageInfo i;
  if (fmt == "jpeg") {
    JpegInfo j = jpeg_probe(path);
    i.w = j.w;
    i.h = j.h;
    i.orientation = j.orientation;
    i.jpeg_quality = j.quality;
  } else if (fmt == "png") {
    i = png_probe(path);
  } else if (fmt == "webp") {
    i = webp_probe(path);
  } else if (platform_decoder_available()) {
    i = platform_probe(path);
  } else {
    fail(ENH_E_INVALID, fmt.empty() ? "unsupported input format"
                                    : fmt + " input is not supported on this platform");
  }
  i.format = fmt.empty() ? "other" : fmt;
  check_limits(path, i);
  return i;
}

Rgb8 decode_image(const std::string& path, ImageInfo* info, SourceMeta* meta) {
  ImageInfo i = probe_image(path);
  if (info) *info = i;
  if (meta) *meta = {};
  Rgb8 img;
  if (i.format == "jpeg") {
    img = jpeg_decode(path, nullptr, meta);
  } else if (i.format == "png") {
    img = png_decode(path, meta);
  } else if (i.format == "webp") {
    img = webp_decode(path, meta);
  } else {
    if (is_core_format(i.format)) fail(ENH_E_INTERNAL, "unreachable");
    return platform_decode(path, meta ? &meta->alpha : nullptr);
  }
  if (meta && !icc_header_valid(meta->icc.data(), meta->icc.size())) meta->icc.clear();
  return img;
}

void rgba_to_rgb_on_white(std::vector<uint8_t>& px, size_t pixels, bool premultiplied,
                          std::vector<uint8_t>* alpha) {
  uint8_t* p = px.data();
  if (alpha) {
    alpha->resize(pixels);
    for (size_t i = 0; i < pixels; ++i) (*alpha)[i] = p[i * 4 + 3];
  }
  for (size_t i = 0; i < pixels; ++i) {  // dst index <= src index: safe in place
    const uint8_t* s = p + i * 4;
    uint8_t* d = p + i * 3;
    const unsigned a = s[3], na = 255 - a;
    for (int c = 0; c < 3; ++c) {
      const unsigned v = premultiplied ? s[c] + na : (s[c] * a + 255 * na + 127) / 255;
      d[c] = uint8_t(v > 255 ? 255 : v);
    }
  }
  px.resize(pixels * 3);
}

}  // namespace enh
