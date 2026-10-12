// End-to-end tests of the job ABI on synthetic ncnn models (no weights needed in CI):
//  - "nearest4": Interp x4 nearest -> the SR output must equal an exact nearest upscale, which
//    pins down tiling, padding, band assembly, x2/x1 downscale and fast 2x pixel by pixel;
//  - "bilinear4": Interp x4 bilinear -> tiled output must equal the single-tile pass.
// Also: EXIF orientation, cancel, pause + resume (byte-identical), NEEDS_USER, errors, export,
// and the event invariants (one terminal event, nothing after it, monotonic progress).
// SPDX-License-Identifier: Apache-2.0
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include <nlohmann/json.hpp>

#include "enh.h"
#include "image/jpeg.hpp"
#include "image/ops.hpp"
#include "util/error.hpp"
#include "util/fs.hpp"

using namespace enh;
using json = nlohmann::json;

static int fails = 0;
#define CHECK(c)                                                          \
  do {                                                                    \
    if (!(c)) {                                                           \
      std::fprintf(stderr, "%s:%d: FAIL %s\n", __FILE__, __LINE__, #c);   \
      ++fails;                                                            \
    }                                                                     \
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
  int64_t last = -1;
  for (auto& e : c.evs)
    if (e.type == ENH_EV_PROGRESS) {
      CHECK(e.done >= last && e.done <= e.total);
      last = e.done;
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
    const uint8_t exif[] = {'E', 'x', 'i', 'f', 0, 0, 'I', 'I', 42, 0, 8, 0, 0, 0, 1, 0, 0x12,
                            0x01, 3, 0, 1, 0, 0, 0, uint8_t(orientation), 0, 0, 0, 0, 0, 0, 0};
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

static void test_export(Session& se) {
  std::string dst = fs::join(g_root, "exported.jpg");
  char* out = nullptr;
  CHECK(enh_export(se.s, fs::join(g_work, "n2").c_str(), "{\"format\":\"jpeg\",\"quality\":90}",
                   dst.c_str(), &out) == ENH_OK);
  CHECK(out && json::parse(out)["width"] == 300);
  enh_free(out);
  JpegInfo ji = jpeg_probe(dst);
  CHECK(ji.w == 300 && ji.h == 202);
  CHECK(!fs::exists(dst + ".part"));
  CHECK(enh_export(se.s, fs::join(g_work, "n2").c_str(), "{\"format\":\"png\"}", dst.c_str(),
                   nullptr) == ENH_E_INVALID);
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
  CHECK(wait_for(c, ENH_EV_PROGRESS));
  std::this_thread::sleep_for(std::chrono::milliseconds(100));
  auto t0 = std::chrono::steady_clock::now();
  enh_job_cancel(j);
  CHECK(wait_terminal(c, 10));
  double ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
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

static void test_errors(Session& se) {
  enh_job* j = nullptr;
  CHECK(enh_job_create(se.s, "not json", &j) == ENH_E_INVALID);
  CHECK(enh_job_create(se.s, "{\"schema\":1,\"job_id\":\"../x\",\"input\":\"a\"}", &j) == ENH_E_INVALID);
  CHECK(enh_job_create(se.s, "{\"schema\":1,\"job_id\":\"x\",\"input\":\"a\",\"scale\":3}", &j) == ENH_E_INVALID);
  std::string txt = fs::join(g_root, "not_a_jpeg.png");
  fs::write_atomic(txt, std::string("\x89PNG\r\n\x1a\n"));
  {
    Collector c;
    CHECK(run_job(se, req("e1", txt, "nearest4"), c).status == ENH_E_INVALID);
  }
  {
    Collector c;
    CHECK(run_job(se, req("e2", make_jpeg("e.jpg", 40, 40), "missing.model"), c).status == ENH_E_MODEL);
  }
  {  // the last rung of the backend ladder fails -> terminal ERROR, not a crash
    setenv("ENH_FAULT", "cpu:numeric:2", 1);
    Collector c;
    CHECK(run_job(se, req("e4", make_jpeg("e4.jpg", 300, 200), "nearest4"), c).status == ENH_E_NUMERIC);
    unsetenv("ENH_FAULT");
  }
  enh_job_destroy(nullptr);
  enh_job_cancel(nullptr);
  CHECK(enh_job_status(nullptr) == ENH_E_INVALID);
  // Destroying a never-started job is fine.
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
    test_orientation(se);
    test_export(se);
    std::string slow = make_jpeg("slow.jpg", 640, 480);
    test_cancel(se, slow);
    test_pause_resume(se, slow);
    test_needs_user(se);
    test_errors(se);
  }
  std::printf("test_job: %d failures\n", fails);
  return fails ? 1 : 0;
}
