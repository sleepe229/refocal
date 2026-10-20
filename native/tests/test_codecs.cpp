// Codecs and metadata (ADR-0003, ADR-0018): metaio EXIF rewrite in both byte orders, the AI
// marker, PNG/WebP decoding (alpha, 16-bit, animation, eXIf/iCCP/EXIF chunks), format sniffing,
// SEC-INP-002 limits, and JPEG metadata round trips. Malformed EXIF must never crash (ASan).
// SPDX-License-Identifier: Apache-2.0
#include <png.h>
#include <webp/encode.h>

#include <algorithm>
#include <csetjmp>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include "image/decode.hpp"
#include "image/encode.hpp"
#include "image/jpeg.hpp"
#include "image/metaio.hpp"
#include "util/error.hpp"
#include "util/fs.hpp"
#include "util/size.hpp"

static int fails = 0;
#define CHECK(c)                                                        \
  do {                                                                  \
    if (!(c)) {                                                         \
      std::fprintf(stderr, "%s:%d: FAIL %s\n", __FILE__, __LINE__, #c); \
      ++fails;                                                          \
    }                                                                   \
  } while (0)

using namespace enh;
using Bytes = std::vector<uint8_t>;

// ---- a tiny independent TIFF writer for test input --------------------------------------------

struct TEntry {
  uint16_t tag, type;
  uint32_t count;
  Bytes data;    // already in the target byte order
  int sub = -1;  // index of a sub-IFD (pointer entry)
};

struct TiffBuilder {
  bool le;
  std::vector<std::vector<TEntry>> ifds;  // ifds[0] = IFD0
  int next_of_ifd0 = -1;                  // IFD1 index (thumbnail)

  Bytes u16(uint32_t v) const {
    return le ? Bytes{uint8_t(v), uint8_t(v >> 8)} : Bytes{uint8_t(v >> 8), uint8_t(v)};
  }
  Bytes u32(uint32_t v) const {
    Bytes b = {uint8_t(v), uint8_t(v >> 8), uint8_t(v >> 16), uint8_t(v >> 24)};
    if (!le) std::reverse(b.begin(), b.end());
    return b;
  }
  TEntry shrt(uint16_t tag, uint16_t v) const { return {tag, 3, 1, u16(v)}; }
  TEntry lng(uint16_t tag, uint32_t v) const { return {tag, 4, 1, u32(v)}; }
  TEntry ascii(uint16_t tag, const std::string& s) const {
    Bytes b(s.begin(), s.end());
    b.push_back(0);
    return {tag, 2, uint32_t(b.size()), b};
  }
  TEntry undef(uint16_t tag, Bytes b) const { return {tag, 7, uint32_t(b.size()), b}; }
  TEntry ptr(uint16_t tag, int sub) const { return {tag, 4, 1, {}, sub}; }

  Bytes build() const {
    Bytes out = le ? Bytes{'I', 'I', 42, 0} : Bytes{'M', 'M', 0, 42};
    auto put = [&](size_t pos, const Bytes& b) { std::copy(b.begin(), b.end(), out.data() + pos); };
    Bytes off = u32(8);
    out.insert(out.end(), off.begin(), off.end());
    std::vector<size_t> ifd_pos(ifds.size());
    std::vector<std::pair<size_t, int>> fix;  // value position -> sub index
    size_t next_pos = 0;
    for (size_t i = 0; i < ifds.size(); ++i) {
      if (out.size() % 2) out.push_back(0);
      ifd_pos[i] = out.size();
      const auto& es = ifds[i];
      const size_t data0 = out.size() + 2 + 12 * es.size() + 4;
      Bytes data;
      Bytes n = u16(uint32_t(es.size()));
      out.insert(out.end(), n.begin(), n.end());
      for (const auto& e : es) {
        for (const Bytes& b : {u16(e.tag), u16(e.type), u32(e.count)})
          out.insert(out.end(), b.begin(), b.end());
        if (e.sub >= 0) {
          fix.push_back({out.size(), e.sub});
          out.insert(out.end(), 4, 0);
        } else if (e.data.size() <= 4) {
          Bytes v = e.data;
          v.resize(4, 0);
          out.insert(out.end(), v.begin(), v.end());
        } else {
          Bytes o = u32(uint32_t(data0 + data.size()));
          out.insert(out.end(), o.begin(), o.end());
          data.insert(data.end(), e.data.begin(), e.data.end());
          if (data.size() % 2) data.push_back(0);
        }
      }
      if (i == 0) next_pos = out.size();
      out.insert(out.end(), 4, 0);
      out.insert(out.end(), data.begin(), data.end());
    }
    for (auto [pos, sub] : fix) put(pos, u32(uint32_t(ifd_pos[sz(sub)])));
    if (next_of_ifd0 >= 0) put(next_pos, u32(uint32_t(ifd_pos[sz(next_of_ifd0)])));
    return out;
  }
};

// IFD0 {Make, Orientation 6, Exif ptr, GPS ptr}; Exif {DateTimeOriginal, MakerNote,
// BodySerialNumber, PixelXDimension SHORT 100, Interop ptr}; GPS {GPSVersionID};
// Interop {InteropIndex}; IFD1 {JPEGInterchangeFormat...} as the thumbnail.
static Bytes camera_exif(bool le) {
  TiffBuilder t{le, {}, -1};
  t.ifds.resize(5);
  t.ifds[0] = {t.ascii(0x010F, "Canon"), t.shrt(0x0112, 6), t.ptr(0x8769, 1), t.ptr(0x8825, 2)};
  t.ifds[1] = {t.ascii(0x9003, "2024:05:01 10:20:30"), t.undef(0x927C, Bytes(40, 0xAB)),
               t.ascii(0xA431, "SERIAL123"), t.shrt(0xA002, 100), t.ptr(0xA005, 3)};
  t.ifds[2] = {{0x0000, 1, 4, {2, 3, 0, 0}}};
  t.ifds[3] = {t.ascii(0x0001, "R98")};
  t.ifds[4] = {t.lng(0x0201, 0), t.lng(0x0202, 0)};
  t.next_of_ifd0 = 4;
  return t.build();
}

static bool contains(const Bytes& hay, const std::string& needle) {
  const Bytes n(needle.begin(), needle.end());
  return std::search(hay.begin(), hay.end(), n.begin(), n.end()) != hay.end();
}

static void test_exif_rewrite() {
  for (bool le : {true, false}) {
    const Bytes src = camera_exif(le);
    CHECK(exif_orientation(src.data(), src.size()) == 6);
    CHECK(exif_get(src, kGpsIfd, 0x0000) >= 0);
    CHECK(exif_get(src, kExifIfd, 0xA431) > 0);

    const Bytes out = exif_rewrite(src.data(), src.size(), {4000, 3000, false});
    CHECK(!out.empty());
    CHECK(out[0] == (le ? 'I' : 'M'));                     // source byte order kept
    CHECK(exif_orientation(out.data(), out.size()) == 1);  // FR-META-001
    CHECK(exif_get(out, kExifIfd, 0xA002) == 4000);        // FR-META-007
    CHECK(exif_get(out, kExifIfd, 0xA003) == 3000);
    CHECK(exif_get(out, kIfd0, 0x010F) == 6);                               // Make kept ("Canon\0")
    CHECK(contains(out, "Canon") && contains(out, "2024:05:01 10:20:30"));  // FR-META-002
    CHECK(exif_get(out, kGpsIfd, 0x0000) == -1);                            // PRIV-META-001
    CHECK(exif_get(out, kExifIfd, 0x927C) == -1);  // MakerNote, PRIV-META-002
    CHECK(exif_get(out, kExifIfd, 0xA431) == -1 && !contains(out, "SERIAL123"));
    CHECK(contains(out, "R98"));  // interop IFD survives
    CHECK(!contains(out, std::string(40, char(0xAB))));

    const Bytes gps = exif_rewrite(src.data(), src.size(), {10, 10, true});
    CHECK(exif_get(gps, kGpsIfd, 0x0000) >= 0);
    // A rewrite of the rewrite is stable.
    const Bytes again = exif_rewrite(out.data(), out.size(), {4000, 3000, false});
    CHECK(again == out);
  }
  // Prefix handling and garbage.
  Bytes app1 = {'E', 'x', 'i', 'f', 0, 0};
  const Bytes cam = camera_exif(true);
  app1.insert(app1.end(), cam.begin(), cam.end());
  CHECK(exif_to_tiff(app1.data(), app1.size()) == cam);
  CHECK(exif_orientation(app1.data(), app1.size()) == 6);
  CHECK(exif_to_tiff(reinterpret_cast<const uint8_t*>("garbage!!"), 9).empty());
  CHECK(exif_rewrite(reinterpret_cast<const uint8_t*>("II*\0\xff\xff\xff\xff"), 8, {1, 1}).empty());
  // Deterministic mutation fuzz: no crash, no hang (run under ASan in CI).
  uint32_t r = 1;
  for (int it = 0; it < 3000; ++it) {
    Bytes m = camera_exif(it % 2 == 0);
    for (int k = 0; k < 1 + it % 7; ++k) {
      r = r * 1103515245u + 12345u;
      m[(r >> 8) % m.size()] = uint8_t(r >> 24);
    }
    if (it % 5 == 0) m.resize((r >> 4) % m.size());
    (void)exif_rewrite(m.data(), m.size(), {1, 1, it % 3 == 0});
    (void)exif_orientation(m.data(), m.size());
  }
}

static void test_xmp() {
  const std::string x = ai_marker_xmp("Refocal <1.0> & co");
  CHECK(x.find(kDigitalSourceType) != std::string::npos);
  CHECK(x.find("xmp:CreatorTool=\"Refocal &lt;1.0&gt; &amp; co\"") != std::string::npos);
  CHECK(x.rfind("<?xpacket begin=", 0) == 0);
}

// ---- PNG -------------------------------------------------------------------------------------

static void write_png_simple(const std::string& path, int w, int h, uint32_t format,
                             const Bytes& px) {
  png_image im{};
  im.version = PNG_IMAGE_VERSION;
  im.width = uint32_t(w);
  im.height = uint32_t(h);
  im.format = format;
  CHECK(png_image_write_to_file(&im, path.c_str(), 0, px.data(), 0, nullptr));
}

// Classic API: RGB8 with eXIf and iCCP chunks.
static void write_png_meta(const std::string& path, int w, int h, const Bytes& exif,
                           const Bytes& icc) {
  FILE* f = std::fopen(path.c_str(), "wb");
  png_structp png = png_create_write_struct(PNG_LIBPNG_VER_STRING, nullptr, nullptr, nullptr);
  png_infop info = png_create_info_struct(png);
  if (setjmp(png_jmpbuf(png))) {
    CHECK(false);
    png_destroy_write_struct(&png, &info);
    std::fclose(f);
    return;
  }
  png_init_io(png, f);
  png_set_IHDR(png, info, uint32_t(w), uint32_t(h), 8, PNG_COLOR_TYPE_RGB, PNG_INTERLACE_NONE,
               PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT);
  png_set_eXIf_1(png, info, uint32_t(exif.size()), const_cast<png_bytep>(exif.data()));
  png_set_iCCP(png, info, "test", 0, icc.data(), uint32_t(icc.size()));
  png_write_info(png, info);
  Bytes row(size_t(w) * 3, 128);
  for (int y = 0; y < h; ++y) png_write_row(png, row.data());
  png_write_end(png, info);
  png_destroy_write_struct(&png, &info);
  std::fclose(f);
}

// A syntactically valid ICC header is enough for libpng's iCCP checks. The body is noise: libpng
// 1.6.59 drops iCCP chunks shorter than ~90 bytes ("too short"), real profiles never are.
static Bytes fake_icc() {
  Bytes p(512, 0);
  uint32_t r = 7;
  for (size_t i = 132; i < p.size(); ++i) p[i] = uint8_t((r = r * 1103515245u + 12345u) >> 24);
  const uint32_t n = uint32_t(p.size());
  p[0] = uint8_t(n >> 24);
  p[1] = uint8_t(n >> 16);
  p[2] = uint8_t(n >> 8);
  p[3] = uint8_t(n);
  std::memcpy(&p[12], "mntr", 4);
  std::memcpy(&p[16], "RGB ", 4);
  std::memcpy(&p[20], "XYZ ", 4);
  std::memcpy(&p[36], "acsp", 4);
  p[64] = 0;
  p[68] = 0;
  p[69] = 0;
  p[70] = 0xF6;
  p[71] = 0xD6;  // D50 illuminant
  p[72] = 0;
  p[73] = 1;
  p[74] = 0;
  p[75] = 0;
  p[76] = 0;
  p[77] = 0;
  p[78] = 0xD3;
  p[79] = 0x2D;
  return p;
}

static void test_png(const std::string& dir) {
  {  // RGBA: transparent -> white, opaque kept, half -> blend
    Bytes px = {255, 0, 0, 255, 0, 0, 255, 0, 0, 0, 0, 128, 10, 20, 30, 255};
    const std::string p = fs::join(dir, "a.png");
    write_png_simple(p, 2, 2, PNG_FORMAT_RGBA, px);
    CHECK(sniff_format(p) == "png");
    ImageInfo i;
    Rgb8 img = decode_image(p, &i);
    CHECK(i.format == "png" && i.alpha && i.w == 2 && i.h == 2);
    CHECK(img.w == 2 && img.h == 2);
    CHECK(img.px[0] == 255 && img.px[1] == 0 && img.px[2] == 0);      // opaque red
    CHECK(img.px[3] == 255 && img.px[4] == 255 && img.px[5] == 255);  // transparent -> white
    CHECK(img.px[6] > 100 &&
          img.px[6] < 200);  // 50% black on white (libpng blends in linear light)
    CHECK(img.px[9] == 10 && img.px[10] == 20 && img.px[11] == 30);
  }
  {  // 16-bit linear gray -> 8-bit sRGB RGB (libpng converts)
    Bytes px(4 * 3 * 2, 0);
    const std::string p = fs::join(dir, "g16.png");
    write_png_simple(p, 4, 3, PNG_FORMAT_LINEAR_Y, px);
    ImageInfo i;
    Rgb8 img = decode_image(p, &i);
    CHECK(img.w == 4 && img.h == 3 && !i.alpha && img.px[0] == 0);
  }
  {  // eXIf + iCCP survive, orientation is read
    TiffBuilder t{true, {}, -1};
    t.ifds.resize(1);
    t.ifds[0] = {t.ascii(0x010F, "Pixel"), t.shrt(0x0112, 8)};
    const Bytes exif = t.build(), icc = fake_icc();
    const std::string p = fs::join(dir, "m.png");
    write_png_meta(p, 5, 4, exif, icc);
    ImageInfo i;
    SourceMeta m;
    Rgb8 img = decode_image(p, &i, &m);
    CHECK(i.orientation == 8 && img.w == 5 && img.h == 4);
    CHECK(m.exif == exif);
    CHECK(m.icc == icc);
  }
  {  // header beyond SEC-INP-002 -> LIMIT before decoding
    Bytes px(30001, 0);
    const std::string p = fs::join(dir, "wide.png");
    write_png_simple(p, 30001, 1, PNG_FORMAT_GRAY, px);
    bool limit = false;
    try {
      probe_image(p);
    } catch (const Error& e) {
      limit = e.status() == ENH_E_LIMIT;
    }
    CHECK(limit);
  }
  {  // truncated
    const std::string p = fs::join(dir, "a.png"), t = fs::join(dir, "trunc.png");
    Bytes b = fs::read_all(p);
    b.resize(b.size() - 20);
    fs::write_atomic(t, b.data(), b.size(), false);
    bool invalid = false;
    try {
      decode_image(t);
    } catch (const Error& e) {
      invalid = e.status() == ENH_E_INVALID;
    }
    CHECK(invalid);
  }
}

// ---- WebP ------------------------------------------------------------------------------------

static void le32(Bytes& b, uint32_t v) {
  for (int i = 0; i < 4; ++i) b.push_back(uint8_t(v >> (8 * i)));
}
static void le24(Bytes& b, uint32_t v) {
  for (int i = 0; i < 3; ++i) b.push_back(uint8_t(v >> (8 * i)));
}
static void chunk(Bytes& out, const char* cc, const Bytes& payload) {
  out.insert(out.end(), cc, cc + 4);
  le32(out, uint32_t(payload.size()));
  out.insert(out.end(), payload.begin(), payload.end());
  if (payload.size() % 2) out.push_back(0);
}

// Simple-format lossless WebP -> extended format with ICCP and EXIF chunks (RIFF by hand,
// libwebpmux is not built).
static Bytes extend_webp(const Bytes& simple, int w, int h, bool alpha, const Bytes& icc,
                         const Bytes& exif) {
  Bytes body = {'W', 'E', 'B', 'P'};
  Bytes vp8x;
  vp8x.push_back(
      uint8_t((icc.empty() ? 0 : 0x20) | (alpha ? 0x10 : 0) | (exif.empty() ? 0 : 0x08)));
  vp8x.insert(vp8x.end(), 3, 0);
  le24(vp8x, uint32_t(w - 1));
  le24(vp8x, uint32_t(h - 1));
  chunk(body, "VP8X", vp8x);
  if (!icc.empty()) chunk(body, "ICCP", icc);
  body.insert(body.end(), simple.begin() + 12, simple.end());  // the VP8L chunk
  if (!exif.empty()) chunk(body, "EXIF", exif);
  Bytes out = {'R', 'I', 'F', 'F'};
  le32(out, uint32_t(body.size()));
  out.insert(out.end(), body.begin(), body.end());
  return out;
}

static void test_webp(const std::string& dir) {
  const int w = 6, h = 4;
  Bytes rgba(sz(w) * sz(h) * 4);
  for (size_t i = 0; i < sz(w) * sz(h); ++i) {
    rgba[i * 4] = uint8_t(i * 10);
    rgba[i * 4 + 1] = uint8_t(255 - i * 10);
    rgba[i * 4 + 2] = 77;
    rgba[i * 4 + 3] = i == 0 ? 0 : 255;  // one transparent pixel
  }
  uint8_t* enc = nullptr;
  const size_t n = WebPEncodeLosslessRGBA(rgba.data(), w, h, w * 4, &enc);
  CHECK(n > 0);
  const Bytes simple(enc, enc + n);
  WebPFree(enc);

  {
    const std::string p = fs::join(dir, "s.webp");
    fs::write_atomic(p, simple.data(), simple.size(), false);
    CHECK(sniff_format(p) == "webp");
    ImageInfo i;
    Rgb8 img = decode_image(p, &i);
    CHECK(i.format == "webp" && i.alpha && !i.animated && img.w == w && img.h == h);
    CHECK(img.px[0] == 255 && img.px[1] == 255 && img.px[2] == 255);  // transparent -> white
    bool exact = true;
    for (size_t k = 1; k < sz(w) * sz(h); ++k)
      for (size_t c = 0; c < 3; ++c) exact = exact && img.px[k * 3 + c] == rgba[k * 4 + c];
    CHECK(exact);  // lossless
  }
  {
    TiffBuilder t{false, {}, -1};
    t.ifds.resize(1);
    t.ifds[0] = {t.shrt(0x0112, 3)};
    const Bytes exif = t.build(), icc = fake_icc();
    const Bytes ext = extend_webp(simple, w, h, true, icc, exif);
    const std::string p = fs::join(dir, "x.webp");
    fs::write_atomic(p, ext.data(), ext.size(), false);
    ImageInfo i;
    SourceMeta m;
    Rgb8 img = decode_image(p, &i, &m);
    CHECK(img.w == w && i.orientation == 3);
    CHECK(m.exif == exif && m.icc == icc);
  }
  {
    const std::string p = fs::join(dir, "bad.webp");
    fs::write_atomic(p, std::string("RIFF\x10\0\0\0WEBPVP8 junk"));
    bool invalid = false;
    try {
      decode_image(p);
    } catch (const Error& e) {
      invalid = e.status() == ENH_E_INVALID;
    }
    CHECK(invalid);
  }
}

// ---- sniffing, platform formats, JPEG metadata round trip ----------------------------------

static void test_sniff(const std::string& dir) {
  const std::string p = fs::join(dir, "h.heic");
  fs::write_atomic(p, std::string("\0\0\0\x18"
                                  "ftypheic\0\0\0\0mif1heic",
                                  24));
  CHECK(sniff_format(p) == "heif");
  fs::write_atomic(p, std::string("\0\0\0\x18"
                                  "ftypavif\0\0\0\0",
                                  16));
  CHECK(sniff_format(p) == "avif");
  fs::write_atomic(p, std::string("GIF89a...."));
  CHECK(sniff_format(p) == "gif");
  fs::write_atomic(p, std::string("hello"));
  CHECK(sniff_format(p).empty());
  if (!platform_decoder_available()) {  // desktop: a clear INVALID, not a crash
    bool invalid = false;
    try {
      probe_image(p);
    } catch (const Error& e) {
      invalid = e.status() == ENH_E_INVALID;
    }
    CHECK(invalid);
  }
}

static Bytes find_app1(const Bytes& jpg, const std::string& prefix) {
  for (size_t i = 2; i + 4 < jpg.size() && jpg[i] == 0xFF;) {
    const uint8_t m = jpg[i + 1];
    const size_t len = size_t(jpg[i + 2]) << 8 | jpg[i + 3];
    if (m == 0xDA) break;
    if (m == 0xE1 && len >= 2 + prefix.size() &&
        std::memcmp(&jpg[i + 4], prefix.data(), prefix.size()) == 0)
      return Bytes(jpg.begin() + long(i + 4), jpg.begin() + long(i + 2 + len));
    i += 2 + len;
  }
  return {};
}

static void test_jpeg_meta(const std::string& dir) {
  Rgb8 img;
  img.w = 16;
  img.h = 8;
  img.px.assign(16 * 8 * 3, 90);
  OutputMeta meta;
  meta.exif = exif_rewrite(camera_exif(false).data(), camera_exif(false).size(), {16, 8, false});
  meta.xmp = ai_marker_xmp("Refocal test");
  meta.icc = fake_icc();
  const std::string p = fs::join(dir, "meta.jpg");
  {
    JpegWriter w(p, img.w, img.h, 90, &meta);
    w.write_rows(img.px.data(), img.h);
    w.finish();
  }
  const Bytes jpg = fs::read_all(p);
  CHECK(jpg[2] == 0xFF && jpg[3] == 0xE1);  // EXIF APP1 right after SOI (no JFIF first)
  const Bytes xmp = find_app1(jpg, kXmpNamespace);
  CHECK(!xmp.empty() && contains(xmp, kDigitalSourceType));
  JpegInfo ji;
  SourceMeta back;
  Rgb8 dec = jpeg_decode(p, &ji, &back);
  CHECK(dec.w == 16 && ji.orientation == 1);
  CHECK(back.exif == meta.exif);
  CHECK(back.icc == meta.icc);
}

// EXIF written with the "Exif\0\0" prefix (some apps do). WebP: orientation and the carried
// metadata both come from the same TIFF block. PNG: libpng drops such an eXIf chunk (PNGv3
// requires a bare TIFF header), so neither is taken from it.
// S9: the QF of the JPEG cleanup pass is read back from the file's quantization table.
static void test_jpeg_quality(const std::string& dir) {
  Rgb8 img;
  img.w = 64;
  img.h = 48;
  img.px.resize(sz(img.w) * sz(img.h) * 3);
  for (size_t i = 0; i < img.px.size(); ++i) img.px[i] = uint8_t(i * 37 % 251);
  for (int q : {10, 30, 50, 75, 92, 100}) {
    const std::string p = dir + "/q" + std::to_string(q) + ".jpg";
    jpeg_encode(p, img, q);
    const int got = jpeg_probe(p).quality;
    if (got != q) std::fprintf(stderr, "quality %d read back as %d\n", q, got);
    CHECK(got == q);
  }
}

static void test_prefixed_exif(const std::string& dir) {
  Bytes prefixed = {'E', 'x', 'i', 'f', 0, 0};
  const Bytes cam = camera_exif(true);
  prefixed.insert(prefixed.end(), cam.begin(), cam.end());
  OutputMeta md;
  md.exif = prefixed;
  std::vector<uint8_t> px(16 * 8 * 3, 128);
  const std::string png = fs::join(dir, "prefixed.png"), webp = fs::join(dir, "prefixed.webp");
  {
    PngWriter w(png, 16, 8, &md);
    w.write_rows(px.data(), 8);
    w.finish();
  }
  {
    WebpWriter w(webp, 16, 8, 90, true, &md);
    w.write_rows(px.data(), 8);
    w.finish();
  }
  for (const auto& [f, kept] : {std::pair{webp, true}, std::pair{png, false}}) {
    CHECK(probe_image(f).orientation == (kept ? 6 : 1));
    ImageInfo info;
    SourceMeta m;
    decode_image(f, &info, &m);
    CHECK(info.orientation == (kept ? 6 : 1));
    CHECK(m.exif == (kept ? cam : Bytes{}));
  }
}

int main(int argc, char** argv) {
  std::string dir = argc > 1 ? argv[1] : "test-work-codecs";
  fs::remove_tree(dir);
  fs::mkdirs(dir);
  test_exif_rewrite();
  test_xmp();
  test_png(dir);
  test_webp(dir);
  test_sniff(dir);
  test_jpeg_meta(dir);
  test_prefixed_exif(dir);
  test_jpeg_quality(dir);
  std::printf("test_codecs: %d failures\n", fails);
  return fails ? 1 : 0;
}
