// Unit tests of the pipeline building blocks.
// SPDX-License-Identifier: Apache-2.0
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "image/exif.hpp"
#include "image/jpeg.hpp"
#include "image/ops.hpp"
#include "pipeline/bandstore.hpp"
#include "pipeline/geometry.hpp"
#include "util/fs.hpp"
#include "util/error.hpp"
#include "util/sha256.hpp"

static int fails = 0;
#define CHECK(c)                                                          \
  do {                                                                    \
    if (!(c)) {                                                           \
      std::fprintf(stderr, "%s:%d: FAIL %s\n", __FILE__, __LINE__, #c);   \
      ++fails;                                                            \
    }                                                                     \
  } while (0)

using namespace enh;

static Rgb8 pattern(int w, int h) {
  Rgb8 img;
  img.w = w;
  img.h = h;
  img.px.resize(size_t(w) * h * 3);
  for (int y = 0; y < h; ++y)
    for (int x = 0; x < w; ++x) {
      uint8_t* p = img.row(y) + x * 3;
      p[0] = uint8_t(x * 7 + y);
      p[1] = uint8_t(y * 5);
      p[2] = uint8_t((x ^ y) * 3);
    }
  return img;
}

static void test_geometry() {
  auto o = tile_origins(1000, 256);
  CHECK((o == std::vector<int>{0, 256, 512, 744}));
  CHECK(tile_origins(100, 256) == std::vector<int>{0});
  CHECK(owned_start(o, 0, 256) == 0 && owned_start(o, 3, 256) == 768);
  CHECK(reflect101(-1, 10) == 1 && reflect101(10, 10) == 8 && reflect101(0, 1) == 0);
  Geometry g = Geometry::make(1000, 700, 256, 16, 4, 2);
  CHECK(g.out_w == 2000 && g.out_h == 1400 && g.bands() == 3 && g.tiles() == 12);
  int rows = 0;
  for (int b = 0; b < g.bands(); ++b) {
    CHECK(g.band_out_y0(b) == rows);
    rows += g.band_out_rows(b);
  }
  CHECK(rows == g.out_h);
  Geometry tiny = Geometry::make(5, 3, 256, 16, 4, 1);
  CHECK(tiny.pad == 2 && tiny.tw == 5 && tiny.th == 3);
}

static void test_exif() {
  // "Exif\0\0" + little-endian TIFF with one IFD0 entry: Orientation = 6.
  const uint8_t le[] = {'E', 'x', 'i', 'f', 0, 0, 'I', 'I', 42, 0, 8, 0, 0, 0, 1, 0,
                        0x12, 0x01, 3, 0, 1, 0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 0};
  CHECK(exif_orientation(le, sizeof le) == 6);
  const uint8_t be[] = {'E', 'x', 'i', 'f', 0, 0, 'M', 'M', 0, 42, 0, 0, 0, 8, 0, 1,
                        0x01, 0x12, 0, 3, 0, 0, 0, 1, 0, 8, 0, 0, 0, 0, 0, 0};
  CHECK(exif_orientation(be, sizeof be) == 8);
  CHECK(exif_orientation(le, 10) == 1);  // truncated
}

static void test_orientation() {
  Rgb8 img = pattern(3, 2);
  auto at = [](const Rgb8& m, int x, int y) { return m.row(y)[x * 3]; };
  Rgb8 r6 = apply_orientation(img, 6);  // 90 CW: (x,y) -> (H-1-y, x)
  CHECK(r6.w == 2 && r6.h == 3);
  CHECK(at(r6, 1, 0) == at(img, 0, 0) && at(r6, 0, 2) == at(img, 2, 1));
  Rgb8 r3 = apply_orientation(img, 3);
  CHECK(at(r3, 0, 0) == at(img, 2, 1));
  for (int o = 1; o <= 8; ++o) {  // every orientation is a permutation of the pixels
    Rgb8 r = apply_orientation(img, o);
    CHECK(r.px.size() == img.px.size());
  }
  Rgb8 back = apply_orientation(apply_orientation(img, 6), 8);  // 90 CW then 270 CW
  CHECK(back.px == img.px);
}

static void test_area_down() {
  Rgb8 img = pattern(8, 6);
  Rgb8 d = area_down(img, 2);
  CHECK(d.w == 4 && d.h == 3);
  int s = img.row(0)[0] + img.row(0)[3] + img.row(1)[0] + img.row(1)[3];
  CHECK(d.row(0)[0] == uint8_t((s + 2) / 4));
  Rgb8 flat;
  flat.w = flat.h = 4;
  flat.px.assign(48, 77);
  CHECK(area_down(flat, 4).px == std::vector<uint8_t>(3, 77));
}

static void test_jpeg(const std::string& dir) {
  Rgb8 img = pattern(97, 61);
  std::string p = fs::join(dir, "t.jpg");
  jpeg_encode(p, img, 95);
  CHECK(is_jpeg_file(p));
  JpegInfo ji = jpeg_probe(p);
  CHECK(ji.w == 97 && ji.h == 61 && ji.orientation == 1);
  Rgb8 back = jpeg_decode(p);
  CHECK(back.w == 97 && back.h == 61);
  long err = 0;
  for (size_t i = 0; i < img.px.size(); ++i) err += std::abs(int(img.px[i]) - int(back.px[i]));
  CHECK(double(err) / img.px.size() < 12.0);  // lossy, but the same picture
  fs::write_atomic(fs::join(dir, "bad.jpg"), std::string("\xFF\xD8\xFF garbage"));
  bool threw = false;
  try {
    jpeg_decode(fs::join(dir, "bad.jpg"));
  } catch (const Error& e) {
    threw = e.status() == ENH_E_INVALID;
  }
  CHECK(threw);
}

static void test_bandstore(const std::string& dir) {
  BandStore st(fs::join(dir, "job"));
  st.reset();
  Checkpoint ck;
  ck.bands_total = 2;
  ck.recipe_hash = Sha256::of_string("x");
  ck.out_w = 4;
  ck.out_h = 2;
  std::vector<uint8_t> band(12, 9);
  st.commit(0, band.data(), band.size(), ck);
  Checkpoint got;
  CHECK(st.load_checkpoint(got) && got.band_idx == 0 && got.recipe_hash == ck.recipe_hash);
  std::vector<uint8_t> back;
  st.read_band(0, back, 12);
  CHECK(back == band);
  CHECK(!fs::exists(st.band_path(0) + ".tmp"));
  CHECK(Sha256::of_string("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
}

int main(int argc, char** argv) {
  std::string dir = argc > 1 ? argv[1] : "test-work";
  fs::remove_tree(dir);
  fs::mkdirs(dir);
  test_geometry();
  test_exif();
  test_orientation();
  test_area_down();
  test_jpeg(dir);
  test_bandstore(dir);
  std::printf("test_pipeline: %d failures\n", fails);
  return fails ? 1 : 0;
}
