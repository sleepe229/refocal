// Unit tests of the pipeline building blocks.
// SPDX-License-Identifier: Apache-2.0
#include <mat.h>

#include <array>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "image/jpeg.hpp"
#include "image/metaio.hpp"
#include "image/ops.hpp"
#include "pipeline/bandstore.hpp"
#include "pipeline/geometry.hpp"
#include "pipeline/jpeg_clean.hpp"
#include "pipeline/lowlight.hpp"
#include "pipeline/scratches.hpp"
#include "policy/gpu_gate.hpp"
#include "util/error.hpp"
#include "util/fs.hpp"
#include "util/sha256.hpp"

static int fails = 0;
#define CHECK(c)                                                        \
  do {                                                                  \
    if (!(c)) {                                                         \
      std::fprintf(stderr, "%s:%d: FAIL %s\n", __FILE__, __LINE__, #c); \
      ++fails;                                                          \
    }                                                                   \
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
  const uint8_t le[] = {'E',  'x',  'i', 'f', 0, 0, 'I', 'I', 42, 0, 8, 0, 0, 0, 1, 0,
                        0x12, 0x01, 3,   0,   1, 0, 0,   0,   6,  0, 0, 0, 0, 0, 0, 0};
  CHECK(exif_orientation(le, sizeof le) == 6);
  const uint8_t be[] = {'E',  'x',  'i', 'f', 0, 0, 'M', 'M', 0, 42, 0, 0, 0, 8, 0, 1,
                        0x01, 0x12, 0,   3,   0, 0, 0,   1,   0, 8,  0, 0, 0, 0, 0, 0};
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
  CHECK(sniff_format(p) == "jpeg");
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
  CHECK(Sha256::of_string("abc") ==
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
}

static void test_gpu_gate() {
  ncnn::Mat ref = gate_input(64, 48);
  CHECK(ref.w == 64 && ref.h == 48 && ref.c == 3);
  GateMetrics same = compare_tiles(ref.clone(), ref);
  CHECK(same.pass && same.psnr == 99.0 && same.bad_frac == 0);
  ncnn::Mat inv = ref.clone();  // silent garbage
  for (int c = 0; c < 3; ++c)
    for (int i = 0; i < 64 * 48; ++i) inv.channel(c)[i] = 1.f - inv.channel(c)[i];
  CHECK(!compare_tiles(inv, ref).pass);
  ncnn::Mat nan = ref.clone();  // a single NaN fails even at high PSNR (S3)
  nan.channel(1)[100] = NAN;
  CHECK(!compare_tiles(nan, ref).pass);
  ncnn::Mat block = ref.clone();  // one corrupted 32x32 block: PSNR may pass, bad_frac must not
  for (int y = 0; y < 32; ++y)
    for (int x = 0; x < 32; ++x) block.channel(0)[y * 64 + x] = 0.f;
  CHECK(!compare_tiles(block, ref).pass);
  ncnn::Mat small(32, 48, 3);  // shape mismatch
  CHECK(!compare_tiles(small, ref).pass);
}

// S9: the JPEG cleanup pass with an identity network: every pixel comes back from the tile that
// owns it, network inputs are multiples of 8, and the qf input reaches the network.
class IdentityNet final : public InferenceBackend {
 public:
  std::string name() const override { return "identity"; }
  const BackendConfig& config() const override { return cfg_; }
  void load(const ModelInfo&) override {}
  void run(const ncnn::Mat& in, ncnn::Mat& out) override { out = in.clone(); }
  std::vector<ncnn::Mat> run_inputs(const std::vector<ncnn::Mat>& in,
                                    const std::vector<std::string>& = {}) override {
    if (in.at(0).w % kJpegCleanMultiple || in.at(0).h % kJpegCleanMultiple) ++bad_shape;
    qf = in.at(1)[0];
    ++calls;
    return {in.at(0).clone()};
  }
  void set_threads(int) override {}
  int threads() const override { return 1; }
  int calls = 0, bad_shape = 0;
  float qf = -1;

 private:
  BackendConfig cfg_;
};

static void test_jpeg_clean() {
  CHECK(std::fabs(jpeg_qf_of_quality(30) - 0.7f) < 1e-6f);
  CHECK(std::fabs(jpeg_qf_of_quality(0) - 0.5f) < 1e-6f);
  for (auto [w, h, tile, pad] :
       {std::array{37, 23, 16, 4}, std::array{5, 3, 64, 16}, std::array{100, 64, 32, 8}}) {
    Rgb8 img;
    img.w = w;
    img.h = h;
    img.px.resize(size_t(w) * h * 3);
    for (size_t i = 0; i < img.px.size(); ++i) img.px[i] = uint8_t(i * 31 % 253);
    IdentityNet net;
    int ticks = 0;
    const Rgb8 out = jpeg_clean(net, img, 0.7f, tile, pad, [&](int, int) { return ++ticks > 0; });
    CHECK(out.w == w && out.h == h && out.px == img.px);
    CHECK(net.bad_shape == 0);
    CHECK(std::fabs(net.qf - 0.7f) < 1e-6f);
    CHECK(ticks == net.calls && net.calls >= 1);
  }
  // Stopping from the tick ends it with ENH_E_CANCELLED.
  Rgb8 img;
  img.w = img.h = 40;
  img.px.assign(size_t(40) * 40 * 3, 9);
  IdentityNet net;
  bool cancelled = false;
  try {
    (void)jpeg_clean(net, img, 0.5f, 16, 4, [](int, int) { return false; });
  } catch (const Error& e) {
    cancelled = e.status() == ENH_E_CANCELLED;
  }
  CHECK(cancelled && net.calls == 1);
}

// Scratch "detector": probability 1 where the grey input is bright.
class BrightNet final : public InferenceBackend {
 public:
  std::string name() const override { return "bright"; }
  const BackendConfig& config() const override { return cfg_; }
  void load(const ModelInfo&) override {}
  void run(const ncnn::Mat& in, ncnn::Mat& out) override {
    w = in.w;
    h = in.h;
    out.create(in.w, in.h, 1);
    for (int y = 0; y < in.h; ++y)
      for (int x = 0; x < in.w; ++x) out.channel(0).row(y)[x] = in.channel(0).row(y)[x] > 0.6f;
  }
  std::vector<ncnn::Mat> run_inputs(const std::vector<ncnn::Mat>&,
                                    const std::vector<std::string>& = {}) override {
    return {};
  }
  void set_threads(int) override {}
  int threads() const override { return 1; }
  int w = 0, h = 0;

 private:
  BackendConfig cfg_;
};

// Inpainting "model": mid grey everywhere; checks the hole is blanked in its input.
class GreyFill final : public InferenceBackend {
 public:
  std::string name() const override { return "grey"; }
  const BackendConfig& config() const override { return cfg_; }
  void load(const ModelInfo&) override {}
  void run(const ncnn::Mat& in, ncnn::Mat& out) override {
    if (in.w != kInpaintSize || in.h != kInpaintSize || in.c != 4) ++bad_shape;
    for (int y = 0; y < in.h; ++y)
      for (int x = 0; x < in.w; ++x) {
        const float k = in.channel(0).row(y)[x];
        if (k != 0.5f && (k != -0.5f || in.channel(1).row(y)[x] != 0.f)) ++bad_input;
      }
    ++calls;
    out.create(kInpaintSize, kInpaintSize, 3);
    out.fill(0.f);
  }
  std::vector<ncnn::Mat> run_inputs(const std::vector<ncnn::Mat>&,
                                    const std::vector<std::string>& = {}) override {
    return {};
  }
  void set_threads(int) override {}
  int threads() const override { return 1; }
  int calls = 0, bad_shape = 0, bad_input = 0;

 private:
  BackendConfig cfg_;
};

static void test_scratches() {
  int nw = 0, nh = 0;
  scratch_input_size(4000, 3000, nw, nh);
  CHECK(nw == 336 && nh == 256);
  scratch_input_size(300, 200, nw, nh);
  CHECK(nw == 384 && nh == 256);
  // A bright vertical scratch (x 110..129) on a grey 900 x 600 photo.
  Rgb8 img;
  img.w = 900;
  img.h = 600;
  img.px.assign(size_t(img.w) * img.h * 3, 90);
  for (int y = 0; y < img.h; ++y)
    for (int x = 110; x < 130; ++x) std::fill_n(img.row(y) + x * 3, 3, uint8_t(250));
  BrightNet det;
  const Mask8 m = detect_scratches(det, img, kScratchThreshold, 1);
  CHECK(det.w % kScratchMultiple == 0 && det.h == kScratchShortSide);
  CHECK(m.w == img.w && m.h == img.h && m.count() > 0);
  CHECK(m.at(120, 300) == 255 && m.at(60, 300) == 0 && m.at(400, 10) == 0);
  for (int y = 0; y < m.h; ++y)
    for (int x = 0; x < m.w; ++x)
      if (m.at(x, y) && (x < 100 || x > 140)) {
        CHECK(false);
        y = m.h;
        break;
      }

  GreyFill fill;
  int ticks = 0;
  const Rgb8 out = inpaint(fill, img, m, [&](int, int) { return ++ticks > 0; });
  CHECK(fill.bad_shape == 0 && fill.bad_input == 0);
  CHECK(fill.calls == 2 && ticks == 2);  // 900 x 600 in 384 px cores: the column of x 110
  CHECK(out.w == img.w && out.h == img.h);
  CHECK(out.row(300)[120 * 3] == 128);  // the hole: the fill (0 in [-1, 1])
  CHECK(out.row(300)[60 * 3] == 90 && out.row(300)[200 * 3] == 90);  // kept exactly
  // No hole: nothing runs, the photo comes back.
  Mask8 none = m;
  std::fill(none.px.begin(), none.px.end(), uint8_t(0));
  GreyFill idle;
  CHECK(inpaint(idle, img, none).px == img.px && idle.calls == 0);
  // A tiny image still makes 512 px inputs.
  Rgb8 tiny;
  tiny.w = 7;
  tiny.h = 5;
  tiny.px.assign(size_t(7) * 5 * 3, 40);
  Mask8 dot;
  dot.w = 7;
  dot.h = 5;
  dot.px.assign(35, 0);
  for (int y = 1; y < 4; ++y)
    for (int x = 2; x < 5; ++x) dot.px[size_t(y) * 7 + x] = 255;
  GreyFill small;
  const Rgb8 t = inpaint(small, tiny, dot);
  CHECK(small.calls == 1 && small.bad_shape == 0 && t.row(2)[3 * 3] < 128 && t.row(2)[3 * 3] > 40);
}

// Low light: RGB -> HVI -> RGB is the identity (to a level), and so is the stage with a network
// that changes nothing.
class SameNet final : public InferenceBackend {
 public:
  std::string name() const override { return "same"; }
  const BackendConfig& config() const override { return cfg_; }
  void load(const ModelInfo&) override {}
  void run(const ncnn::Mat& in, ncnn::Mat& out) override {
    w = in.w;
    h = in.h;
    out = in.clone();
  }
  std::vector<ncnn::Mat> run_inputs(const std::vector<ncnn::Mat>& in,
                                    const std::vector<std::string>& = {}) override {
    ncnn::Mat out;
    run(in.at(0), out);
    return {out};
  }
  void set_threads(int) override {}
  int threads() const override { return 1; }
  int w = 0, h = 0;

 private:
  BackendConfig cfg_;
};

static void test_lowlight() {
  const float k = 0.98f;
  int worst = 0;
  for (int r = 0; r < 256; r += 15)
    for (int g = 0; g < 256; g += 17)
      for (int b = 0; b < 256; b += 13) {
        float rr, gg, bb;
        rgb_of_hvi(hvi_of_rgb(r / 255.f, g / 255.f, b / 255.f, k), k, rr, gg, bb);
        worst = std::max({worst, std::abs(int(std::lround(rr * 255)) - r),
                          std::abs(int(std::lround(gg * 255)) - g),
                          std::abs(int(std::lround(bb * 255)) - b)});
      }
  CHECK(worst <= 1);
  const Hvi grey = hvi_of_rgb(0.5f, 0.5f, 0.5f, k);
  CHECK(grey.h == 0 && grey.v == 0 && grey.i == 0.5f);
  Rgb8 img;
  img.w = 1001;
  img.h = 333;
  img.px.resize(size_t(img.w) * img.h * 3);
  for (size_t i = 0; i < img.px.size(); ++i) img.px[i] = uint8_t(i * 37 % 251);
  SameNet net;
  const Rgb8 out = enhance_low_light(net, img, k);
  CHECK(net.w == kLowLightSize && net.h == kLowLightSize);  // 384 x 128, padded to 384 x 384
  int diff = 0;
  for (size_t i = 0; i < img.px.size(); ++i) diff = std::max(diff, std::abs(out.px[i] - img.px[i]));
  CHECK(out.w == img.w && out.h == img.h && diff <= 1);
  // Small photos run at their own size.
  Rgb8 tiny;
  tiny.w = 13;
  tiny.h = 5;
  tiny.px.assign(size_t(13) * 5 * 3, 70);
  SameNet t;
  CHECK(enhance_low_light(t, tiny, k).px == tiny.px && t.w == kLowLightSize &&
        t.h == kLowLightSize);
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
  test_gpu_gate();
  test_jpeg_clean();
  test_scratches();
  test_lowlight();
  std::printf("test_pipeline: %d failures\n", fails);
  return fails ? 1 : 0;
}
