// PNG input and output on libpng (ADR-0003, FR-EXP-001). Pixels through the simplified API (palette, gray, 16-bit,
// interlace, gAMA handled by libpng); eXIf/iCCP through a header-only pass of the classic API.
// SPDX-License-Identifier: Apache-2.0
#include <csetjmp>
#include <cstdio>
#include <memory>

#include <png.h>

#include "image/decode.hpp"
#include "image/encode.hpp"
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

// ---- output ----
// libpng reports errors by longjmp: every setjmp scope below holds only trivially destructible
// locals, and the metadata is copied into Impl before the first one.

namespace {
[[noreturn]] void on_write_error(png_structp png, png_const_charp) { png_longjmp(png, 1); }
}  // namespace

struct PngWriter::Impl {
  FILE* f = nullptr;
  png_structp png = nullptr;
  png_infop info = nullptr;
  int w = 0;
  bool finished = false;
  JpegMeta meta;
  ~Impl() {
    if (png) png_destroy_write_struct(&png, info ? &info : nullptr);
    if (f) std::fclose(f);
  }
};

PngWriter::PngWriter(const std::string& path, int w, int h, const JpegMeta* meta)
    : impl_(std::make_unique<Impl>()) {
  Impl& m = *impl_;
  if (meta) m.meta = *meta;
  m.w = w;
  m.f = std::fopen(path.c_str(), "wb");
  if (!m.f) fail(ENH_E_IO, "cannot create output");
  m.png = png_create_write_struct(PNG_LIBPNG_VER_STRING, nullptr, on_write_error, on_warning);
  if (!m.png) fail(ENH_E_OOM, "png_create_write_struct");
  m.info = png_create_info_struct(m.png);
  if (!m.info) fail(ENH_E_OOM, "png_create_info_struct");
  png_text xmp{};
  if (setjmp(png_jmpbuf(m.png))) fail(ENH_E_IO, "PNG encode failed");
  png_init_io(m.png, m.f);
  // A broken source ICC profile must not fail the export: libpng then drops the chunk.
  png_set_benign_errors(m.png, 1);
  png_set_option(m.png, PNG_SKIP_sRGB_CHECK_PROFILE, PNG_OPTION_ON);
  png_set_compression_level(m.png, 6);
  png_set_IHDR(m.png, m.info, png_uint_32(w), png_uint_32(h), 8, PNG_COLOR_TYPE_RGB,
               PNG_INTERLACE_NONE, PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT);
  if (!m.meta.icc.empty()) {  // validated on read (icc_header_valid)
    png_set_iCCP(m.png, m.info, "ICC Profile", PNG_COMPRESSION_TYPE_BASE, m.meta.icc.data(),
                 png_uint_32(m.meta.icc.size()));
  }
  if (!m.meta.exif.empty()) {
    png_set_eXIf_1(m.png, m.info, png_uint_32(m.meta.exif.size()), m.meta.exif.data());
  }
  if (!m.meta.xmp.empty()) {
    xmp.compression = PNG_ITXT_COMPRESSION_NONE;
    xmp.key = const_cast<char*>("XML:com.adobe.xmp");
    xmp.text = m.meta.xmp.data();
    xmp.itxt_length = m.meta.xmp.size();
    xmp.lang = const_cast<char*>("");  // libpng memcpy()s both even when empty
    xmp.lang_key = const_cast<char*>("");
    png_set_text(m.png, m.info, &xmp, 1);
  }
  png_write_info(m.png, m.info);
}

PngWriter::~PngWriter() = default;

void PngWriter::write_rows(const uint8_t* rgb, int rows) {
  Impl& m = *impl_;
  if (setjmp(png_jmpbuf(m.png))) fail(ENH_E_IO, "PNG encode failed");
  for (int r = 0; r < rows; ++r) {
    png_write_row(m.png, const_cast<png_bytep>(rgb + size_t(r) * m.w * 3));
  }
}

void PngWriter::finish() {
  Impl& m = *impl_;
  if (m.finished) return;
  if (setjmp(png_jmpbuf(m.png))) fail(ENH_E_IO, "PNG encode failed");
  png_write_end(m.png, m.info);
  m.finished = true;
  if (std::fflush(m.f) != 0 || std::ferror(m.f)) fail(ENH_E_IO, "PNG write failed");
}

}  // namespace enh
