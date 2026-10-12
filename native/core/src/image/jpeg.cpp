// SPDX-License-Identifier: Apache-2.0
#include "image/jpeg.hpp"

#include <csetjmp>
#include <cstring>
#include <vector>

// clang-format off
#include <jpeglib.h>
// clang-format on

#include "image/exif.hpp"
#include "util/error.hpp"

namespace enh {
namespace {

struct ErrMgr {
  jpeg_error_mgr pub;
  jmp_buf jb;
  char msg[JMSG_LENGTH_MAX];
};

void on_error(j_common_ptr c) {
  auto* e = reinterpret_cast<ErrMgr*>(c->err);
  (*c->err->format_message)(c, e->msg);
  longjmp(e->jb, 1);
}

void on_message(j_common_ptr) {}  // warnings (corrupt-but-decodable data) are not fatal

struct File {
  FILE* f = nullptr;
  explicit File(const std::string& path, const char* mode) : f(std::fopen(path.c_str(), mode)) {}
  ~File() {
    if (f) std::fclose(f);
  }
};

// Shared decode prologue. Returns false (with msg) on libjpeg error.
struct Decoder {
  jpeg_decompress_struct cinfo{};
  ErrMgr err{};
  bool created = false;
  ~Decoder() {
    if (created) jpeg_destroy_decompress(&cinfo);
  }
};

int orientation_of(jpeg_decompress_struct& cinfo) {
  for (jpeg_saved_marker_ptr m = cinfo.marker_list; m; m = m->next) {
    if (m->marker == JPEG_APP0 + 1) {
      int o = exif_orientation(m->data, m->data_length);
      if (o != 1) return o;
    }
  }
  return 1;
}

}  // namespace

bool is_jpeg_file(const std::string& path) {
  File f(path, "rb");
  if (!f.f) return false;
  unsigned char sig[3] = {};
  return std::fread(sig, 1, 3, f.f) == 3 && sig[0] == 0xFF && sig[1] == 0xD8 && sig[2] == 0xFF;
}

static Rgb8 decode_impl(const std::string& path, JpegInfo* info, bool header_only) {
  File f(path, "rb");
  if (!f.f) fail(ENH_E_IO, "cannot open input");
  Decoder d;
  d.cinfo.err = jpeg_std_error(&d.err.pub);
  d.err.pub.error_exit = on_error;
  d.err.pub.output_message = on_message;
  // Everything mutated after setjmp lives on the heap: after longjmp, automatic variables
  // changed since setjmp are indeterminate.
  auto img = std::make_unique<Rgb8>();
  auto ji = std::make_unique<JpegInfo>();
  if (setjmp(d.err.jb)) fail(ENH_E_INVALID, std::string("JPEG decode failed: ") + d.err.msg);
  jpeg_create_decompress(&d.cinfo);
  d.created = true;
  jpeg_stdio_src(&d.cinfo, f.f);
  jpeg_save_markers(&d.cinfo, JPEG_APP0 + 1, 0xFFFF);
  jpeg_read_header(&d.cinfo, TRUE);
  if (d.cinfo.jpeg_color_space == JCS_CMYK || d.cinfo.jpeg_color_space == JCS_YCCK) {
    fail(ENH_E_INVALID, "CMYK JPEG is not supported");
  }
  ji->w = int(d.cinfo.image_width);
  ji->h = int(d.cinfo.image_height);
  ji->components = d.cinfo.num_components;
  ji->orientation = orientation_of(d.cinfo);
  if (info) *info = *ji;
  if (header_only) return {};
  d.cinfo.out_color_space = JCS_RGB;
  jpeg_start_decompress(&d.cinfo);
  img->w = int(d.cinfo.output_width);
  img->h = int(d.cinfo.output_height);
  img->px.resize(size_t(img->w) * img->h * 3);
  while (d.cinfo.output_scanline < d.cinfo.output_height) {
    JSAMPROW row = img->row(int(d.cinfo.output_scanline));
    jpeg_read_scanlines(&d.cinfo, &row, 1);
  }
  jpeg_finish_decompress(&d.cinfo);
  return std::move(*img);
}

JpegInfo jpeg_probe(const std::string& path) {
  JpegInfo ji;
  decode_impl(path, &ji, true);
  return ji;
}

Rgb8 jpeg_decode(const std::string& path, JpegInfo* info) { return decode_impl(path, info, false); }

struct JpegWriter::Impl {
  jpeg_compress_struct cinfo{};
  ErrMgr err{};
  FILE* f = nullptr;
  bool created = false, finished = false;
  int w = 0;
  ~Impl() {
    if (created) jpeg_destroy_compress(&cinfo);
    if (f) std::fclose(f);
  }
};

JpegWriter::JpegWriter(const std::string& path, int w, int h, int quality)
    : impl_(std::make_unique<Impl>()) {
  Impl& m = *impl_;
  m.f = std::fopen(path.c_str(), "wb");
  if (!m.f) fail(ENH_E_IO, "cannot create output");
  m.w = w;
  m.cinfo.err = jpeg_std_error(&m.err.pub);
  m.err.pub.error_exit = on_error;
  m.err.pub.output_message = on_message;
  if (setjmp(m.err.jb)) fail(ENH_E_IO, std::string("JPEG encode failed: ") + m.err.msg);
  jpeg_create_compress(&m.cinfo);
  m.created = true;
  jpeg_stdio_dest(&m.cinfo, m.f);
  m.cinfo.image_width = JDIMENSION(w);
  m.cinfo.image_height = JDIMENSION(h);
  m.cinfo.input_components = 3;
  m.cinfo.in_color_space = JCS_RGB;
  jpeg_set_defaults(&m.cinfo);
  jpeg_set_quality(&m.cinfo, quality, TRUE);
  // No optimize_coding: two-pass Huffman keeps the coefficients of the whole image in memory
  // (~600 MB at 192 MP), which defeats streaming export from the BandStore.
  m.cinfo.optimize_coding = FALSE;
  jpeg_start_compress(&m.cinfo, TRUE);
}

JpegWriter::~JpegWriter() = default;

void JpegWriter::write_rows(const uint8_t* rgb, int rows) {
  Impl& m = *impl_;
  if (setjmp(m.err.jb)) fail(ENH_E_IO, std::string("JPEG encode failed: ") + m.err.msg);
  for (int i = 0; i < rows; ++i) {
    JSAMPROW r = const_cast<uint8_t*>(rgb + size_t(i) * m.w * 3);
    jpeg_write_scanlines(&m.cinfo, &r, 1);
  }
}

void JpegWriter::finish() {
  Impl& m = *impl_;
  if (m.finished) return;
  if (setjmp(m.err.jb)) fail(ENH_E_IO, std::string("JPEG encode failed: ") + m.err.msg);
  jpeg_finish_compress(&m.cinfo);
  m.finished = true;
  if (std::fflush(m.f) != 0 || std::ferror(m.f)) fail(ENH_E_IO, "JPEG write failed");
}

void jpeg_encode(const std::string& path, const Rgb8& img, int quality) {
  JpegWriter w(path, img.w, img.h, quality);
  w.write_rows(img.px.data(), img.h);
  w.finish();
}

}  // namespace enh
