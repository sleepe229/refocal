// End-to-end tests of the job ABI on synthetic ncnn models (no weights needed in CI):
//  - "nearest4": Interp x4 nearest -> the SR output must equal an exact nearest upscale, which
//    pins down tiling, padding, band assembly, x2/x1 downscale and fast 2x pixel by pixel;
//  - "bilinear4": Interp x4 bilinear -> tiled output must equal the single-tile pass.
// Also: EXIF orientation, cancel, pause + resume (byte-identical), NEEDS_USER, errors, export,
// and the event invariants (one terminal event, nothing after it, monotonic progress).
// SPDX-License-Identifier: Apache-2.0
#include <png.h>

#include <algorithm>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <mutex>
#include <nlohmann/json.hpp>
#include <string>
#include <thread>
#include <vector>

#include "enh.h"
#include "heif_fixture.hpp"
#include "image/decode.hpp"
#include "image/heif_meta.hpp"
#include "image/jpeg.hpp"
#include "image/metaio.hpp"
#include "image/ops.hpp"
#include "job/events.hpp"
#include "util/error.hpp"
#include "util/fs.hpp"

using namespace enh;
using json = nlohmann::json;

static int fails = 0;
#define CHECK(c)                                                        \
  do {                                                                  \
    if (!(c)) {                                                         \
      std::fprintf(stderr, "%s:%d: FAIL %s\n", __FILE__, __LINE__, #c); \
      ++fails;                                                          \
    }                                                                   \
  } while (0)

// ---- event collection --------------------------------------------------------------------------

struct Ev {
  int32_t type, stage;
  int64_t done, total;
  json payload;
};

struct Collector {
  std::mutex mu;
  std::condition_variable cv;
  std::vector<Ev> evs;
  int terminals = 0;
};
static Collector* g_col = nullptr;

static void on_event(int64_t, int32_t type, int32_t stage, int64_t done, int64_t total, char* p) {
  json j = json::parse(p, nullptr, false);
  enh_free(p);
  std::lock_guard lk(g_col->mu);
  g_col->evs.push_back({type, stage, done, total, j});
  if (type == ENH_EV_DONE || type == ENH_EV_ERROR) g_col->terminals++;
  g_col->cv.notify_all();
}

static bool wait_for(Collector& c, int32_t type, int seconds = 60) {
  std::unique_lock lk(c.mu);
  return c.cv.wait_for(lk, std::chrono::seconds(seconds), [&] {
    for (auto& e : c.evs)
      if (e.type == type) return true;
    return false;
  });
}

static bool wait_terminal(Collector& c, int seconds = 120) {
  std::unique_lock lk(c.mu);
  return c.cv.wait_for(lk, std::chrono::seconds(seconds), [&] { return c.terminals > 0; });
}

static void check_invariants(Collector& c) {
  std::lock_guard lk(c.mu);
  CHECK(c.terminals == 1);
  CHECK(!c.evs.empty() && (c.evs.back().type == ENH_EV_DONE || c.evs.back().type == ENH_EV_ERROR));
  // Monotonic within a stage (JPEG cleanup and SR count their own tiles).
  std::map<int32_t, int64_t> last;
  for (auto& e : c.evs)
    if (e.type == ENH_EV_PROGRESS) {
      auto it = last.try_emplace(e.stage, -1).first;
      CHECK(e.done >= it->second && e.done <= e.total);
      it->second = e.done;
    }
}

// ---- fixtures ------------------------------------------------------------------------------------

static std::string g_root, g_models, g_work;

static void make_model(const std::string& id, int resize_type) {
  std::string dir = fs::join(g_models, id);
  fs::mkdirs(dir);
  char param[256];
  std::snprintf(param, sizeof param,
                "7767517\n2 2\nInput in0 0 1 in0\nInterp up 1 1 in0 out0 0=%d 1=4.0 2=4.0\n",
                resize_type);
  fs::write_atomic(fs::join(dir, "model.ncnn.param"), std::string(param));
  fs::write_atomic(fs::join(dir, "model.ncnn.bin"), std::string());
  fs::write_atomic(fs::join(dir, "model.json"), std::string("{\"scale\":4,\"pad\":16}"));
}

static Rgb8 texture(int w, int h) {
  Rgb8 img;
  img.w = w;
  img.h = h;
  img.px.resize(size_t(w) * h * 3);
  uint32_t r = 12345;
  for (int y = 0; y < h; ++y)
    for (int x = 0; x < w; ++x) {
      r = r * 1103515245u + 12345u;
      uint8_t* p = img.row(y) + x * 3;
      p[0] = uint8_t((x * 3 + y) & 0xFF);
      p[1] = uint8_t((y * 2 + (r >> 24) % 16) & 0xFF);
      p[2] = uint8_t(((x / 8 + y / 8) % 2) * 200 + 20);
    }
  return img;
}

// Writes a JPEG; with orientation != 1, splices an EXIF APP1 segment right after SOI.
static std::string make_jpeg(const std::string& name, int w, int h, int orientation = 1) {
  std::string p = fs::join(g_root, name);
  jpeg_encode(p, texture(w, h), 95);
  if (orientation != 1) {
    auto bytes = fs::read_all(p);
    const uint8_t exif[] = {'E', 'x',  'i',  'f', 0,
                            0,   'I',  'I',  42,  0,
                            8,   0,    0,    0,   1,
                            0,   0x12, 0x01, 3,   0,
                            1,   0,    0,    0,   uint8_t(orientation),
                            0,   0,    0,    0,   0,
                            0,   0};
    std::vector<uint8_t> seg = {0xFF, 0xE1, 0, uint8_t(sizeof exif + 2)};
    seg.insert(seg.end(), exif, exif + sizeof exif);
    bytes.insert(bytes.begin() + 2, seg.begin(), seg.end());
    fs::write_atomic(p, bytes.data(), bytes.size(), false);
  }
  return p;
}

static Rgb8 nearest_up(const Rgb8& in, int f) {
  Rgb8 o;
  o.w = in.w * f;
  o.h = in.h * f;
  o.px.resize(size_t(o.w) * o.h * 3);
  for (int y = 0; y < o.h; ++y)
    for (int x = 0; x < o.w; ++x) std::memcpy(o.row(y) + x * 3, in.row(y / f) + (x / f) * 3, 3);
  return o;
}

// Concatenates the committed bands of a finished job.
static Rgb8 read_output(const std::string& job_dir) {
  json r = json::parse(fs::read_text(fs::join(job_dir, "result.json")));
  Rgb8 o;
  o.w = r["width"];
  o.h = r["height"];
  o.px.reserve(size_t(o.w) * o.h * 3);
  int b = 0;
  for (int rows : r["band_rows"].get<std::vector<int>>()) {
    char name[32];
    std::snprintf(name, sizeof name, "bands/%04d.raw", b++);
    auto d = fs::read_all(fs::join(job_dir, name));
    CHECK(d.size() == size_t(rows) * o.w * 3);
    o.px.insert(o.px.end(), d.begin(), d.end());
  }
  return o;
}

struct Session {
  enh_session* s = nullptr;
  Session() {
    enh_session_config cfg{};
    cfg.struct_size = sizeof cfg;
    cfg.models_dir = g_models.c_str();
    cfg.work_dir = g_work.c_str();
    cfg.backend_pref = ENH_BACKEND_NCNN_CPU;  // deterministic in CI; Vulkan is S3/S1b territory
    cfg.cpu_threads = 2;
    CHECK(enh_session_create(&cfg, &s) == ENH_OK);
  }
  ~Session() { enh_session_destroy(s); }
};

struct RunResult {
  int32_t status = -1;
  json payload;
};

static RunResult run_job(Session& se, const json& req, Collector& col) {
  g_col = &col;
  enh_job* j = nullptr;
  std::string r = req.dump();
  RunResult rr;
  if (enh_job_create(se.s, r.c_str(), &j) != ENH_OK) return rr;
  CHECK(enh_job_start(j, on_event, 7) == ENH_OK);
  CHECK(enh_job_start(j, on_event, 7) == ENH_E_INVALID);
  CHECK(wait_terminal(col));
  enh_job_destroy(j);
  check_invariants(col);
  std::lock_guard lk(col.mu);
  rr.payload = col.evs.back().payload;
  rr.status = col.evs.back().type == ENH_EV_DONE ? ENH_OK : rr.payload.value("status", -1);
  return rr;
}

static json req(const std::string& id, const std::string& input, const std::string& model) {
  return {{"schema", 1}, {"job_id", id}, {"input", input}, {"sr_model", model}, {"tile", 64}};
}

// ---- tests ---------------------------------------------------------------------------------------

static void test_nearest_exact(Session& se) {
  std::string in = make_jpeg("n.jpg", 150, 101);
  Rgb8 src = jpeg_decode(in);
  {
    Collector c;
    auto r = run_job(se, req("n4", in, "nearest4"), c);
    CHECK(r.status == ENH_OK);
    Rgb8 out = read_output(fs::join(g_work, "n4"));
    CHECK(out.w == 600 && out.h == 404);
    CHECK(out.px == nearest_up(src, 4).px);
    CHECK(r.payload["preview"]["width"].get<int>() > 0);
    CHECK(fs::exists(fs::join(g_work, "n4/preview.jpg")));
  }
  {
    Collector c;
    json q = req("n2", in, "nearest4");
    q["scale"] = 2;
    CHECK(run_job(se, q, c).status == ENH_OK);
    Rgb8 out = read_output(fs::join(g_work, "n2"));
    CHECK(out.w == 300 && out.h == 202 && out.px == nearest_up(src, 2).px);
  }
  {
    Collector c;
    json q = req("n1", in, "nearest4");
    q["scale"] = 1;
    CHECK(run_job(se, q, c).status == ENH_OK);
    CHECK(read_output(fs::join(g_work, "n1")).px == src.px);
  }
  {
    Collector c;
    json q = req("nf2", in, "nearest4");
    q["scale"] = 2;
    q["fast2"] = true;
    CHECK(run_job(se, q, c).status == ENH_OK);
    Rgb8 out = read_output(fs::join(g_work, "nf2"));
    CHECK(out.w == 300 && out.h == 200 && out.px == nearest_up(area_down(src, 2), 4).px);
  }
  {  // 8x (ADR-0014): x4, x4 again, area /2 = nearest x8; the first pass's store is removed
    Collector c;
    json q = req("n8", in, "nearest4");
    q["scale"] = 8;
    auto r = run_job(se, q, c);
    CHECK(r.status == ENH_OK && r.payload["scale"] == 8);
    Rgb8 out = read_output(fs::join(g_work, "n8"));
    CHECK(out.w == 1200 && out.h == 808 && out.px == nearest_up(src, 8).px);
    CHECK(!fs::exists(fs::join(g_work, "n8/x8")));
    std::lock_guard lk(c.mu);
    int64_t last = 0, total = 0;
    for (auto& e : c.evs)
      if (e.type == ENH_EV_PROGRESS && e.stage == kStageUpscale) last = e.done, total = e.total;
    CHECK(total > 0 && last == total);  // one progress over both passes
  }
}

// CompareViewer tiles (06 §5): regions of the result from the BandStore and of the original
// scaled to the result. nearest4 makes both exact: at factor 4 each is the input itself.
static void test_viewer(Session& se) {
  std::string in = make_jpeg("v.jpg", 150, 101);
  Rgb8 src = jpeg_decode(in);
  Collector c;
  json q = req("view", in, "nearest4");
  q["tile"] = 32;  // several bands: rows cross band boundaries
  CHECK(run_job(se, q, c).status == ENH_OK);
  const std::string dir = fs::join(g_work, "view");
  const Rgb8 out = read_output(dir);
  enh_viewer* v = nullptr;
  CHECK(enh_viewer_open(dir.c_str(), &v) == ENH_OK);
  if (!v) return;
  auto render = [&](int source, int x, int y, int w, int h, int f) {
    const int ow = (w + f - 1) / f, oh = (h + f - 1) / f;
    std::vector<uint8_t> rgba(size_t(ow) * oh * 4);
    const enh_status st =
        enh_viewer_render(v, source, x, y, w, h, f, rgba.data(), int64_t(rgba.size()));
    CHECK(st == ENH_OK);
    return rgba;
  };
  auto rgb_at = [](const Rgb8& im, int x, int y, int k) {
    return im.px[(size_t(y) * im.w + x) * 3 + k];
  };
  // factor 1: the result's pixels, across bands (rows 100..299 of 404)
  {
    const auto t = render(0, 37, 100, 200, 200, 1);
    bool same = true;
    for (int y = 0; y < 200; ++y)
      for (int x = 0; x < 200; ++x)
        for (int k = 0; k < 3; ++k)
          same &= t[(size_t(y) * 200 + x) * 4 + k] == rgb_at(out, 37 + x, 100 + y, k);
    CHECK(same && t[3] == 255);
  }
  // factor 4 over the whole image: result and original both give the input back
  for (int source : {0, 1}) {
    const auto t = render(source, 0, 0, 600, 404, 4);
    bool same = true;
    for (int y = 0; y < 101; ++y)
      for (int x = 0; x < 150; ++x)
        for (int k = 0; k < 3; ++k)
          same &= t[(size_t(y) * 150 + x) * 4 + k] == rgb_at(src, x, y, k);
    CHECK(same);
  }
  // an edge tile that does not divide: ceil size, partial means
  CHECK(render(0, 590, 400, 10, 4, 4).size() == size_t(3 * 1 * 4));
  // the original zoomed past its own size (bilinear) and the limits
  CHECK(render(1, 0, 0, 256, 256, 1).size() == size_t(256 * 256 * 4));
  std::vector<uint8_t> buf(16);
  CHECK(enh_viewer_render(v, 0, 0, 0, 601, 1, 1, buf.data(), 16) ==
        ENH_E_INVALID);  // past the edge
  CHECK(enh_viewer_render(v, 0, 0, 0, 4, 4, 1, buf.data(), 16) ==
        ENH_E_INVALID);  // buffer too small
  CHECK(enh_viewer_render(v, 2, 0, 0, 1, 1, 1, buf.data(), 16) == ENH_E_INVALID);  // no such source
  CHECK(enh_viewer_render(v, 0, 0, 0, 600, 404, 0, buf.data(), 16) == ENH_E_INVALID);
  enh_viewer_close(v);
  CHECK(enh_viewer_open(fs::join(g_work, "nope").c_str(), &v) != ENH_OK);
  // The original gone (saved and released): its tiles fail, the result's still work.
  std::string in2 = make_jpeg("v2.jpg", 64, 64);
  Collector c2;
  CHECK(run_job(se, req("view2", in2, "nearest4"), c2).status == ENH_OK);
  std::remove(in2.c_str());
  CHECK(enh_viewer_open(fs::join(g_work, "view2").c_str(), &v) == ENH_OK);
  if (v) {
    std::vector<uint8_t> t(64 * 64 * 4);
    CHECK(enh_viewer_render(v, 1, 0, 0, 256, 256, 4, t.data(), int64_t(t.size())) == ENH_E_IO);
    CHECK(enh_viewer_render(v, 0, 0, 0, 256, 256, 4, t.data(), int64_t(t.size())) == ENH_OK);
    enh_viewer_close(v);
  }
  enh_viewer_close(nullptr);
}

// FR-ENH-015: a fragment preview runs on its crop only; the viewer's original side follows.
static void test_crop(Session& se) {
  std::string in = make_jpeg("crop.jpg", 150, 101);
  Rgb8 src = jpeg_decode(in);
  const Rgb8 part = crop(src, 40, 30, 64, 48);
  Collector c;
  json q = req("crop", in, "nearest4");
  q["crop"] = {40, 30, 64, 48};
  auto r = run_job(se, q, c);
  CHECK(r.status == ENH_OK);
  const Rgb8 out = read_output(fs::join(g_work, "crop"));
  CHECK(out.w == 256 && out.h == 192 && out.px == nearest_up(part, 4).px);
  enh_viewer* v = nullptr;
  CHECK(enh_viewer_open(fs::join(g_work, "crop").c_str(), &v) == ENH_OK);
  if (v) {
    std::vector<uint8_t> t(64 * 48 * 4);
    CHECK(enh_viewer_render(v, 1, 0, 0, 256, 192, 4, t.data(), int64_t(t.size())) == ENH_OK);
    bool same = true;
    for (size_t i = 0; i < size_t(64) * 48; ++i)
      for (int k = 0; k < 3; ++k) same &= t[i * 4 + k] == part.px[i * 3 + k];
    CHECK(same);
    enh_viewer_close(v);
  }
  // Outside the photo: the job fails; sizes outside 16..2048 are refused at once.
  Collector c2;
  q["job_id"] = "crop_out";
  q["crop"] = {100, 60, 64, 48};
  CHECK(run_job(se, q, c2).status == ENH_E_INVALID);
  enh_job* j = nullptr;
  for (const char* bad : {"[0,0,8,64]", "[0,0,64,4096]", "[-1,0,64,64]", "[0,0,64]"}) {
    q["job_id"] = "crop_bad";
    q["crop"] = json::parse(bad);
    const std::string rq = q.dump();
    CHECK(enh_job_create(se.s, rq.c_str(), &j) == ENH_E_INVALID);
  }
}

static void test_tiled_equals_whole(Session& se) {
  std::string in = make_jpeg("b.jpg", 230, 170);
  Collector c1, c2;
  json tiled = req("bt", in, "bilinear4");
  json whole = req("bw", in, "bilinear4");
  whole["tile"] = 1024;  // single tile
  CHECK(run_job(se, tiled, c1).status == ENH_OK);
  CHECK(run_job(se, whole, c2).status == ENH_OK);
  Rgb8 a = read_output(fs::join(g_work, "bt")), b = read_output(fs::join(g_work, "bw"));
  int maxd = 0;
  for (size_t i = 0; i < a.px.size() && i < b.px.size(); ++i)
    maxd = std::max(maxd, std::abs(int(a.px[i]) - int(b.px[i])));
  CHECK(a.px.size() == b.px.size());
  std::printf("bilinear tiled vs whole: max diff %d\n", maxd);
  CHECK(maxd == 0);
}

// S9: with an identity JPEG pack the result is the plain one; the pass reports its stage and
// the quality factor read from the input (make_jpeg writes quality 95 -> qf 0.05).
static void test_jpeg_clean(Session& se) {
  const std::string dir = fs::join(g_models, "jpeg.identity");
  fs::mkdirs(dir);
  fs::write_atomic(fs::join(dir, "model.ncnn.param"),
                   std::string("7767517\n3 3\nInput in0 0 1 in0\nInput in1 0 1 in1\n"
                               "Noop id 1 1 in0 out0\n"));
  fs::write_atomic(fs::join(dir, "model.ncnn.bin"), std::string());
  fs::write_atomic(fs::join(dir, "model.json"), std::string("{\"scale\":1,\"pad\":8}"));
  const std::string in = make_jpeg("jc.jpg", 301, 157);
  Collector plain, clean;
  CHECK(run_job(se, req("jp", in, "nearest4"), plain).status == ENH_OK);
  json q = req("jc", in, "nearest4");
  q["jpeg_model"] = "jpeg.identity";
  CHECK(run_job(se, q, clean).status == ENH_OK);
  CHECK(read_output(fs::join(g_work, "jc")).px == read_output(fs::join(g_work, "jp")).px);
  bool staged = false, progressed = false;
  {
    std::lock_guard lk(clean.mu);
    for (const auto& e : clean.evs) {
      if (e.type == ENH_EV_STAGE && e.stage == 5) {
        staged = true;
        CHECK(std::fabs(e.payload.value("qf", -1.0) - 0.05) < 0.011);
      }
      progressed |= e.type == ENH_EV_PROGRESS && e.stage == 5 && e.done == e.total;
    }
  }
  CHECK(staged && progressed);
  Collector bad;
  json b = req("jb", in, "nearest4");
  b["jpeg_model"] = "jpeg.identity";
  b["jpeg_qf"] = 1.5;
  CHECK(run_job(se, b, bad).status != ENH_OK);
}

static void test_orientation(Session& se) {
  std::string in = make_jpeg("o.jpg", 120, 80, 6);  // rotate 90 CW
  Collector c;
  json q = req("o6", in, "nearest4");
  q["scale"] = 1;
  CHECK(run_job(se, q, c).status == ENH_OK);
  Rgb8 out = read_output(fs::join(g_work, "o6"));
  CHECK(out.w == 80 && out.h == 120);
  CHECK(out.px == apply_orientation(jpeg_decode(in), 6).px);
}

static double psnr(const std::vector<uint8_t>& a, const std::vector<uint8_t>& b) {
  double se = 0;
  for (size_t i = 0; i < a.size(); ++i) se += double(a[i] - b[i]) * (a[i] - b[i]);
  return se == 0 ? 99 : 10 * std::log10(255.0 * 255.0 * a.size() / se);
}

static void test_export(Session& se) {
  const std::string job = fs::join(g_work, "n2");
  const Rgb8 sr = read_output(job);
  std::string dst = fs::join(g_root, "exported.jpg");
  char* out = nullptr;
  CHECK(enh_export(se.s, job.c_str(), "{\"format\":\"jpeg\",\"quality\":90}", dst.c_str(), &out) ==
        ENH_OK);
  CHECK(out && json::parse(out)["width"] == 300);
  enh_free(out);
  JpegInfo ji = jpeg_probe(dst);
  CHECK(ji.w == 300 && ji.h == 202);
  CHECK(!fs::exists(dst + ".part"));

  // Lossless formats reproduce the BandStore exactly (FR-EXP-001); lossy WebP comes close.
  auto exported = [&](const char* opts, const char* name) {
    const std::string d = fs::join(g_root, name);
    const enh_status st = enh_export(se.s, job.c_str(), opts, d.c_str(), nullptr);
    return st == ENH_OK ? decode_image(d) : Rgb8{};
  };
  CHECK(exported("{\"format\":\"png\"}", "e.png").px == sr.px);
  CHECK(sniff_format(fs::join(g_root, "e.png")) == "png");
  CHECK(exported("{\"format\":\"webp\",\"lossless\":true}", "el.webp").px == sr.px);
  const Rgb8 lossy = exported("{\"format\":\"webp\",\"quality\":95}", "e.webp");
  CHECK(lossy.w == 300 && lossy.h == 202 && psnr(lossy.px, sr.px) > 28);

  // Strength (FR-ENH-005): 0 is the Lanczos upscale of the input, 1 the SR result.
  Rgb8 src = jpeg_decode(
      json::parse(fs::read_text(fs::join(job, "request.json")))["input"].get<std::string>());
  Rgb8 lz;
  lz.w = sr.w;
  lz.h = sr.h;
  lz.px.resize(sr.px.size());
  LanczosResampler(src, sr.w, sr.h).rows(0, sr.h, lz.px.data());
  CHECK(exported("{\"format\":\"png\",\"strength\":0}", "s0.png").px == lz.px);
  CHECK(exported("{\"format\":\"png\",\"strength\":1.0}", "s1.png").px == sr.px);
  const Rgb8 half = exported("{\"format\":\"png\",\"strength\":0.5}", "s5.png");
  bool between = half.px.size() == sr.px.size();
  for (size_t i = 0; between && i < sr.px.size(); ++i) {
    const int lo = std::min(sr.px[i], lz.px[i]), hi = std::max(sr.px[i], lz.px[i]);
    between = half.px[i] >= lo && half.px[i] <= hi && std::abs(2 * half.px[i] - lo - hi) <= 2;
  }
  CHECK(between);

  // Thumbnail (history preview, FR-HIST-001): the exported pixels, strength applied, <= max_side.
  const std::string thumb = fs::join(g_root, "thumb.jpg");
  const json topt = {
      {"format", "png"}, {"strength", 0.5}, {"thumbnail", {{"path", thumb}, {"max_side", 64}}}};
  out = nullptr;
  CHECK(enh_export(se.s, job.c_str(), topt.dump().c_str(), fs::join(g_root, "t.png").c_str(),
                   &out) == ENH_OK);
  const json tj = out ? json::parse(out) : json();
  enh_free(out);
  CHECK(tj.value("/thumbnail/path"_json_pointer, std::string()) == thumb);
  CHECK(tj.value("/thumbnail/width"_json_pointer, 0) == 64 &&
        tj.value("/thumbnail/height"_json_pointer, 0) == 43);
  CHECK(!fs::exists(thumb + ".part"));
  PreviewAccumulator acc;
  acc.init(half.w, half.h, 64);
  acc.add_rows(half.px.data(), 0, half.h);
  // Same pixels as encoding the area-downscaled export at the default quality 80.
  const std::string ref = fs::join(g_root, "thumb-ref.jpg");
  jpeg_encode(ref, acc.finish(), 80);
  const Rgb8 tn = decode_image(thumb);
  CHECK(tn.w == 64 && tn.h == 43 && tn.px == decode_image(ref).px);
  ::unlink(thumb.c_str());
  // A failed export leaves no thumbnail behind.
  const std::string nowhere = fs::join(g_root, "no/such/dir/x.png");
  CHECK(enh_export(se.s, job.c_str(), topt.dump().c_str(), nowhere.c_str(), nullptr) != ENH_OK);
  CHECK(!fs::exists(thumb) && !fs::exists(thumb + ".part"));

  // HEIC (FR-EXP-002): raw RGBA for the platform encoder, then the metadata into its output.
  const std::string raw = fs::join(g_root, "e.rgba");
  CHECK(enh_export(se.s, job.c_str(), R"({"format":"rgba"})", raw.c_str(), nullptr) == ENH_OK);
  const auto rgba = fs::read_all(raw);
  bool same = rgba.size() == sr.px.size() / 3 * 4;
  for (size_t i = 0; same && i < sr.px.size() / 3; ++i) {
    same = rgba[i * 4] == sr.px[i * 3] && rgba[i * 4 + 1] == sr.px[i * 3 + 1] &&
           rgba[i * 4 + 2] == sr.px[i * 3 + 2] && rgba[i * 4 + 3] == 255;
  }
  CHECK(same);
  const std::string encoded = fs::join(g_root, "encoded.heic"), heic = fs::join(g_root, "e.heic");
  const auto container = heif_fixture::make_heif(std::vector<uint8_t>(40, 1), {2, 3});
  fs::write_atomic(encoded, container.data(), container.size(), false);
  const json hopt = {{"format", "heic"}, {"heif_input", encoded}};
  out = nullptr;
  CHECK(enh_export(se.s, job.c_str(), hopt.dump().c_str(), heic.c_str(), &out) == ENH_OK);
  CHECK(out && json::parse(out).value("/metadata/ai_marker"_json_pointer, false));
  enh_free(out);
  const auto hb = fs::read_all(heic);
  const HeifMetaInfo hi = heif_read_meta(hb.data(), hb.size());
  CHECK(hi.xmp.find("compositeWithTrainedAlgorithmicMedia") != std::string::npos);
  CHECK(heif_item_data(hb.data(), hb.size(), 3) == std::vector<uint8_t>({2, 3}));
  CHECK(enh_export(se.s, job.c_str(), R"({"format":"heic"})", heic.c_str(), nullptr) ==
        ENH_E_INVALID);

  for (const char* bad :
       {"{\"format\":\"gif\"}", "{\"format\":\"jpeg\",\"lossless\":true}", "{\"strength\":1.5}",
        "{\"strength\":-0.1}", "{\"quality\":0}", "{\"thumbnail\":{}}",
        "{\"thumbnail\":{\"path\":\"/tmp/t.jpg\",\"max_side\":8}}",
        "{\"thumbnail\":{\"path\":\"/tmp/t.jpg\",\"quality\":101}}"}) {
    CHECK(enh_export(se.s, job.c_str(), bad, dst.c_str(), nullptr) == ENH_E_INVALID);
  }
}

// Lanczos: the same size is a copy; a flat image stays flat; x2 of a ramp stays monotonic.
static void test_lanczos() {
  Rgb8 t = texture(37, 23);
  std::vector<uint8_t> o(t.px.size());
  LanczosResampler(t, t.w, t.h).rows(0, t.h, o.data());
  CHECK(o == t.px);
  Rgb8 flat;
  flat.w = 9;
  flat.h = 7;
  flat.px.assign(9 * 7 * 3, 77);
  std::vector<uint8_t> f(36 * 28 * 3);
  LanczosResampler lf(flat, 36, 28);
  lf.rows(0, 10, f.data());
  lf.rows(10, 18, f.data() + 10 * 36 * 3);
  bool all = true;
  for (uint8_t v : f) all &= v == 77;
  CHECK(all);
}

// PNG input runs through the same pipeline: the SR model sees it on white; its alpha is kept
// and comes back in PNG and WebP exports, not in JPEG (FR-IMP-007).
static void test_png_input(Session& se) {
  const int w = 90, h = 70;
  Rgb8 src = texture(w, h);
  std::vector<uint8_t> rgba(size_t(w) * h * 4);
  for (int i = 0; i < w * h; ++i) {
    std::memcpy(&rgba[i * 4], &src.px[i * 3], 3);
    rgba[i * 4 + 3] = 255;
  }
  rgba[3] = 0;  // one transparent pixel
  std::string in = fs::join(g_root, "in.png");
  png_image im{};
  im.version = PNG_IMAGE_VERSION;
  im.width = w;
  im.height = h;
  im.format = PNG_FORMAT_RGBA;
  CHECK(png_image_write_to_file(&im, in.c_str(), 0, rgba.data(), 0, nullptr));
  Collector c;
  json q = req("png1", in, "nearest4");
  q["scale"] = 1;
  RunResult rr = run_job(se, q, c);
  CHECK(rr.status == ENH_OK);
  CHECK(rr.payload["input"]["format"] == "png");
  bool warned = false;
  for (auto& e : c.evs)
    warned |= e.type == ENH_EV_WARNING && e.payload.value("code", "") == "alpha_kept";
  CHECK(warned);
  CHECK(rr.payload["alpha"]["width"] == w && rr.payload["alpha"]["height"] == h);
  Rgb8 out = read_output(fs::join(g_work, "png1"));
  src.px[0] = src.px[1] = src.px[2] = 255;
  CHECK(out.w == w && out.h == h && out.px == src.px);

  const std::string dir = fs::join(g_work, "png1");
  auto export_to = [&](const std::string& opts, const std::string& name) {
    const std::string dst = fs::join(g_root, name);
    char* o = nullptr;
    CHECK(enh_export(se.s, dir.c_str(), opts.c_str(), dst.c_str(), &o) == ENH_OK);
    const bool alpha = o && json::parse(o)["metadata"]["alpha"].get<bool>();
    enh_free(o);
    return std::pair{dst, alpha};
  };
  // PNG: the alpha back, exactly at 1x (the transparent pixel 0, the rest 255).
  {
    const auto [dst, alpha] = export_to(R"({"format":"png"})", "alpha.png");
    CHECK(alpha);
    png_image rd{};
    rd.version = PNG_IMAGE_VERSION;
    CHECK(png_image_begin_read_from_file(&rd, dst.c_str()));
    CHECK(rd.format & PNG_FORMAT_FLAG_ALPHA);
    rd.format = PNG_FORMAT_RGBA;
    std::vector<uint8_t> px(PNG_IMAGE_SIZE(rd));
    CHECK(png_image_finish_read(&rd, nullptr, px.data(), 0, nullptr));
    bool rest = true;
    for (int i = 1; i < w * h; ++i) rest &= px[size_t(i) * 4 + 3] == 255;
    CHECK(px[3] == 0 && rest);
  }
  // WebP lossless: the same alpha; JPEG: none.
  {
    const auto [dst, alpha] = export_to(R"({"format":"webp","lossless":true})", "alpha.webp");
    CHECK(alpha);
    ImageInfo info;
    SourceMeta meta;
    decode_image(dst, &info, &meta);
    CHECK(info.alpha && meta.alpha.size() == size_t(w) * h && meta.alpha[0] == 0 &&
          meta.alpha[1] == 255);
  }
  CHECK(!export_to(R"({"format":"jpeg"})", "alpha.jpg").second);

  // 4x: the alpha is scaled with the image (a transparent 8x8 block stays transparent inside).
  for (int y = 20; y < 28; ++y)
    for (int x = 30; x < 38; ++x) rgba[(size_t(y) * w + x) * 4 + 3] = 0;
  CHECK(png_image_write_to_file(&im, in.c_str(), 0, rgba.data(), 0, nullptr));
  Collector c4;
  CHECK(run_job(se, req("png4", in, "nearest4"), c4).status == ENH_OK);
  const std::string d4 = fs::join(g_work, "png4"), dst4 = fs::join(g_root, "alpha4.png");
  CHECK(enh_export(se.s, d4.c_str(), R"({"format":"png"})", dst4.c_str(), nullptr) == ENH_OK);
  ImageInfo i4;
  SourceMeta m4;
  decode_image(dst4, &i4, &m4);
  CHECK(i4.w == w * 4 && m4.alpha.size() == size_t(w) * h * 16);
  if (m4.alpha.size() == size_t(w) * h * 16) {
    CHECK(m4.alpha[size_t(4 * 24) * w * 4 + 4 * 34] == 0);    // inside the block
    CHECK(m4.alpha[size_t(4 * 50) * w * 4 + 4 * 70] == 255);  // far from it
  }
}

// A well-formed ICC v2 display profile: header, one tag ("cprt") with non-trivial data, so
// that it passes icc_header_valid and libpng's checks on write and read.
static std::vector<uint8_t> icc_profile() {
  constexpr size_t kSize = 600, kTag = 144;
  std::vector<uint8_t> p(kSize, 0);
  auto put = [&](size_t at, const char* s) { std::memcpy(&p[at], s, 4); };
  auto be32 = [&](size_t at, uint32_t v) {
    for (int i = 0; i < 4; ++i) p[at + i] = uint8_t(v >> (24 - 8 * i));
  };
  be32(0, kSize);
  p[8] = 2;  // version 2.1
  p[9] = 0x10;
  put(12, "mntr");
  put(16, "RGB ");
  put(20, "XYZ ");
  put(36, "acsp");
  const uint8_t d50[12] = {0, 0, 0xF6, 0xD6, 0, 1, 0, 0, 0, 0, 0xD3, 0x2D};
  std::memcpy(&p[68], d50, 12);  // PCS illuminant
  be32(128, 1);                  // tag count
  put(132, "cprt");
  be32(136, kTag);
  be32(140, kSize - kTag);
  put(kTag, "text");
  for (size_t i = kTag + 8; i < kSize; ++i) p[i] = uint8_t('a' + (i * 7) % 26);
  return p;
}

// Source ICC profiles with a broken header are dropped on read, not carried to the result.
static void test_icc_validation() {
  auto good = icc_profile();
  CHECK(icc_header_valid(good.data(), good.size()));
  auto bad = good;
  bad[3] = 136;  // size field disagrees
  CHECK(!icc_header_valid(bad.data(), bad.size()));
  bad = good;
  bad[36] = 'x';
  CHECK(!icc_header_valid(bad.data(), bad.size()));
  CHECK(!icc_header_valid(good.data(), 100));
}

// EXIF (orientation 6, Make, GPS) + ICC in the input -> the export carries them per policy.
static void test_export_metadata(Session& se) {
  const uint8_t tiff[] = {'I',  'I',  42, 0, 8, 0, 0, 0, 3,   0,            // IFD0: 3 entries
                          0x0F, 0x01, 2,  0, 4, 0, 0, 0, 'C', 'a', 'm', 0,  // Make "Cam"
                          0x12, 0x01, 3,  0, 1, 0, 0, 0, 6,   0,   0,   0,  // Orientation 6
                          0x25, 0x88, 4,  0, 1, 0, 0, 0, 50,  0,   0,   0,  // GPS IFD at 50
                          0,    0,    0,  0,                                // no IFD1
                          1,    0,                                          // GPS: 1 entry
                          0,    0,    1,  0, 4, 0, 0, 0, 2,   3,   0,   0,  // GPSVersionID
                          0,    0,    0,  0};
  OutputMeta in_meta;
  in_meta.exif.assign(tiff, tiff + sizeof tiff);
  in_meta.icc = icc_profile();
  std::string in = fs::join(g_root, "meta_in.jpg");
  {
    Rgb8 t = texture(64, 40);
    JpegWriter wr(in, t.w, t.h, 95, &in_meta);
    wr.write_rows(t.px.data(), t.h);
    wr.finish();
  }
  Collector c;
  json q = req("md", in, "nearest4");
  q["scale"] = 2;
  CHECK(run_job(se, q, c).status == ENH_OK);
  const std::string job = fs::join(g_work, "md"), dst = fs::join(g_root, "md.jpg");

  auto exported = [&](const char* opts, SourceMeta& m) {
    char* out = nullptr;
    enh_status st = enh_export(se.s, job.c_str(), opts, dst.c_str(), &out);
    json r = out ? json::parse(out) : json();
    enh_free(out);
    if (st == ENH_OK) jpeg_decode(dst, nullptr, &m);
    return std::pair{st, r};
  };
  auto has_xmp = [&] {
    auto b = fs::read_all(dst);
    const std::string needle = kDigitalSourceType;
    return std::search(b.begin(), b.end(), needle.begin(), needle.end()) != b.end();
  };
  {
    SourceMeta m;
    auto [st, r] = exported("{\"format\":\"jpeg\"}", m);
    CHECK(st == ENH_OK);
    CHECK(r["metadata"]["exif"] == true && r["metadata"]["icc"] == true &&
          r["metadata"]["ai_marker"] == true);
    CHECK(exif_orientation(m.exif.data(), m.exif.size()) == 1);  // baked: result is 80x128
    CHECK(exif_get(m.exif, kExifIfd, 0xA002) == 80 && exif_get(m.exif, kExifIfd, 0xA003) == 128);
    CHECK(exif_get(m.exif, kIfd0, 0x010F) == 4);
    CHECK(exif_get(m.exif, kGpsIfd, 0) == -1);
    CHECK(m.icc == in_meta.icc);
    CHECK(has_xmp());
  }
  {
    SourceMeta m;
    auto [st, r] = exported("{\"metadata\":{\"gps\":true,\"ai_marker\":false}}", m);
    CHECK(st == ENH_OK && exif_get(m.exif, kGpsIfd, 0) >= 0 && !has_xmp());
  }
  {
    SourceMeta m;
    auto [st, r] = exported("{\"metadata\":{\"exif\":false}}", m);
    CHECK(st == ENH_OK && m.exif.empty() && m.icc == in_meta.icc);
  }
  // PNG (eXIf, iCCP, iTXt) and WebP (EXIF, ICCP, XMP chunks) carry the same blocks.
  for (const char* fmt : {"png", "webp"}) {
    const std::string d = fs::join(g_root, std::string("md.") + fmt);
    const std::string opts = std::string("{\"format\":\"") + fmt + "\"}";
    CHECK(enh_export(se.s, job.c_str(), opts.c_str(), d.c_str(), nullptr) == ENH_OK);
    SourceMeta m;
    ImageInfo info;
    Rgb8 img = decode_image(d, &info, &m);
    CHECK(img.w == 80 && img.h == 128 && info.orientation == 1);
    CHECK(exif_get(m.exif, kIfd0, 0x010F) == 4 && exif_get(m.exif, kGpsIfd, 0) == -1);
    CHECK(m.icc == in_meta.icc);
    auto b = fs::read_all(d);
    const std::string needle = kDigitalSourceType;
    CHECK(std::search(b.begin(), b.end(), needle.begin(), needle.end()) != b.end());
  }
  {
    SourceMeta m;
    CHECK(exported("{\"metadata\":{\"gps\":\"yes\"}}", m).first == ENH_E_INVALID);
    CHECK(exported("{\"metadata\":[]}", m).first == ENH_E_INVALID);
  }
}

// A slower job: bilinear on a larger image with small tiles.
static json slow_req(const std::string& id, const std::string& in) {
  json q = req(id, in, "bilinear4");
  q["tile"] = 32;
  return q;
}

static void test_cancel(Session& se, const std::string& in) {
  Collector c;
  g_col = &c;
  enh_job* j = nullptr;
  std::string r = slow_req("cx", in).dump();
  CHECK(enh_job_create(se.s, r.c_str(), &j) == ENH_OK);
  CHECK(enh_job_start(j, on_event, 1) == ENH_OK);
  CHECK(wait_for(c, ENH_EV_PROGRESS));  // in the upscale stage; the input keeps it busy for seconds
  auto t0 = std::chrono::steady_clock::now();
  enh_job_cancel(j);
  CHECK(wait_terminal(c, 10));
  double ms =
      std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
  std::printf("cancel latency: %.1f ms\n", ms);
  CHECK(ms < 1000);
  CHECK(enh_job_status(j) == ENH_E_CANCELLED);
  enh_job_destroy(j);
  check_invariants(c);
  CHECK(!fs::exists(fs::join(g_work, "cx")));  // cancelled jobs free their disk
}

static void test_pause_resume(Session& se, const std::string& in) {
  Collector full;
  CHECK(run_job(se, slow_req("pr_ref", in), full).status == ENH_OK);

  Collector c;
  g_col = &c;
  enh_job* j = nullptr;
  std::string r = slow_req("pr", in).dump();
  CHECK(enh_job_create(se.s, r.c_str(), &j) == ENH_OK);
  CHECK(enh_job_start(j, on_event, 1) == ENH_OK);
  {  // pause once a few bands are committed
    std::unique_lock lk(c.mu);
    c.cv.wait_for(lk, std::chrono::seconds(60), [&] {
      for (auto& e : c.evs)
        if (e.type == ENH_EV_PROGRESS && e.total > 0 && e.done * 3 > e.total) return true;
      return false;
    });
  }
  enh_job_pause(j);
  CHECK(wait_terminal(c, 10));
  CHECK(enh_job_status(j) == ENH_E_PAUSED);
  enh_job_destroy(j);
  check_invariants(c);
  CHECK(fs::exists(fs::join(g_work, "pr/checkpoint.json")));

  Collector c2;
  g_col = &c2;
  enh_job* j2 = nullptr;
  CHECK(enh_job_resume(se.s, fs::join(g_work, "pr").c_str(), &j2) == ENH_OK);
  CHECK(enh_job_start(j2, on_event, 2) == ENH_OK);
  CHECK(wait_terminal(c2));
  enh_job_destroy(j2);
  check_invariants(c2);
  std::lock_guard lk(c2.mu);
  CHECK(c2.evs.back().type == ENH_EV_DONE);
  CHECK(c2.evs.back().payload["resumed_from_band"].get<int>() > 0);
  CHECK(read_output(fs::join(g_work, "pr")).px == read_output(fs::join(g_work, "pr_ref")).px);
  CHECK(enh_job_resume(se.s, "/etc", &j2) != ENH_OK);
}

// 8x resumes in either pass with the same bytes. Paused in the second pass: the first is not
// run again. Killed in the first (its checkpoint at band 1, no result bands yet): it goes on
// from band 2 of the first pass.
static void test_x8_resume(Session& se) {
  const std::string in = make_jpeg("x8.jpg", 200, 150);
  auto q = [&](const std::string& id) {
    json r = slow_req(id, in);
    r["scale"] = 8;
    return r;
  };
  Collector ref;
  CHECK(run_job(se, q("x8_ref"), ref).status == ENH_OK);
  const int64_t tpb1 = (200 + 31) / 32, pass1 = tpb1 * ((150 + 31) / 32);  // 32 px tiles

  for (bool in_pass1 : {false, true}) {
    const std::string id = in_pass1 ? "x8_p1" : "x8_p2", dir = fs::join(g_work, id);
    {  // paused some way into the second pass
      Collector c;
      g_col = &c;
      enh_job* j = nullptr;
      CHECK(enh_job_create(se.s, q(id).dump().c_str(), &j) == ENH_OK);
      CHECK(enh_job_start(j, on_event, 1) == ENH_OK);
      {
        std::unique_lock lk(c.mu);
        c.cv.wait_for(lk, std::chrono::seconds(60), [&] {
          for (auto& e : c.evs)
            if (e.type == ENH_EV_PROGRESS && e.done > pass1 + 50) return true;
          return false;
        });
      }
      enh_job_pause(j);
      CHECK(wait_terminal(c, 10));
      CHECK(enh_job_status(j) == ENH_E_PAUSED);
      enh_job_destroy(j);
      CHECK(fs::exists(fs::join(dir, "x8/checkpoint.json")));
    }
    if (in_pass1) {  // as a kill after band 1 of the first pass leaves it
      json ck = json::parse(fs::read_text(fs::join(dir, "x8/checkpoint.json")));
      ck["band_idx"] = 1;
      fs::write_atomic(fs::join(dir, "x8/checkpoint.json"), ck.dump());
      fs::remove_tree(fs::join(dir, "bands"));
      std::remove(fs::join(dir, "checkpoint.json").c_str());
    }
    Collector c;
    g_col = &c;
    enh_job* j = nullptr;
    CHECK(enh_job_resume(se.s, dir.c_str(), &j) == ENH_OK);
    CHECK(enh_job_start(j, on_event, 2) == ENH_OK);
    CHECK(wait_terminal(c));
    enh_job_destroy(j);
    check_invariants(c);
    std::lock_guard lk(c.mu);
    CHECK(c.evs.back().type == ENH_EV_DONE);
    int64_t first = -1;
    for (auto& e : c.evs) {
      if (e.type == ENH_EV_PROGRESS && first < 0) first = e.done;
      CHECK(!(e.type == ENH_EV_WARNING && e.payload.value("code", "") == "resume_restarted"));
    }
    CHECK(in_pass1 ? first == 2 * tpb1 : first > pass1);
    CHECK(read_output(dir).px == read_output(fs::join(g_work, "x8_ref")).px);
    CHECK(!fs::exists(fs::join(dir, "x8")));
  }
}

// NFR-THERM-002: critical holds the job before its next tile until fair; serious throttles.
static void test_thermal(Session& se, const std::string& in) {
  auto warnings = [](Collector& c) {
    std::vector<std::string> w;
    std::lock_guard lk(c.mu);
    for (auto& e : c.evs)
      if (e.type == ENH_EV_WARNING) w.push_back(e.payload.value("code", ""));
    return w;
  };
  auto progress = [](Collector& c) {
    std::lock_guard lk(c.mu);
    int64_t done = -1;
    for (auto& e : c.evs)
      if (e.type == ENH_EV_PROGRESS) done = e.done;
    return done;
  };
  {
    Collector c;
    g_col = &c;
    enh_set_thermal(se.s, 4);
    enh_job* j = nullptr;
    std::string r = slow_req("th_crit", in).dump();
    CHECK(enh_job_create(se.s, r.c_str(), &j) == ENH_OK);
    CHECK(enh_job_start(j, on_event, 1) == ENH_OK);
    {
      std::unique_lock lk(c.mu);
      c.cv.wait_for(lk, std::chrono::seconds(30), [&] {
        for (auto& e : c.evs)
          if (e.type == ENH_EV_WARNING && e.payload.value("code", "") == "thermal_wait")
            return true;
        return false;
      });
    }
    const int64_t held = progress(c);
    std::this_thread::sleep_for(std::chrono::milliseconds(600));
    CHECK(progress(c) == held);  // no tile while critical
    CHECK(c.terminals == 0);
    enh_set_thermal(se.s, 2);  // fair
    CHECK(wait_terminal(c));
    CHECK(enh_job_status(j) == ENH_OK);
    enh_job_destroy(j);
    check_invariants(c);
    auto w = warnings(c);
    CHECK(std::count(w.begin(), w.end(), "thermal_wait") == 1);
    CHECK(std::count(w.begin(), w.end(), "thermal_resumed") == 1);
  }
  {  // waiting does not block pause
    Collector c;
    g_col = &c;
    enh_set_thermal(se.s, 4);
    enh_job* j = nullptr;
    std::string r = slow_req("th_pause", in).dump();
    CHECK(enh_job_create(se.s, r.c_str(), &j) == ENH_OK);
    CHECK(enh_job_start(j, on_event, 1) == ENH_OK);
    CHECK(wait_for(c, ENH_EV_WARNING, 30));
    enh_job_pause(j);
    CHECK(wait_terminal(c, 5));
    CHECK(enh_job_status(j) == ENH_E_PAUSED);
    enh_job_destroy(j);
  }
  {
    Collector c;
    enh_set_thermal(se.s, 3);  // serious
    CHECK(run_job(se, req("th_serious", in, "nearest4"), c).status == ENH_OK);
    auto w = warnings(c);
    CHECK(std::count(w.begin(), w.end(), "thermal_throttle") == 1);
    CHECK(std::count(w.begin(), w.end(), "thermal_wait") == 0);
  }
  enh_set_thermal(se.s, 0);
}

static void test_needs_user(Session& se) {
  std::string in = make_jpeg("nu.jpg", 200, 150);
  for (bool cancel : {false, true}) {
    Collector c;
    g_col = &c;
    json q = req(cancel ? "nu_c" : "nu", in, "nearest4");
    q["max_output_mp"] = 0.2;  // x4 = 0.48 MP, x2 = 0.12 MP
    enh_job* j = nullptr;
    std::string r = q.dump();
    CHECK(enh_job_create(se.s, r.c_str(), &j) == ENH_OK);
    CHECK(enh_job_start(j, on_event, 1) == ENH_OK);
    CHECK(wait_for(c, ENH_EV_NEEDS_USER));
    {
      std::lock_guard lk(c.mu);
      for (auto& e : c.evs)
        if (e.type == ENH_EV_NEEDS_USER) {
          CHECK(e.payload["code"] == "downscale_required");
          CHECK(e.payload["options"].size() >= 2);
        }
    }
    if (cancel) {
      enh_job_cancel(j);
    } else {
      CHECK(enh_job_answer(j, "{\"scale\":2,\"fast2\":true}") == ENH_OK);
    }
    CHECK(wait_terminal(c));
    CHECK(enh_job_status(j) == (cancel ? ENH_E_CANCELLED : ENH_OK));
    enh_job_destroy(j);
    check_invariants(c);
  }
  CHECK(read_output(fs::join(g_work, "nu")).w == 400);  // fast 2x: (200 / 2) * 4
}

// 8x on an input above 1.5 MP (ADR-0014) asks for a smaller scale, 4x first (the batch queue
// answers the first option).
static void test_x8_too_large(Session& se) {
  Collector c;
  g_col = &c;
  json q = req("x8big", make_jpeg("x8big.jpg", 1300, 1200), "nearest4");
  q["scale"] = 8;
  enh_job* j = nullptr;
  CHECK(enh_job_create(se.s, q.dump().c_str(), &j) == ENH_OK);
  CHECK(enh_job_start(j, on_event, 1) == ENH_OK);
  CHECK(wait_for(c, ENH_EV_NEEDS_USER));
  {
    std::lock_guard lk(c.mu);
    for (auto& e : c.evs)
      if (e.type == ENH_EV_NEEDS_USER) {
        CHECK(e.payload["code"] == "downscale_required");
        CHECK(e.payload["options"].size() >= 1 &&
              e.payload["options"][0] == json::parse(R"({"scale":4,"fast2":false})"));
      }
  }
  enh_job_cancel(j);
  CHECK(wait_terminal(c));
  enh_job_destroy(j);
  check_invariants(c);
}

// TEST-FAULT-001 (ADR-0016, NFR-MEM-004, FR-ENH-014): out of memory or a memory warning ->
// half-size sub-tiles with the same pixels; with no smaller tile left -> the user is asked
// for a smaller output, never a silent downscale.
static std::vector<Ev> fallbacks(Collector& c) {
  std::lock_guard lk(c.mu);
  std::vector<Ev> out;
  for (auto& e : c.evs)
    if (e.type == ENH_EV_FALLBACK) out.push_back(e);
  return out;
}

static void test_oom_ladder(Session& se) {
  std::string in = make_jpeg("oom.jpg", 230, 170);
  {
    Collector c;
    CHECK(run_job(se, req("oom_ref", in, "bilinear4"), c).status == ENH_OK);
  }
  const Rgb8 ref = read_output(fs::join(g_work, "oom_ref"));
  {  // tile 64 + pad 16 = 96 px input does not fit, 32 + 32 does
    setenv("ENH_FAULT", "cpu:oom_above:90", 1);
    Collector c;
    auto r = run_job(se, req("oom_tile", in, "bilinear4"), c);
    unsetenv("ENH_FAULT");
    CHECK(r.status == ENH_OK);
    auto f = fallbacks(c);
    CHECK(f.size() == 1);
    if (!f.empty()) {
      CHECK(f[0].payload["kind"] == "tile" && f[0].payload["reason"] == "oom");
      CHECK(f[0].payload["from"] == "64" && f[0].payload["to"] == "32");
    }
    CHECK(read_output(fs::join(g_work, "oom_tile")).px == ref.px);
    CHECK(r.payload["fallbacks"] == json::array({"tile:64->32"}));
  }
  {  // a memory warning after the job was created: its first tile is already smaller; one from
     // before (the previous job's) does not count
    enh_set_memory_pressure(se.s, 3);
    Collector c;
    g_col = &c;
    const std::string q = req("oom_pressure", in, "bilinear4").dump();
    enh_job* j = nullptr;
    CHECK(enh_job_create(se.s, q.c_str(), &j) == ENH_OK);
    enh_set_memory_pressure(se.s, 2);
    CHECK(enh_job_start(j, on_event, 4) == ENH_OK);
    CHECK(wait_terminal(c));
    CHECK(enh_job_status(j) == ENH_OK);
    enh_job_destroy(j);
    check_invariants(c);
    enh_set_memory_pressure(se.s, 0);
    auto f = fallbacks(c);
    CHECK(f.size() == 1 && f[0].payload["reason"] == "memory_pressure");
    CHECK(read_output(fs::join(g_work, "oom_pressure")).px == ref.px);
  }
  // No smaller tile (32 + 32 > 50) and no other backend: NEEDS_USER oom_downscale. A wrong
  // answer ends the job; 2x runs the job again (here with the memory back).
  for (const char* answer : {"{\"scale\":1,\"fast2\":false}", "{\"scale\":2,\"fast2\":false}"}) {
    const bool good = std::string(answer).find("\"scale\":2") != std::string::npos;
    setenv("ENH_FAULT", "cpu:oom_above:50", 1);
    Collector c;
    g_col = &c;
    const std::string id = good ? "oom_down" : "oom_bad";
    const std::string r = req(id, in, "nearest4").dump();
    enh_job* j = nullptr;
    CHECK(enh_job_create(se.s, r.c_str(), &j) == ENH_OK);
    CHECK(enh_job_start(j, on_event, 3) == ENH_OK);
    CHECK(wait_for(c, ENH_EV_NEEDS_USER));
    {
      std::lock_guard lk(c.mu);
      for (auto& e : c.evs)
        if (e.type == ENH_EV_NEEDS_USER) {
          CHECK(e.payload["code"] == "oom_downscale" && e.payload["scale"] == 4);
          CHECK(e.payload["options"] == json::parse(R"([{"scale":2,"fast2":false},
                                                        {"scale":2,"fast2":true}])"));
        }
    }
    unsetenv("ENH_FAULT");
    CHECK(enh_job_answer(j, answer) == ENH_OK);
    CHECK(wait_terminal(c));
    CHECK(enh_job_status(j) == (good ? ENH_OK : ENH_E_INVALID));
    enh_job_destroy(j);
    check_invariants(c);
  }
  CHECK(read_output(fs::join(g_work, "oom_down")).w == 460);
  CHECK(json::parse(fs::read_text(fs::join(g_work, "oom_down/request.json")))["scale"] == 2);
}

static void test_errors(Session& se) {
  enh_job* j = nullptr;
  CHECK(enh_job_create(se.s, "not json", &j) == ENH_E_INVALID);
  CHECK(enh_job_create(se.s, "{\"schema\":1,\"job_id\":\"../x\",\"input\":\"a\"}", &j) ==
        ENH_E_INVALID);
  CHECK(enh_job_create(se.s, "{\"schema\":1,\"job_id\":\"x\",\"input\":\"a\",\"scale\":3}", &j) ==
        ENH_E_INVALID);
  std::string txt = fs::join(g_root, "not_a_jpeg.png");
  fs::write_atomic(txt, std::string("\x89PNG\r\n\x1a\n"));
  {
    Collector c;
    CHECK(run_job(se, req("e1", txt, "nearest4"), c).status == ENH_E_INVALID);
  }
  {
    Collector c;
    CHECK(run_job(se, req("e2", make_jpeg("e.jpg", 40, 40), "missing.model"), c).status ==
          ENH_E_MODEL);
  }
  {  // the last rung of the backend ladder fails -> terminal ERROR, not a crash
    setenv("ENH_FAULT", "cpu:numeric:2", 1);
    Collector c;
    CHECK(run_job(se, req("e4", make_jpeg("e4.jpg", 300, 200), "nearest4"), c).status ==
          ENH_E_NUMERIC);
    unsetenv("ENH_FAULT");
  }
  {  // FR-FACE-007: faces_off boxes are four finite non-negative numbers, at most 32
    json q = req("fo", make_jpeg("fo.jpg", 40, 40), "nearest4");
    for (const char* bad : {"[[1,2,3]]", "[[1,2,3,-4]]", "[\"x\"]", "[[1,2,3,1e999]]"}) {
      q["faces_off"] = json::parse(bad, nullptr, false);
      const std::string r = q.dump();
      CHECK(enh_job_create(se.s, r.c_str(), &j) == ENH_E_INVALID);
    }
    q["faces_off"] = json::array();
    for (int i = 0; i < 33; ++i) q["faces_off"].push_back({i, i, 10, 10});
    std::string r = q.dump();
    CHECK(enh_job_create(se.s, r.c_str(), &j) == ENH_E_INVALID);
    q["faces_off"] = json::array({{1.5, 2, 30, 30}});
    r = q.dump();
    CHECK(enh_job_create(se.s, r.c_str(), &j) == ENH_OK);
    CHECK(json::parse(fs::read_text(fs::join(g_work, "fo/request.json")))["faces_off"][0][0] ==
          1.5);
    enh_job_destroy(j);
  }
  enh_job_destroy(nullptr);
  enh_job_cancel(nullptr);
  CHECK(enh_job_status(nullptr) == ENH_E_INVALID);
  // Destroying a never-started job is fine.
  {  // 8x: not with fast 2x
    json q = req("x8f", txt, "nearest4");
    q["scale"] = 8;
    q["fast2"] = true;
    CHECK(enh_job_create(se.s, q.dump().c_str(), &j) == ENH_E_INVALID);
    q["fast2"] = false;
    q["scale"] = 3;
    CHECK(enh_job_create(se.s, q.dump().c_str(), &j) == ENH_E_INVALID);
  }
  CHECK(enh_job_create(se.s, req("e3", txt, "nearest4").dump().c_str(), &j) == ENH_OK);
  enh_job_destroy(j);
}

int main(int argc, char** argv) {
  g_root = argc > 1 ? argv[1] : "test-work-job";
  fs::remove_tree(g_root);
  g_models = fs::join(g_root, "models");
  g_work = fs::join(g_root, "jobs");
  fs::mkdirs(g_models);
  fs::mkdirs(g_work);
  make_model("nearest4", 1);
  make_model("bilinear4", 2);
  {
    Session se;
    test_nearest_exact(se);
    test_tiled_equals_whole(se);
    test_viewer(se);
    test_crop(se);
    test_orientation(se);
    test_jpeg_clean(se);
    test_export(se);
    test_lanczos();
    test_icc_validation();
    test_png_input(se);
    test_export_metadata(se);
    std::string slow = make_jpeg("slow.jpg", 640, 480);
    // Large enough that the job cannot finish before the cancel, even with AVX kernels.
    test_cancel(se, make_jpeg("slower.jpg", 2048, 1536));
    test_pause_resume(se, slow);
    test_thermal(se, slow);
    test_x8_resume(se);
    test_x8_too_large(se);
    test_needs_user(se);
    test_oom_ladder(se);
    test_errors(se);
  }
  std::printf("test_job: %d failures\n", fails);
  return fails ? 1 : 0;
}
