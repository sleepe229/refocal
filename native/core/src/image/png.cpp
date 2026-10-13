// PNG input on libpng (ADR-0003). Pixels through the simplified API (palette, gray, 16-bit,
// interlace, gAMA handled by libpng); eXIf/iCCP through a header-only pass of the classic API.
// SPDX-License-Identifier: Apache-2.0
#include <csetjmp>
#include <cstdio>
#include <memory>

#include <png.h>

#include "image/decode.hpp"
#include "image/metaio.hpp"
#include "util/error.hpp"

namespace enh {
namespace {

struct File {
  FILE* f = nullptr;
  explicit File(const std::string& path) : f(std::fopen(path.c_str(), "rb")) {}
  ~File() {
    if (f) std::fclose(f);
  }
};

void on_warning(png_structp, png_const_charp) {}

// Header pass: size, alpha, and (optionally) eXIf/iCCP. Results land in heap objects because
// automatic variables modified after setjmp are indeterminate after longjmp.
void read_header(const std::string& path, ImageInfo* info, SourceMeta* meta) {
  File f(path);
  if (!f.f) fail(ENH_E_IO, "cannot open input");
  png_structp png = png_create_read_struct(PNG_LIBPNG_VER_STRING, nullptr, nullptr, on_warning);
  if (!png) fail(ENH_E_OOM, "png_create_read_struct");
  png_infop pi = png_create_info_struct(png);
  auto ok = std::make_unique<bool>(false);
  if (pi && !setjmp(png_jmpbuf(png))) {
    png_set_chunk_malloc_max(png, kMaxMetaBytes * 2);
    png_init_io(png, f.f);
    png_read_info(png, pi);
    info->w = int(png_get_image_width(png, pi));
    info->h = int(png_get_image_height(png, pi));
    const int ct = png_get_color_type(png, pi);
    info->alpha = (ct & PNG_COLOR_MASK_ALPHA) || png_get_valid(png, pi, PNG_INFO_tRNS);
    png_bytep exif = nullptr;
    png_uint_32 exif_len = 0;
    if (png_get_eXIf_1(png, pi, &exif_len, &exif) && exif) {
      info->orientation = tiff_orientation(exif, exif_len);
      if (meta && exif_len <= kMaxMetaBytes) meta->exif = exif_to_tiff(exif, exif_len);
    }
    png_charp name = nullptr;
    int comp = 0;
    png_bytep prof = nullptr;
    png_uint_32 prof_len = 0;
    if (meta && png_get_iCCP(png, pi, &name, &comp, &prof, &prof_len) && prof && prof_len <= kMaxMetaBytes) {
      meta->icc.assign(prof, prof + prof_len);
    }
    *ok = true;
  }
  png_destroy_read_struct(&png, pi ? &pi : nullptr, nullptr);
  if (!*ok) fail(ENH_E_INVALID, "PNG header is corrupt");
}

}  // namespace

ImageInfo png_probe(const std::string& path) {
  ImageInfo i;
  read_header(path, &i, nullptr);
  return i;
}

Rgb8 png_decode(const std::string& path, SourceMeta* meta) {
  ImageInfo hdr;
  read_header(path, &hdr, meta);

  png_image im{};
  im.version = PNG_IMAGE_VERSION;
  if (!png_image_begin_read_from_file(&im, path.c_str())) {
    fail(ENH_E_INVALID, std::string("PNG decode failed: ") + im.message);
  }
  im.format = PNG_FORMAT_RGB;  // alpha is composited onto `bg` by libpng
  const png_color bg{255, 255, 255};
  Rgb8 img;
  img.w = int(im.width);
  img.h = int(im.height);
  img.px.resize(PNG_IMAGE_SIZE(im));
  if (!png_image_finish_read(&im, &bg, img.px.data(), 0, nullptr)) {
    const std::string msg = im.message;
    png_image_free(&im);
    fail(ENH_E_INVALID, "PNG decode failed: " + msg);
  }
  return img;
}

}  // namespace enh
