// Faces (ADR-0012): alignment, warp and paste on synthetic data; YuNet in the core against
// OpenCV FaceDetectorYN on public-domain photos (tests/data/faces) when the detector weights
// are in MODELS_DIR (tools/models/fetch.sh, models.lock); a full job with the face pack when
// face.gfpgan-1.4 is there too (nightly, 177 MB).
//   test_faces DATA_DIR [MODELS_DIR WORK_DIR]
// SPDX-License-Identifier: Apache-2.0
#include <net.h>
#include <unistd.h>

#include <cmath>
#include <cstdio>
#include <nlohmann/json.hpp>
#include <string>
#include <vector>

#include "backend/backend.hpp"
#include "enh.h"
#include "image/decode.hpp"
#include "mini_test.hpp"
#include "pipeline/faces.hpp"
#include "policy/analyze.hpp"
#include "util/fs.hpp"

using namespace enh;

static std::string g_data, g_models, g_work;

static Rgb8 gradient(int w, int h) {
  Rgb8 m;
  m.w = w;
  m.h = h;
  m.px.resize(size_t(w) * h * 3);
  for (int y = 0; y < h; ++y)
    for (int x = 0; x < w; ++x) {
      uint8_t* p = m.row(y) + 3 * x;
      p[0] = uint8_t(x * 255 / std::max(1, w - 1));
      p[1] = uint8_t(y * 255 / std::max(1, h - 1));
      p[2] = uint8_t((x + y) % 256);
    }
  return m;
}

TEST("alignment recovers a similarity from the five landmarks") {
  // Template points pushed through a known similarity: the fit must give it back.
  const double tmpl[10] = {192.98138, 239.94708, 318.90277, 240.19366, 256.63416,
                           314.01935, 201.26117, 371.41043, 313.08905, 371.15118};
  Affine m;  // image -> face: scale 0.8, rotation 12 degrees, shift
  const double k = 0.8, t = 12 * M_PI / 180;
  m.a = k * std::cos(t);
  m.c = k * std::sin(t);
  m.b = -m.c;
  m.d = m.a;
  m.tx = -40;
  m.ty = 25;
  const Affine inv = m.inverse();
  Face f;
  for (int i = 0; i < 5; ++i) {
    double x, y;
    inv.apply(tmpl[2 * i], tmpl[2 * i + 1], &x, &y);
    f.lm[2 * i] = float(x);
    f.lm[2 * i + 1] = float(y);
  }
  const Affine got = face_alignment(f);
  CHECK(std::abs(got.a - m.a) < 1e-4 && std::abs(got.c - m.c) < 1e-4);
  CHECK(std::abs(got.tx - m.tx) < 1e-2 && std::abs(got.ty - m.ty) < 1e-2);
}

TEST("warp by the identity is the image; inverse undoes") {
  const Rgb8 img = gradient(37, 29);
  CHECK(warp_affine(img, Affine{}, 37, 29).px == img.px);
  Affine m;
  m.tx = 3;
  m.ty = -2;
  const Affine back = m.inverse();
  double x, y;
  back.apply(13, 7, &x, &y);
  CHECK(std::abs(x - 10) < 1e-12 && std::abs(y - 9) < 1e-12);
}

TEST("paste: strength 0 changes nothing; the crop centre takes the restored face") {
  const int scale = 2, ow = 1200, oh = 900;
  Affine align;  // the 512 face is the input square [100, 356) x [50, 306)
  align.tx = -100;
  align.ty = -50;
  Rgb8 face;
  face.w = face.h = kFaceSide;
  face.px.assign(size_t(kFaceSide) * kFaceSide * 3, 200);
  std::vector<uint8_t> band(size_t(ow) * oh * 3, 10);
  const auto before = band;
  paste_faces(band.data(), ow, 0, oh, {prepare_paste(align, face, scale, 0.f, ow, oh)});
  CHECK(band == before);
  const RestoredFace r = prepare_paste(align, face, scale, 1.f, ow, oh);
  CHECK(r.x0 <= 200 && r.x1 >= 712 && r.y0 <= 100 && r.y1 >= 612);
  // Two bands: the paste is applied per band and must match a single pass.
  std::vector<uint8_t> whole = band, split = band;
  paste_faces(whole.data(), ow, 0, oh, {r});
  paste_faces(split.data(), ow, 0, 400, {r});
  paste_faces(split.data() + size_t(400) * ow * 3, ow, 400, oh - 400, {r});
  CHECK(whole == split);
  const uint8_t* centre = whole.data() + (size_t(356) * ow + 456) * 3;  // (100+128)*2, (50+128)*2
  CHECK(centre[0] == 200 && centre[1] == 200);
  const uint8_t* outside = whole.data() + (size_t(50) * ow + 50) * 3;
  CHECK(outside[0] == 10);
  // The feathered edge blends in between.
  const uint8_t* edge = whole.data() + (size_t(356) * ow + 205 + 2 * 40) * 3;
  CHECK(edge[0] > 10 && edge[0] < 200);
}

// Outputs given by the test (the decoder is checked apart from the network's numerics).
class FakeYunet final : public InferenceBackend {
 public:
  std::vector<ncnn::Mat> outs;
  std::string name() const override { return "fake"; }
  const BackendConfig& config() const override { return cfg_; }
  void load(const ModelInfo&) override {}
  void run(const ncnn::Mat&, ncnn::Mat&) override {}
  std::vector<ncnn::Mat> run_outputs(const ncnn::Mat& in) override {
    seen_w = in.w;
    seen_h = in.h;
    return outs;
  }
  void set_threads(int) override {}
  int threads() const override { return 1; }
  int seen_w = 0, seen_h = 0;

 private:
  BackendConfig cfg_;
};

TEST("colour match: the restored face takes the original's mean Lab colour (FR-FACE-008)") {
  // A face model that warms the colour: the paste must not bring the tint along.
  Rgb8 aligned = gradient(kFaceSide, kFaceSide), restored = aligned;
  for (size_t i = 0; i < restored.px.size(); i += 3) {
    restored.px[i] = uint8_t(std::min(255, restored.px[i] + 40));
    restored.px[i + 2] = uint8_t(std::max(0, restored.px[i + 2] - 30));
  }
  double before[3], want[3], after[3];
  masked_mean_lab(restored, before);
  masked_mean_lab(aligned, want);
  const double de = match_face_color(restored, aligned);
  masked_mean_lab(restored, after);
  const double de_after =
      std::hypot(std::hypot(after[0] - want[0], after[1] - want[1]), after[2] - want[2]);
  std::printf("  dE %.1f -> %.2f\n", de, de_after);
  CHECK(de > 10);
  CHECK(de_after <= 3);
  // The same colour: nothing changes beyond rounding.
  Rgb8 same = aligned;
  CHECK(match_face_color(same, aligned) < 1e-9);
  size_t diff = 0;
  for (size_t i = 0; i < same.px.size(); ++i)
    diff = std::max<size_t>(diff, std::abs(same.px[i] - aligned.px[i]));
  CHECK(diff <= 1);
}

TEST("YuNet decoding: grid cells, strides, NMS, threshold, back to image coordinates") {
  FakeYunet y;
  const int strides[3] = {8, 16, 32};
  for (int k = 0; k < 3; ++k) {
    const int n = (kYunetSide / strides[k]) * (kYunetSide / strides[k]);
    for (int part = 0; part < 4; ++part) {
      const int dim = part == 2 ? 4 : part == 3 ? 10 : 1;
      ncnn::Mat m(dim, n);
      m.fill(0.f);
      y.outs.push_back(m);
    }
  }
  // Reorder to cls_8..32, obj_8..32, bbox_8..32, kps_8..32.
  std::vector<ncnn::Mat> ordered(12);
  for (int k = 0; k < 3; ++k)
    for (int part = 0; part < 4; ++part) ordered[part * 3 + k] = y.outs[k * 4 + part];
  y.outs = ordered;
  auto set = [&](int k, int cell, float score, float dx, float dy, float lw, float lh, float kp) {
    y.outs[k].row(cell)[0] = score;
    y.outs[3 + k].row(cell)[0] = score;
    float* b = y.outs[6 + k].row(cell);
    b[0] = dx, b[1] = dy, b[2] = lw, b[3] = lh;
    for (int i = 0; i < 10; ++i) y.outs[9 + k].row(cell)[i] = kp;
  };
  const int cols8 = kYunetSide / 8;
  set(0, 30 * cols8 + 40, 0.9f, 0.5f, 0.25f, std::log(4.f), std::log(6.f), 0.5f);   // the face
  set(0, 30 * cols8 + 41, 0.85f, 0.5f, 0.25f, std::log(4.f), std::log(6.f), 0.5f);  // duplicate
  set(1, 5 * 40 + 5, 0.5f, 0, 0, 0, 0, 0);  // below the threshold
  const int cols32 = kYunetSide / 32;
  set(2, 2 * cols32 + 3, 0.95f, 0.f, 0.f, std::log(2.f), std::log(2.f), 0.f);  // larger, at 32
  // An image twice the analysis size: coordinates come back doubled.
  const Rgb8 img = gradient(1280, 960);
  const auto f = detect_faces(y, img);
  CHECK(y.seen_w == kYunetSide && y.seen_h == kYunetSide);
  CHECK(f.size() == 2);
  if (f.size() != 2) return;
  // Largest first: the stride-32 one, 64x64 analysis px at cell (3, 2) -> centre (96, 64).
  CHECK(std::abs(f[0].x - 2 * (96 - 32)) < 1e-3 && std::abs(f[0].w - 128) < 1e-3);
  CHECK(std::abs(f[0].score - 0.95f) < 1e-6);
  // The stride-8 face: centre ((40.5)*8, (30.25)*8) = (324, 242), 32x48.
  CHECK(std::abs(f[1].x - 2 * (324 - 16)) < 1e-3 && std::abs(f[1].y - 2 * (242 - 24)) < 1e-3);
  CHECK(std::abs(f[1].w - 64) < 1e-3 && std::abs(f[1].h - 96) < 1e-3);
  CHECK(std::abs(f[1].lm[0] - 2 * 324) < 1e-3 && std::abs(f[1].lm[1] - 2 * 244) < 1e-3);
}

TEST("YuNet in the core finds what OpenCV FaceDetectorYN finds") {
  if (g_models.empty() || !fs::exists(fs::join(g_models, "det.yunet-2023mar/model.ncnn.bin"))) {
    std::printf("  no detector weights: skipped\n");
    return;
  }
  auto det = make_ncnn_backend({BackendKind::cpu, 0, false, 0});
  det->load(resolve_model(g_models, "det.yunet-2023mar"));
  const auto ref = nlohmann::json::parse(fs::read_text(fs::join(g_data, "opencv_yunet.json")));
  for (const auto& [name, rows] : ref.items()) {
    const Rgb8 img = decode_image(fs::join(g_data, name));
    const auto faces = detect_faces(*det, img);
    std::printf("  %s: %zu faces (OpenCV %zu)\n", name.c_str(), faces.size(), rows.size());
    CHECK(faces.size() == rows.size());
    size_t strict = 0;
    for (const auto& r : rows) {
      const float rx = r[0], ry = r[1], rw = r[2], rh = r[3];
      // The best match by box overlap, then the landmarks within 4% of the face width.
      const Face* best = nullptr;
      double best_iou = 0;
      for (const Face& f : faces) {
        const double x0 = std::max(f.x, rx), y0 = std::max(f.y, ry);
        const double x1 = std::min(f.x + f.w, rx + rw), y1 = std::min(f.y + f.h, ry + rh);
        const double in = std::max(0.0, x1 - x0) * std::max(0.0, y1 - y0);
        const double iou = in / (f.w * f.h + rw * rh - in);
        if (iou > best_iou) best_iou = iou, best = &f;
      }
      double worst = 0;
      if (best) {
        for (int i = 0; i < 10; ++i)
          worst = std::max(worst, double(std::abs(best->lm[i] - float(r[4 + i]))));
      }
      const bool close = best_iou > 0.85 && worst < 0.04 * rw;
      strict += close ? 1 : 0;
      if (!close) {
        std::printf("    face %.0f,%.0f %.0fx%.0f: iou %.3f, landmarks off %.1f px\n", rx, ry, rw,
                    rh, best_iou, worst);
        if (best) {
          std::printf("      core  %.1f %.1f %.1f %.1f s=%.3f |", best->x, best->y, best->w,
                      best->h, best->score);
          for (int i = 0; i < 10; ++i) std::printf(" %.1f", best->lm[i]);
          std::printf("\n      opencv");
          for (int i = 0; i < 14; ++i) std::printf(" %.1f", float(r[i]));
          std::printf("\n");
        }
      }
      // The same face: two runtimes may let neighbouring anchors of near-equal score win the
      // NMS (ncnn vs OpenCV DNN numerics), so a few faces can differ by about one grid cell.
      CHECK(best_iou > 0.75);
    }
    // Box within IoU 0.85 and landmarks within 4% of the face width for at least 90%.
    CHECK(strict * 10 >= rows.size() * 9);
  }
}

TEST("noise estimate (Immerkaer) recovers the sigma of added Gaussian noise") {
  // A smooth image (the operator ignores linear content) plus N(0, sigma) per channel.
  uint32_t seed = 12345;
  auto gauss = [&] {  // Box-Muller from a LCG
    auto u = [&] {
      seed = seed * 1664525u + 1013904223u;
      return (seed >> 8) / 16777216.0 + 1e-12;
    };
    return std::sqrt(-2 * std::log(u())) * std::cos(2 * M_PI * u());
  };
  for (const double sigma : {0.0, 5.0, 10.0, 20.0}) {
    Rgb8 img;
    img.w = 600;
    img.h = 400;
    img.px.resize(size_t(img.w) * img.h * 3);
    for (int y = 0; y < img.h; ++y)
      for (int x = 0; x < img.w; ++x) {
        const double base = 60 + 0.15 * x + 0.1 * y;
        // The same noise on all channels: luma noise = sigma.
        const double n = sigma * gauss();
        for (int c = 0; c < 3; ++c)
          img.row(y)[3 * x + c] = uint8_t(std::clamp(base + n + 0.5, 0.0, 255.0));
      }
    const double est = estimate_noise(img);
    std::printf("  sigma %.0f -> %.2f\n", sigma, est);
    CHECK(std::abs(est - sigma) <= std::max(0.8, 0.12 * sigma));
  }
}

TEST("analyze: size, faces with the detector, noise") {
  if (g_models.empty() || !fs::exists(fs::join(g_models, "det.yunet-2023mar/model.ncnn.bin"))) {
    std::printf("  no detector weights: skipped\n");
    return;
  }
  enh_session_config cfg{};
  cfg.struct_size = sizeof cfg;
  cfg.models_dir = g_models.c_str();
  cfg.work_dir = g_work.c_str();
  enh_session* s = nullptr;
  CHECK(enh_session_create(&cfg, &s) == ENH_OK);
  char* out = nullptr;
  CHECK(enh_analyze(s, fs::join(g_data, "einstein.jpg").c_str(), &out) == ENH_OK);
  if (out) {
    const auto a = nlohmann::json::parse(out);
    enh_free(out);
    std::printf("  %s\n", a.dump().c_str());
    CHECK(a["width"] == 675 && a["height"] == 900);
    CHECK(a["faces"]["count"] == 1 && a["faces"]["detector"] == true);
    CHECK(a["faces"]["boxes"].size() == 1 && a["faces"]["boxes"][0].size() == 4);
    CHECK(a["noise_sigma"].get<double>() >= 0);
  }
  CHECK(enh_analyze(s, "/nonexistent.jpg", &out) != ENH_OK);
  enh_session_destroy(s);
}

TEST("a job with the face pack restores the face (nightly: needs face.gfpgan-1.4)") {
  if (g_models.empty() || !fs::exists(fs::join(g_models, "face.gfpgan-1.4/model.ncnn.bin")) ||
      !fs::exists(fs::join(g_models, "sr.general-x4v3/model.ncnn.bin"))) {
    std::printf("  no face pack: skipped\n");
    return;
  }
  enh_session_config cfg{};
  cfg.struct_size = sizeof cfg;
  cfg.models_dir = g_models.c_str();
  cfg.work_dir = g_work.c_str();
  cfg.backend_pref = ENH_BACKEND_NCNN_CPU;
  enh_session* s = nullptr;
  CHECK(enh_session_create(&cfg, &s) == ENH_OK);
  if (!s) return;
  nlohmann::json q = {
      {"schema", 1},         {"job_id", "faces"}, {"input", fs::join(g_data, "einstein.jpg")},
      {"scale", 2},          {"fast2", true},     {"face_model", "face.gfpgan-1.4"},
      {"face_strength", 0.5}};
  const std::string r = q.dump();
  enh_job* j = nullptr;
  CHECK(enh_job_create(s, r.c_str(), &j) == ENH_OK);
  struct Seen {
    int faces = -1;
    bool done = false;
  } seen;
  static Seen* g = nullptr;
  g = &seen;
  CHECK(enh_job_start(
            j,
            [](int64_t, int32_t type, int32_t, int64_t, int64_t, char* p) {
              const auto e = nlohmann::json::parse(p);
              enh_free(p);
              if (type == ENH_EV_WARNING && e.value("code", "") == "faces_found")
                g->faces = e["count"];
              if (type == ENH_EV_DONE) g->done = true;
            },
            1) == ENH_OK);
  for (int i = 0; i < 1200 && enh_job_status(j) < 0; ++i) usleep(100000);
  CHECK(enh_job_status(j) == ENH_OK);
  CHECK(seen.faces == 1);
  enh_job_destroy(j);

  // ADR-0016: a face that runs out of memory on CPU fp16 and fp32 is skipped, the job is done.
  setenv("ENH_FAULT", "cpu:oom_above:500", 1);  // the 512 px face, not the SR tiles
  q["job_id"] = "faces_oom";
  const std::string r1 = q.dump();
  CHECK(enh_job_create(s, r1.c_str(), &j) == ENH_OK);
  struct Fallbacks {
    std::vector<nlohmann::json> evs;
  } fb;
  static Fallbacks* gf = nullptr;
  gf = &fb;
  CHECK(enh_job_start(
            j,
            [](int64_t, int32_t type, int32_t, int64_t, int64_t, char* p) {
              const auto e = nlohmann::json::parse(p);
              enh_free(p);
              if (type == ENH_EV_FALLBACK) gf->evs.push_back(e);
            },
            3) == ENH_OK);
  for (int i = 0; i < 1200 && enh_job_status(j) < 0; ++i) usleep(100000);
  unsetenv("ENH_FAULT");
  CHECK(enh_job_status(j) == ENH_OK);
  enh_job_destroy(j);
  CHECK(fb.evs.size() == 2);
  if (fb.evs.size() == 2) {
    CHECK(fb.evs[0]["kind"] == "backend" && fb.evs[0]["to"] == "cpu_fp32");
    CHECK(fb.evs[1]["kind"] == "face" && fb.evs[1]["index"] == 0 && fb.evs[1]["reason"] == "oom");
  }

  // FR-FACE-007: the face turned off (its box from enh_analyze) is not restored; with that
  // one face, the result equals the job without faces.
  {
    char* aj = nullptr;
    CHECK(enh_analyze(s, fs::join(g_data, "einstein.jpg").c_str(), &aj) == ENH_OK);
    const auto box = nlohmann::json::parse(aj)["faces"]["boxes"][0];
    enh_free(aj);
    nlohmann::json off = q;
    off["job_id"] = "faces_off";
    off["faces_off"] = nlohmann::json::array({box});
    const std::string ro = off.dump();
    CHECK(enh_job_create(s, ro.c_str(), &j) == ENH_OK);
    seen = {};
    CHECK(enh_job_start(
              j,
              [](int64_t, int32_t type, int32_t, int64_t, int64_t, char* p) {
                const auto e = nlohmann::json::parse(p);
                enh_free(p);
                if (type == ENH_EV_WARNING && e.value("code", "") == "faces_found")
                  g->faces = e["count"].get<int>() * 10 + e["off"].get<int>();
              },
              4) == ENH_OK);
    for (int i = 0; i < 1200 && enh_job_status(j) < 0; ++i) usleep(100000);
    CHECK(enh_job_status(j) == ENH_OK);
    CHECK(seen.faces == 1);  // restored 0, off 1
    enh_job_destroy(j);
    nlohmann::json plain = q;
    plain.erase("face_model");
    plain["job_id"] = "faces_none";
    const std::string rp = plain.dump();
    CHECK(enh_job_create(s, rp.c_str(), &j) == ENH_OK);
    CHECK(enh_job_start(
              j, [](int64_t, int32_t, int32_t, int64_t, int64_t, char* p) { enh_free(p); }, 5) ==
          ENH_OK);
    for (int i = 0; i < 1200 && enh_job_status(j) < 0; ++i) usleep(100000);
    CHECK(enh_job_status(j) == ENH_OK);
    enh_job_destroy(j);
    CHECK(fs::read_all(fs::join(g_work, "faces_off/bands/0000.raw")) ==
          fs::read_all(fs::join(g_work, "faces_none/bands/0000.raw")));
  }

  // Region Faces (FR-FACE-006): the background is a Lanczos upscale, the SR model does not run.
  q["job_id"] = "faces_only";
  q["background"] = "lanczos";
  q["fast2"] = false;
  const std::string r2 = q.dump();
  CHECK(enh_job_create(s, r2.c_str(), &j) == ENH_OK);
  seen = {};
  CHECK(enh_job_start(
            j,
            [](int64_t, int32_t type, int32_t, int64_t, int64_t, char* p) {
              const auto e = nlohmann::json::parse(p);
              enh_free(p);
              if (type == ENH_EV_WARNING && e.value("code", "") == "faces_found")
                g->faces = e["count"];
            },
            2) == ENH_OK);
  for (int i = 0; i < 1200 && enh_job_status(j) < 0; ++i) usleep(100000);
  CHECK(enh_job_status(j) == ENH_OK);
  CHECK(seen.faces == 1);
  enh_job_destroy(j);
  const auto res = nlohmann::json::parse(fs::read_text(fs::join(g_work, "faces_only/result.json")));
  CHECK(res["backend"] == "lanczos");
  CHECK(res["width"] == 675 * 2 && res["height"] == 900 * 2);

  // Lanczos background without faces is not a region.
  nlohmann::json bad = q;
  bad.erase("face_model");
  bad["job_id"] = "bad";
  const std::string r3 = bad.dump();
  CHECK(enh_job_create(s, r3.c_str(), &j) == ENH_E_INVALID);
  enh_session_destroy(s);
}

int main(int argc, char** argv) {
  g_data = argc > 1 ? argv[1] : "tests/data/faces";
  g_models = argc > 2 ? argv[2] : "";
  g_work = argc > 3 ? argv[3] : "test-work-faces";
  fs::mkdirs(g_work);
  return mini::run_all();
}
