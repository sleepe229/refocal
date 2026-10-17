// SPDX-License-Identifier: Apache-2.0
#include "pipeline/faces.hpp"

#include <net.h>

#include <algorithm>
#include <cmath>
#include <nlohmann/json.hpp>
#include <utility>

#include "backend/backend.hpp"
#include "image/ops.hpp"
#include "util/error.hpp"
#include "util/fs.hpp"

namespace enh {
namespace {

// FFHQ-512 five-point template (facexlib face_restoration_helper.py), in YuNet's landmark
// order: the subject's right eye (image left), left eye, nose, mouth right, mouth left.
constexpr double kTemplate[10] = {192.98138, 239.94708, 318.90277, 240.19366, 256.63416,
                                  314.01935, 201.26117, 371.41043, 313.08905, 371.15118};

float iou(const Face& a, const Face& b) {
  const float x0 = std::max(a.x, b.x), y0 = std::max(a.y, b.y);
  const float x1 = std::min(a.x + a.w, b.x + b.w), y1 = std::min(a.y + a.h, b.y + b.h);
  const float inter = std::max(0.f, x1 - x0) * std::max(0.f, y1 - y0);
  const float uni = a.w * a.h + b.w * b.h - inter;
  return uni > 0 ? inter / uni : 0;
}

int reflect(int i, int n) {
  if (n == 1) return 0;
  while (i < 0 || i >= n) i = i < 0 ? -i : 2 * (n - 1) - i;
  return i;
}

// Weight of a face pixel in the paste mask: 1 inside, falling smoothly to 0 over the outer
// band of the 512 crop (the crop's border is background the model only padded).
float feather(double fx, double fy) {
  constexpr double kMargin = 24, kRamp = 72;
  const double e = std::min(std::min(fx, fy), std::min(kFaceSide - 1 - fx, kFaceSide - 1 - fy));
  const double t = std::clamp((e - kMargin) / kRamp, 0.0, 1.0);
  return float(t * t * (3 - 2 * t));
}

}  // namespace

void keep_restorable(std::vector<Face>& faces) {
  faces.erase(std::remove_if(faces.begin(), faces.end(),
                             [](const Face& f) { return std::min(f.w, f.h) < kMinFacePx; }),
              faces.end());
  if (faces.size() > kMaxFaces) faces.resize(kMaxFaces);
}

float iou(const Face& f, const FaceBox& b) {
  const float ix = std::max(0.f, std::min(f.x + f.w, b.x + b.w) - std::max(f.x, b.x));
  const float iy = std::max(0.f, std::min(f.y + f.h, b.y + b.h) - std::max(f.y, b.y));
  const float inter = ix * iy, uni = f.w * f.h + b.w * b.h - inter;
  return uni > 0 ? inter / uni : 0.f;
}

std::vector<Face> detect_faces(InferenceBackend& yunet, const Rgb8& img, float min_score,
                               float nms_iou) {
  if (img.w <= 0 || img.h <= 0) return {};
  const double s = std::min(1.0, double(kYunetSide) / std::max(img.w, img.h));
  Rgb8 small =
      s < 1 ? resize_area(img, std::max(1, int(img.w * s + 0.5)), std::max(1, int(img.h * s + 0.5)))
            : img;
  // BGR 0..255, padded to 640x640 at the right and bottom (zeros).
  ncnn::Mat in(kYunetSide, kYunetSide, 3);
  in.fill(0.f);
  for (int y = 0; y < small.h; ++y) {
    const uint8_t* p = small.row(y);
    float* b = in.channel(0).row(y);
    float* g = in.channel(1).row(y);
    float* r = in.channel(2).row(y);
    for (int x = 0; x < small.w; ++x) {
      r[x] = p[3 * x];
      g[x] = p[3 * x + 1];
      b[x] = p[3 * x + 2];
    }
  }
  const std::vector<ncnn::Mat> out = yunet.run_outputs(in);
  if (out.size() != 12) fail(ENH_E_MODEL, "face detector: expected 12 outputs");

  std::vector<Face> faces;
  const int strides[3] = {8, 16, 32};
  for (int k = 0; k < 3; ++k) {
    const int st = strides[k], cols = kYunetSide / st, n = cols * cols;
    const ncnn::Mat &cls = out[k], &obj = out[3 + k], &box = out[6 + k], &kps = out[9 + k];
    if (int(cls.total()) != n || int(obj.total()) != n || int(box.total()) != 4 * n ||
        int(kps.total()) != 10 * n) {
      fail(ENH_E_MODEL, "face detector: unexpected output shape");
    }
    const float *pc = cls, *po = obj, *pb = box, *pk = kps;
    for (int i = 0; i < n; ++i) {
      const float score = std::sqrt(std::clamp(pc[i], 0.f, 1.f) * std::clamp(po[i], 0.f, 1.f));
      if (score < min_score) continue;
      const int r = i / cols, c = i % cols;
      const float* b = pb + 4 * i;
      const float cx = (c + b[0]) * st, cy = (r + b[1]) * st;
      const float w = std::exp(b[2]) * st, h = std::exp(b[3]) * st;
      Face f;
      f.score = score;
      f.x = float((cx - w / 2) / s);
      f.y = float((cy - h / 2) / s);
      f.w = float(w / s);
      f.h = float(h / s);
      for (int j = 0; j < 5; ++j) {
        f.lm[2 * j] = float((pk[10 * i + 2 * j] + c) * st / s);
        f.lm[2 * j + 1] = float((pk[10 * i + 2 * j + 1] + r) * st / s);
      }
      faces.push_back(f);
    }
  }
  // Non-maximum suppression by score, then the largest face first.
  std::sort(faces.begin(), faces.end(),
            [](const Face& a, const Face& b) { return a.score > b.score; });
  std::vector<Face> kept;
  for (const Face& f : faces) {
    if (std::none_of(kept.begin(), kept.end(), [&](const Face& k) { return iou(f, k) > nms_iou; }))
      kept.push_back(f);
  }
  std::sort(kept.begin(), kept.end(),
            [](const Face& a, const Face& b) { return a.w * a.h > b.w * b.h; });
  return kept;
}

std::vector<Face> detect_small_faces(InferenceBackend& yunet, const Rgb8& img, float min_score) {
  if (img.w <= 0 || img.h <= 0 || double(img.w) * img.h > kSmallPhotoPx) return {};
  constexpr int f = kSmallFaceUpscale, T = kYunetSide, kOverlap = 96;  // > a 30 px face
  const int uw = img.w * f, uh = img.h * f;
  auto origins = [&](int n) {
    std::vector<int> o;
    for (int v = 0;; v += T - kOverlap) {
      if (v + T >= n) {
        o.push_back(std::max(0, n - T));
        break;
      }
      o.push_back(v);
    }
    return o;
  };
  std::vector<Face> all;
  Rgb8 tile;
  for (int ty : origins(uh))
    for (int tx : origins(uw)) {
      // The tile of the upscale, sampled bilinearly from the photo (pixel centres aligned).
      tile.w = std::min(T, uw - tx);
      tile.h = std::min(T, uh - ty);
      tile.px.resize(size_t(tile.w) * tile.h * 3);
      for (int y = 0; y < tile.h; ++y) {
        const float fy = std::clamp((ty + y + 0.5f) / f - 0.5f, 0.f, float(img.h - 1));
        const int y0 = int(fy), y1 = std::min(y0 + 1, img.h - 1);
        const float ay = fy - y0;
        uint8_t* d = tile.row(y);
        for (int x = 0; x < tile.w; ++x) {
          const float fx = std::clamp((tx + x + 0.5f) / f - 0.5f, 0.f, float(img.w - 1));
          const int x0 = int(fx), x1 = std::min(x0 + 1, img.w - 1);
          const float ax = fx - x0;
          for (int c = 0; c < 3; ++c) {
            const float top = img.row(y0)[x0 * 3 + c] * (1 - ax) + img.row(y0)[x1 * 3 + c] * ax;
            const float bot = img.row(y1)[x0 * 3 + c] * (1 - ax) + img.row(y1)[x1 * 3 + c] * ax;
            d[x * 3 + c] = uint8_t(std::lround(top * (1 - ay) + bot * ay));
          }
        }
      }
      for (Face fc : detect_faces(yunet, tile, min_score)) {
        fc.x = (fc.x + tx) / f;
        fc.y = (fc.y + ty) / f;
        fc.w /= f;
        fc.h /= f;
        for (int j = 0; j < 5; ++j) {
          fc.lm[2 * j] = (fc.lm[2 * j] + tx) / f;
          fc.lm[2 * j + 1] = (fc.lm[2 * j + 1] + ty) / f;
        }
        if (std::min(fc.w, fc.h) >= kMinSmallFacePx) all.push_back(fc);
      }
    }
  // The same face from two overlapping tiles: the better scored one.
  std::sort(all.begin(), all.end(), [](const Face& a, const Face& b) { return a.score > b.score; });
  std::vector<Face> kept;
  for (const Face& fc : all)
    if (std::none_of(kept.begin(), kept.end(), [&](const Face& k) { return iou(fc, k) > 0.3f; }))
      kept.push_back(fc);
  std::sort(kept.begin(), kept.end(),
            [](const Face& a, const Face& b) { return a.w * a.h > b.w * b.h; });
  if (kept.size() > kMaxFaces) kept.resize(kMaxFaces);
  return kept;
}

std::vector<Face> find_faces(InferenceBackend& yunet, const Rgb8& img) {
  std::vector<Face> found = detect_faces(yunet, img);
  keep_restorable(found);
  if (found.empty()) found = detect_small_faces(yunet, img);
  return found;
}

Affine Affine::inverse() const {
  const double det = a * d - b * c;
  if (std::abs(det) < 1e-12) fail(ENH_E_INTERNAL, "singular face transform");
  Affine r;
  r.a = d / det;
  r.b = -b / det;
  r.c = -c / det;
  r.d = a / det;
  r.tx = -(r.a * tx + r.b * ty);
  r.ty = -(r.c * tx + r.d * ty);
  return r;
}

Affine Affine::scaled(double s) const {
  Affine r = *this;
  r.a /= s;
  r.b /= s;
  r.c /= s;
  r.d /= s;
  return r;
}

Affine face_alignment(const Face& f) {
  // Closed-form least squares for x' = a*x - b*y + tx, y' = b*x + a*y + ty.
  double mx = 0, my = 0, mu = 0, mv = 0;
  for (int i = 0; i < 5; ++i) {
    mx += f.lm[2 * i];
    my += f.lm[2 * i + 1];
    mu += kTemplate[2 * i];
    mv += kTemplate[2 * i + 1];
  }
  mx /= 5;
  my /= 5;
  mu /= 5;
  mv /= 5;
  double sxx = 0, sab = 0, sba = 0;
  for (int i = 0; i < 5; ++i) {
    const double x = f.lm[2 * i] - mx, y = f.lm[2 * i + 1] - my;
    const double u = kTemplate[2 * i] - mu, v = kTemplate[2 * i + 1] - mv;
    sxx += x * x + y * y;
    sab += x * u + y * v;
    sba += x * v - y * u;
  }
  if (sxx < 1e-9) fail(ENH_E_INTERNAL, "degenerate face landmarks");
  Affine m;
  m.a = sab / sxx;
  m.c = sba / sxx;
  m.b = -m.c;
  m.d = m.a;
  m.tx = mu - (m.a * mx + m.b * my);
  m.ty = mv - (m.c * mx + m.d * my);
  return m;
}

Rgb8 warp_affine(const Rgb8& src, const Affine& m, int w, int h) {
  const Affine inv = m.inverse();
  Rgb8 out;
  out.w = w;
  out.h = h;
  out.px.resize(size_t(w) * h * 3);
  for (int y = 0; y < h; ++y) {
    uint8_t* o = out.row(y);
    for (int x = 0; x < w; ++x) {
      double sx, sy;
      inv.apply(x, y, &sx, &sy);
      const int x0 = int(std::floor(sx)), y0 = int(std::floor(sy));
      const double fx = sx - x0, fy = sy - y0;
      const uint8_t* p00 = src.row(reflect(y0, src.h)) + 3 * reflect(x0, src.w);
      const uint8_t* p01 = src.row(reflect(y0, src.h)) + 3 * reflect(x0 + 1, src.w);
      const uint8_t* p10 = src.row(reflect(y0 + 1, src.h)) + 3 * reflect(x0, src.w);
      const uint8_t* p11 = src.row(reflect(y0 + 1, src.h)) + 3 * reflect(x0 + 1, src.w);
      for (int ch = 0; ch < 3; ++ch) {
        const double v = (p00[ch] * (1 - fx) + p01[ch] * fx) * (1 - fy) +
                         (p10[ch] * (1 - fx) + p11[ch] * fx) * fy;
        o[3 * x + ch] = uint8_t(std::clamp(v + 0.5, 0.0, 255.0));
      }
    }
  }
  return out;
}

namespace {

// GFPGAN/CodeFormer io: RGB in [-1, 1], NCHW 1x3x512x512 (04 §3).
ncnn::Mat face_to_mat(const Rgb8& aligned) {
  if (aligned.w != kFaceSide || aligned.h != kFaceSide) fail(ENH_E_INTERNAL, "face not 512x512");
  ncnn::Mat in(kFaceSide, kFaceSide, 3);
  for (int y = 0; y < kFaceSide; ++y) {
    const uint8_t* p = aligned.row(y);
    for (int ch = 0; ch < 3; ++ch) {
      float* d = in.channel(ch).row(y);
      for (int x = 0; x < kFaceSide; ++x) d[x] = p[3 * x + ch] / 127.5f - 1.f;
    }
  }
  return in;
}

Rgb8 mat_to_face(const ncnn::Mat& out) {
  if (out.w != kFaceSide || out.h != kFaceSide || out.c != 3) {
    fail(ENH_E_MODEL, "face model: unexpected output shape");
  }
  Rgb8 face;
  face.w = face.h = kFaceSide;
  face.px.resize(size_t(kFaceSide) * kFaceSide * 3);
  for (int y = 0; y < kFaceSide; ++y) {
    uint8_t* o = face.row(y);
    for (int ch = 0; ch < 3; ++ch) {
      const float* s = out.channel(ch).row(y);
      for (int x = 0; x < kFaceSide; ++x) {
        o[3 * x + ch] = uint8_t(std::clamp((s[x] + 1.f) * 127.5f + 0.5f, 0.f, 255.f));
      }
    }
  }
  return face;
}

}  // namespace

Rgb8 restore_face(InferenceBackend& model, const Rgb8& aligned) {
  ncnn::Mat out;
  model.run(face_to_mat(aligned), out);
  return mat_to_face(out);
}

FaceModel resolve_face_model(const std::string& models_dir, const std::string& id) {
  FaceModel m;
  m.id = id;
  const std::string dir = fs::join(models_dir, id);
  const std::string meta = fs::join(dir, "model.json");
  if (fs::exists(meta)) {
    const auto j = nlohmann::json::parse(fs::read_text(meta), nullptr, false);
    if (j.is_discarded() || !j.is_object()) fail(ENH_E_MODEL, "bad model.json: " + id);
    m.split = j.value("split", std::string()) == "codeformer";
  }
  if (!m.split) {
    m.main = resolve_model(models_dir, id);
    return m;
  }
  for (auto [info, name] :
       {std::pair{&m.encoder, "encoder"}, std::pair{&m.generator, "generator"}}) {
    info->id = id + "/" + name;
    info->param_path = fs::join(dir, std::string(name) + ".ncnn.param");
    info->bin_path = fs::join(dir, std::string(name) + ".ncnn.bin");
    if (!fs::exists(info->param_path) || !fs::exists(info->bin_path)) {
      fail(ENH_E_MODEL, "model not installed: " + id);
    }
  }
  const std::string cb = fs::join(dir, "codebook.f32");
  const size_t n = size_t(kCodebookSize) * kCodeDim;
  if (fs::file_size(cb) != int64_t(n * sizeof(float))) fail(ENH_E_MODEL, "bad codebook: " + id);
  m.codebook.resize(n);
  fs::read_exact(cb, m.codebook.data(), n * sizeof(float));
  for (float v : m.codebook)
    if (!std::isfinite(v)) fail(ENH_E_MODEL, "bad codebook: " + id);
  return m;
}

ncnn::Mat codebook_lookup(const ncnn::Mat& logits, const std::vector<float>& codebook) {
  const int tokens = kCodeGrid * kCodeGrid;
  if (logits.w != kCodebookSize || logits.h * logits.c * logits.d != tokens) {
    fail(ENH_E_MODEL, "face model: unexpected logits shape");
  }
  if (codebook.size() != size_t(kCodebookSize) * kCodeDim) fail(ENH_E_MODEL, "no codebook");
  ncnn::Mat feat(kCodeGrid, kCodeGrid, kCodeDim);
  const float* rows = logits;  // contiguous: h rows of w (c = d = 1)
  for (int t = 0; t < tokens; ++t) {
    const float* r = rows + size_t(t) * kCodebookSize;
    const int best = int(std::max_element(r, r + kCodebookSize) - r);  // first of ties
    const float* code = codebook.data() + size_t(best) * kCodeDim;
    for (int c = 0; c < kCodeDim; ++c) feat.channel(c)[t] = code[c];
  }
  return feat;
}

FaceRestorer::FaceRestorer(const FaceModel& model, const BackendConfig& cfg) : model_(model) {
  a_ = make_ncnn_backend(cfg);
  a_->load(model.split ? model.encoder : model.main);
  if (model.split) {
    b_ = make_ncnn_backend(cfg);
    b_->load(model.generator);
  }
}

Rgb8 FaceRestorer::restore(const Rgb8& aligned, double fidelity) {
  if (!model_.split) return restore_face(*a_, aligned);
  if (!(fidelity >= 0 && fidelity <= 1)) fail(ENH_E_INVALID, "fidelity must be 0..1");
  auto enc = a_->run_inputs({face_to_mat(aligned)}, {"out0", "out1", "out2", "out3",
                                                     "out4"});  // logits, features at 32..256 px
  if (enc.size() != 5) fail(ENH_E_MODEL, "face model: unexpected encoder outputs");
  ncnn::Mat w(1, 1, 1);  // [1,1,1,1] in the graph: a scalar the fuse blocks broadcast
  w[0] = float(fidelity);
  auto gen =
      b_->run_inputs({codebook_lookup(enc[0], model_.codebook), enc[1], enc[2], enc[3], enc[4], w});
  if (gen.size() != 1) fail(ENH_E_MODEL, "face model: unexpected generator outputs");
  return mat_to_face(gen[0]);
}

namespace {

double srgb_to_linear(double c) {
  c /= 255.0;
  return c <= 0.04045 ? c / 12.92 : std::pow((c + 0.055) / 1.055, 2.4);
}
double linear_to_srgb(double c) {
  c = std::clamp(c, 0.0, 1.0);
  return 255.0 * (c <= 0.0031308 ? 12.92 * c : 1.055 * std::pow(c, 1 / 2.4) - 0.055);
}
double lab_f(double t) { return t > 216.0 / 24389 ? std::cbrt(t) : (24389.0 / 27 * t + 16) / 116; }
double lab_finv(double t) {
  return t * t * t > 216.0 / 24389 ? t * t * t : (116 * t - 16) * 27 / 24389;
}
constexpr double kXn = 0.95047, kYn = 1.0, kZn = 1.08883;  // D65

void rgb_to_lab(const uint8_t* p, double lab[3]) {
  const double r = srgb_to_linear(p[0]), g = srgb_to_linear(p[1]), b = srgb_to_linear(p[2]);
  const double x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / kXn;
  const double y = (0.2126729 * r + 0.7151522 * g + 0.0721750 * b) / kYn;
  const double z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / kZn;
  const double fx = lab_f(x), fy = lab_f(y), fz = lab_f(z);
  lab[0] = 116 * fy - 16;
  lab[1] = 500 * (fx - fy);
  lab[2] = 200 * (fy - fz);
}

void lab_to_rgb(const double lab[3], uint8_t* p) {
  const double fy = (lab[0] + 16) / 116, fx = fy + lab[1] / 500, fz = fy - lab[2] / 200;
  const double x = lab_finv(fx) * kXn, y = lab_finv(fy) * kYn, z = lab_finv(fz) * kZn;
  const double r = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z;
  const double g = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z;
  const double b = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z;
  p[0] = uint8_t(linear_to_srgb(r) + 0.5);
  p[1] = uint8_t(linear_to_srgb(g) + 0.5);
  p[2] = uint8_t(linear_to_srgb(b) + 0.5);
}

}  // namespace

void masked_mean_lab(const Rgb8& img, double lab[3]) {
  double sum[3] = {0, 0, 0}, w = 0;
  for (int y = 0; y < img.h; ++y)
    for (int x = 0; x < img.w; ++x) {
      const float m = feather(x, y);
      if (m <= 0) continue;
      double l[3];
      rgb_to_lab(img.row(y) + 3 * x, l);
      for (int c = 0; c < 3; ++c) sum[c] += m * l[c];
      w += m;
    }
  for (int c = 0; c < 3; ++c) lab[c] = w > 0 ? sum[c] / w : 0;
}

double match_face_color(Rgb8& restored, const Rgb8& aligned) {
  double want[3], have[3];
  masked_mean_lab(aligned, want);
  masked_mean_lab(restored, have);
  const double shift[3] = {want[0] - have[0], want[1] - have[1], want[2] - have[2]};
  const double de = std::sqrt(shift[0] * shift[0] + shift[1] * shift[1] + shift[2] * shift[2]);
  for (int y = 0; y < restored.h; ++y) {
    uint8_t* p = restored.row(y);
    for (int x = 0; x < restored.w; ++x, p += 3) {
      double l[3];
      rgb_to_lab(p, l);
      for (int c = 0; c < 3; ++c) l[c] += shift[c];
      l[0] = std::clamp(l[0], 0.0, 100.0);
      lab_to_rgb(l, p);
    }
  }
  return de;
}

RestoredFace prepare_paste(const Affine& align, Rgb8 restored, int scale, float strength, int out_w,
                           int out_h) {
  RestoredFace r;
  r.to_face = align.scaled(scale);
  r.face = std::move(restored);
  r.strength = std::clamp(strength, 0.f, 1.f);
  // Bounding box of the 512 crop in the output.
  const Affine back = r.to_face.inverse();
  double x0 = 1e18, y0 = 1e18, x1 = -1e18, y1 = -1e18;
  for (const auto [fx, fy] : {std::pair{0.0, 0.0},
                              {double(kFaceSide), 0.0},
                              {0.0, double(kFaceSide)},
                              {double(kFaceSide), double(kFaceSide)}}) {
    double ox, oy;
    back.apply(fx, fy, &ox, &oy);
    x0 = std::min(x0, ox);
    y0 = std::min(y0, oy);
    x1 = std::max(x1, ox);
    y1 = std::max(y1, oy);
  }
  r.x0 = std::clamp(int(std::floor(x0)), 0, out_w);
  r.x1 = std::clamp(int(std::ceil(x1)) + 1, 0, out_w);
  r.y0 = std::clamp(int(std::floor(y0)), 0, out_h);
  r.y1 = std::clamp(int(std::ceil(y1)) + 1, 0, out_h);
  return r;
}

void paste_faces(uint8_t* band, int w, int y, int rows, const std::vector<RestoredFace>& faces) {
  for (const RestoredFace& f : faces) {
    if (f.strength <= 0) continue;
    const int ya = std::max(y, f.y0), yb = std::min(y + rows, f.y1), xb = std::min(w, f.x1);
    for (int oy = ya; oy < yb; ++oy) {
      uint8_t* row = band + size_t(oy - y) * w * 3;
      for (int ox = f.x0; ox < xb; ++ox) {
        double fx, fy;
        f.to_face.apply(ox + 0.5, oy + 0.5, &fx, &fy);
        fx -= 0.5;
        fy -= 0.5;
        if (fx < 0 || fy < 0 || fx > kFaceSide - 1 || fy > kFaceSide - 1) continue;
        const float alpha = feather(fx, fy) * f.strength;
        if (alpha <= 0) continue;
        const int x0 = std::min(int(fx), kFaceSide - 2), y0 = std::min(int(fy), kFaceSide - 2);
        const double tx = fx - x0, ty = fy - y0;
        const uint8_t* p00 = f.face.row(y0) + 3 * x0;
        const uint8_t* p10 = f.face.row(y0 + 1) + 3 * x0;
        uint8_t* d = row + 3 * ox;
        for (int ch = 0; ch < 3; ++ch) {
          const double v = (p00[ch] * (1 - tx) + p00[3 + ch] * tx) * (1 - ty) +
                           (p10[ch] * (1 - tx) + p10[3 + ch] * tx) * ty;
          d[ch] = uint8_t(std::clamp(d[ch] + (v - d[ch]) * alpha + 0.5, 0.0, 255.0));
        }
      }
    }
  }
}

}  // namespace enh
