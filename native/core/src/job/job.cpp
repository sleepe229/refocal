// Job runner (ADR-0006, ADR-0012 for the 0.1 subset): decode (any format) -> orient -> [fast 2x] ->
// SR banded (prep -> infer -> post, depth-2 queues) -> BandStore -> preview -> result.
// Cancel/pause are checked at tile boundaries; queued tiles are dropped, the tile in flight
// finishes (S6: latency <= 1 tile). Exactly one terminal event per started job.
// SPDX-License-Identifier: Apache-2.0
#include "job/job.hpp"

#include <net.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstring>
#include <deque>
#include <functional>
#include <map>
#include <mutex>
#include <optional>
#include <regex>
#include <thread>
#include <utility>
#include <vector>

#include "backend/backend.hpp"
#include "enh.h"
#include "image/decode.hpp"
#include "image/jpeg.hpp"
#include "image/ops.hpp"
#include "job/events.hpp"
#include "job/session.hpp"
#include "pipeline/bandstore.hpp"
#include "pipeline/faces.hpp"
#include "pipeline/geometry.hpp"
#include "pipeline/jpeg_clean.hpp"
#include "pipeline/lowlight.hpp"
#include "pipeline/scratches.hpp"
#include "policy/gpu_gate.hpp"
#include "policy/gpu_identity.hpp"
#include "util/error.hpp"
#include "util/fs.hpp"
#include "util/log.hpp"
#include "util/sha256.hpp"
#include "util/size.hpp"

namespace enh {

// ---------------------------------------------------------------------------------------------
// Request
// ---------------------------------------------------------------------------------------------

JobRequest parse_job_request(const std::string& text) {
  auto j = nlohmann::json::parse(text, nullptr, false);
  if (j.is_discarded() || !j.is_object()) fail(ENH_E_INVALID, "request is not a JSON object");
  if (j.value("schema", 0) != 1) fail(ENH_E_INVALID, "unsupported request schema");
  JobRequest r;
  try {
    r.job_id = j.at("job_id").get<std::string>();
    r.input = j.at("input").get<std::string>();
    r.sr_model = j.value("sr_model", r.sr_model);
    r.scale = j.value("scale", r.scale);
    r.fast2 = j.value("fast2", r.fast2);
    r.pre_down = j.value("pre_down", r.pre_down);
    r.sharpen = j.value("sharpen", r.sharpen);
    r.tile = j.value("tile", r.tile);
    r.backend = j.value("backend", r.backend);
    r.preview_max = j.value("preview_max", r.preview_max);
    r.max_output_mp = j.value("max_output_mp", r.max_output_mp);
    r.face_model = j.value("face_model", r.face_model);
    r.det_model = j.value("det_model", r.det_model);
    r.face_strength = j.value("face_strength", r.face_strength);
    r.face_fidelity = j.value("face_fidelity", r.face_fidelity);
    r.face_color_match = j.value("face_color_match", r.face_color_match);
    r.background = j.value("background", r.background);
    r.jpeg_model = j.value("jpeg_model", r.jpeg_model);
    r.jpeg_qf = j.value("jpeg_qf", r.jpeg_qf);
    r.scratch_model = j.value("scratch_model", r.scratch_model);
    r.lowlight_model = j.value("lowlight_model", r.lowlight_model);
    r.inpaint_model = j.value("inpaint_model", r.inpaint_model);
    for (const auto& b : j.value("faces_off", nlohmann::json::array())) {
      const auto v = b.get<std::vector<float>>();
      if (v.size() != 4 ||
          !std::all_of(v.begin(), v.end(), [](float x) { return std::isfinite(x) && x >= 0; }))
        fail(ENH_E_INVALID, "bad faces_off box");
      r.faces_off.push_back({v[0], v[1], v[2], v[3]});
    }
    if (r.faces_off.size() > kMaxFaces) fail(ENH_E_INVALID, "too many faces_off");
    if (j.contains("crop") && !j["crop"].is_null()) {
      const auto c = j["crop"].get<std::vector<int>>();
      if (c.size() != 4 || c[0] < 0 || c[1] < 0 || c[2] < 16 || c[3] < 16 || c[2] > 2048 ||
          c[3] > 2048)
        fail(ENH_E_INVALID, "bad crop");
      r.crop_x = c[0];
      r.crop_y = c[1];
      r.crop_w = c[2];
      r.crop_h = c[3];
    }
  } catch (const nlohmann::json::exception& e) {
    fail(ENH_E_INVALID, std::string("bad request: ") + e.what());
  }
  static const std::regex id_re("[A-Za-z0-9_-]{1,64}");
  if (!std::regex_match(r.job_id, id_re)) fail(ENH_E_INVALID, "bad job_id");
  // Model ids name directories under models_dir; stages read their model.json by the id.
  static const std::regex model_re("[A-Za-z0-9][A-Za-z0-9._-]{0,63}");
  for (const std::string* id : {&r.sr_model, &r.face_model, &r.det_model, &r.jpeg_model,
                                &r.scratch_model, &r.lowlight_model, &r.inpaint_model}) {
    if (!id->empty() && (!std::regex_match(*id, model_re) || id->find("..") != std::string::npos))
      fail(ENH_E_INVALID, "bad model id");
  }
  if (r.input.empty()) fail(ENH_E_INVALID, "empty input");
  if (r.scale != 1 && r.scale != 2 && r.scale != 4 && r.scale != 8)
    fail(ENH_E_INVALID, "scale must be 1, 2, 4 or 8");
  if (r.fast2 && r.scale != 2) fail(ENH_E_INVALID, "fast2 requires scale 2");
  if (!(r.pre_down > 0 && r.pre_down <= 1)) fail(ENH_E_INVALID, "pre_down must be in (0, 1]");
  if (r.pre_down < 1 && r.scale == 8) fail(ENH_E_INVALID, "pre_down does not go with 8x");
  if (!(r.sharpen >= 0 && r.sharpen <= 1.5)) fail(ENH_E_INVALID, "sharpen must be 0..1.5");
  if (r.tile != 0 && (r.tile < 32 || r.tile > 1024)) fail(ENH_E_INVALID, "tile out of range");
  if (r.backend != "auto" && r.backend != "cpu" && r.backend != "vulkan")
    fail(ENH_E_INVALID, "bad backend");
  if (r.preview_max < 64 || r.preview_max > 8192) fail(ENH_E_INVALID, "bad preview_max");
  if (!(r.face_strength >= 0 && r.face_strength <= 1)) fail(ENH_E_INVALID, "bad face_strength");
  if (!(r.face_fidelity >= 0 && r.face_fidelity <= 1)) fail(ENH_E_INVALID, "bad face_fidelity");
  if (!r.face_model.empty() && r.det_model.empty()) fail(ENH_E_INVALID, "faces need det_model");
  if (r.background != "sr" && r.background != "lanczos") fail(ENH_E_INVALID, "bad background");
  if (!std::isfinite(r.jpeg_qf) || r.jpeg_qf > 1) fail(ENH_E_INVALID, "bad jpeg_qf");
  if (r.scratch_model.empty() != r.inpaint_model.empty())
    fail(ENH_E_INVALID, "scratch_model and inpaint_model go together");
  if (r.background == "lanczos" && r.face_model.empty()) {
    fail(ENH_E_INVALID, "a Lanczos background is the Faces region: it needs face_model");
  }
  return r;
}

nlohmann::json job_request_to_json(const JobRequest& r) {
  nlohmann::json j = {{"schema", 1},
                      {"job_id", r.job_id},
                      {"input", r.input},
                      {"sr_model", r.sr_model},
                      {"scale", r.scale},
                      {"fast2", r.fast2},
                      {"pre_down", r.pre_down},
                      {"sharpen", r.sharpen},
                      {"tile", r.tile},
                      {"backend", r.backend},
                      {"preview_max", r.preview_max},
                      {"max_output_mp", r.max_output_mp},
                      {"face_model", r.face_model},
                      {"det_model", r.det_model},
                      {"face_strength", r.face_strength},
                      {"face_fidelity", r.face_fidelity},
                      {"face_color_match", r.face_color_match},
                      {"background", r.background},
                      {"jpeg_model", r.jpeg_model},
                      {"jpeg_qf", r.jpeg_qf},
                      {"scratch_model", r.scratch_model},
                      {"lowlight_model", r.lowlight_model},
                      {"inpaint_model", r.inpaint_model},
                      {"faces_off", [&] {
                         nlohmann::json a = nlohmann::json::array();
                         for (const FaceBox& b : r.faces_off) a.push_back({b.x, b.y, b.w, b.h});
                         return a;
                       }()}};
  if (r.crop_w) j["crop"] = {r.crop_x, r.crop_y, r.crop_w, r.crop_h};
  return j;
}

namespace {

// ---------------------------------------------------------------------------------------------
// Plumbing
// ---------------------------------------------------------------------------------------------

template <class T>
class BoundedQueue {
 public:
  explicit BoundedQueue(size_t cap) : cap_(cap) {}
  bool push(T v) {
    std::unique_lock lk(mu_);
    cv_.wait(lk, [&] { return closed_ || q_.size() < cap_; });
    if (closed_) return false;
    q_.push_back(std::move(v));
    cv_.notify_all();
    return true;
  }
  std::optional<T> pop() {
    std::unique_lock lk(mu_);
    cv_.wait(lk, [&] { return closed_ || !q_.empty(); });
    if (q_.empty()) return std::nullopt;
    T v = std::move(q_.front());
    q_.pop_front();
    cv_.notify_all();
    return v;
  }
  // Producer done: consumers drain what is queued, then see end of stream.
  void close() {
    std::lock_guard lk(mu_);
    closed_ = true;
    cv_.notify_all();
  }
  // Stop: queued items are dropped (cancel latency <= 1 tile, S6).
  void abort() {
    std::lock_guard lk(mu_);
    closed_ = true;
    q_.clear();
    cv_.notify_all();
  }
  // Open again for another run of the stage (no producer or consumer is running).
  void reset() {
    std::lock_guard lk(mu_);
    closed_ = false;
    q_.clear();
  }

 private:
  std::mutex mu_;
  std::condition_variable cv_;
  std::deque<T> q_;
  size_t cap_;
  bool closed_ = false;
};

// enh_set_thermal levels (enh.h).
constexpr int kThermalFair = 2, kThermalSerious = 3, kThermalCritical = 4;
constexpr int kThermalPauseMs = 300;  // NFR-THERM-002: 200..500 ms between tiles at serious

struct Stopped {};  // unwinds the runner on cancel/pause outside the tile pipeline

struct TileIn {
  int band = 0, j = 0;
  ncnn::Mat in;
};
struct TileOut {
  int band = 0, j = 0;
  ncnn::Mat out;
};

const char* backend_kind_name(const BackendConfig& c) {
  if (c.kind == BackendKind::vulkan) return c.fp16 ? "vulkan_fp16" : "vulkan_fp32";
  return c.fp16 ? "cpu" : "cpu_fp32";
}

// Failures the fallback ladder answers (ADR-0016); anything else ends the job.
bool recoverable(enh_status st) {
  return st == ENH_E_BACKEND || st == ENH_E_NUMERIC || st == ENH_E_OOM;
}

const char* fallback_reason(enh_status st) {
  return st == ENH_E_NUMERIC ? "numeric" : st == ENH_E_OOM ? "oom" : "backend_error";
}

// Smallest sub-tile core of the "tile / 2" rung: below it the pad would dominate the work.
constexpr int kMinSubTile = 32;

// ADR-0025: rows per band of a finish pass (as the region Faces bands).
constexpr int kFinishRows = 256;

// ADR-0025: rows of a finished SR pass read back from its band store a band at a time, for
// the finish pass's resampler (whose window only moves forward); keeps the two bands before
// the current one.
class StoreRows {
 public:
  StoreRows(const BandStore& st, const Geometry& g) : st_(st), g_(g) {}
  const uint8_t* row(int y) {
    while (b_ > 0 && y < g_.band_out_y0(b_)) --b_;
    while (b_ + 1 < g_.bands() && y >= g_.band_out_y0(b_ + 1)) ++b_;
    auto it = cache_.find(b_);
    if (it == cache_.end()) {
      it = cache_.emplace(b_, std::vector<uint8_t>{}).first;
      st_.read_band(b_, it->second, sz(g_.band_out_rows(b_)) * sz(g_.out_w) * 3);
      while (cache_.begin()->first < b_ - 2) cache_.erase(cache_.begin());
    }
    return it->second.data() + sz(y - g_.band_out_y0(b_)) * sz(g_.out_w) * 3;
  }

 private:
  const BandStore& st_;
  const Geometry& g_;
  int b_ = 0;
  std::map<int, std::vector<uint8_t>> cache_;
};

// Runs one tile as n x n sub-tiles of its core (n = 2^split), each with the pad taken from the
// tile's own padded input. With the model's receptive field within the pad the output equals
// one run (S2), at about 1/n^2 of the activation memory (ADR-0016 "tile / 2").
void run_tile(InferenceBackend& be, const ncnn::Mat& in, ncnn::Mat& out, int pad, int scale,
              int split) {
  if (split == 0) return be.run(in, out);
  const int n = 1 << split, cw = in.w - 2 * pad, ch = in.h - 2 * pad;
  out.create(scale * in.w, scale * in.h, 3);
  if (out.empty()) fail(ENH_E_OOM, "tile output");
  out.fill(0.f);
  for (int sy = 0; sy < n; ++sy) {
    const int y0 = ch * sy / n, y1 = ch * (sy + 1) / n;
    for (int sx = 0; sx < n; ++sx) {
      const int x0 = cw * sx / n, x1 = cw * (sx + 1) / n;
      const int w = x1 - x0 + 2 * pad, h = y1 - y0 + 2 * pad;
      ncnn::Mat sub(w, h, 3);
      if (sub.empty()) fail(ENH_E_OOM, "sub-tile input");
      for (int c = 0; c < 3; ++c) {
        for (int r = 0; r < h; ++r) {
          std::memcpy(sub.channel(c).row(r), in.channel(c).row(y0 + r) + x0, sizeof(float) * sz(w));
        }
      }
      ncnn::Mat so;
      be.run(sub, so);
      if (so.w != scale * w || so.h != scale * h || so.c != 3) {
        fail(ENH_E_MODEL, "unexpected model output shape");
      }
      for (int c = 0; c < 3; ++c) {
        for (int r = scale * pad; r < scale * (h - pad); ++r) {
          std::memcpy(out.channel(c).row(scale * y0 + r) + sz(scale) * sz(x0 + pad),
                      so.channel(c).row(r) + sz(scale) * sz(pad),
                      sizeof(float) * sz(scale) * sz(x1 - x0));
        }
      }
    }
  }
}

}  // namespace
}  // namespace enh

using namespace enh;

struct enh_job {
  enh_session* s = nullptr;
  JobRequest req;
  std::string dir;
  bool resume = false;
  EventSink sink;

  std::atomic<bool> started{false}, cancel{false}, pause{false}, failed{false};
  std::atomic<int32_t> status{-1};

  std::mutex nu_mu;
  std::condition_variable nu_cv;
  bool answered = false;
  nlohmann::json answer;

  std::mutex err_mu;
  enh_status err_status = ENH_OK;
  std::string err_msg;

  BoundedQueue<TileIn> q1{2};
  BoundedQueue<TileOut> q2{2};
  std::thread runner;

  bool stop() const { return cancel.load() || pause.load() || failed.load(); }

  void request_stop() {
    q1.abort();
    q2.abort();
    std::lock_guard lk(nu_mu);
    nu_cv.notify_all();
  }

  void record_error(enh_status st, const std::string& msg) {
    {
      std::lock_guard lk(err_mu);
      if (err_status == ENH_OK) {
        err_status = st;
        err_msg = msg;
      }
    }
    failed = true;
    request_stop();
  }

  nlohmann::json wait_answer(const nlohmann::json& question) {
    {
      std::lock_guard lk(nu_mu);
      answered = false;
    }
    sink.emit(ENH_EV_NEEDS_USER, kStageDecode, 0, 0, question);
    std::unique_lock lk(nu_mu);
    nu_cv.wait(lk, [&] { return answered || stop(); });
    if (stop()) throw Stopped{};
    answered = false;
    return answer;
  }

  // NFR-THERM-002, before each tile on the inference thread. serious: half the CPU threads
  // and a pause between tiles; critical: wait until fair or lower. False: the job was stopped
  // while waiting.
  bool thermal_gate(InferenceBackend& be, int64_t done, int64_t total) {
    int level = s->thermal.load();
    if (level >= kThermalCritical) {
      sink.emit(ENH_EV_WARNING, kStageUpscale, done, total, {{"code", "thermal_wait"}});
      while (s->thermal.load() > kThermalFair) {
        if (stop()) return false;
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
      }
      sink.emit(ENH_EV_WARNING, kStageUpscale, done, total, {{"code", "thermal_resumed"}});
      level = s->thermal.load();
    }
    const bool hot = level >= kThermalSerious;
    if (hot != throttled) {
      throttled = hot;
      const int n = hot ? std::max(1, (be.threads() + 1) / 2) : 0;
      be.set_threads(n);
      if (hot)
        sink.emit(ENH_EV_WARNING, kStageUpscale, done, total, {{"code", "thermal_throttle"}});
    }
    if (hot) {
      for (int i = 0; i < kThermalPauseMs / 50 && !stop(); ++i)
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
    return !stop();
  }

  bool throttled = false;  // inference thread only

  // Fallback ladder state (ADR-0016), kept across a retry at a smaller scale: tiles run as
  // 2^split x 2^split sub-tiles; the memory warnings already answered (from enh_job_create on).
  int split = 0;
  uint32_t warnings_seen = 0;
  bool sr_started = false;  // past decode and faces: an OOM now can be answered by a downscale

  // "tile / 2" (ADR-0016): the next tiles run as sub-tiles of half the size. False when they
  // are already the smallest.
  bool smaller_tile(const Geometry& g, const char* reason, int64_t done, int64_t total,
                    std::vector<std::string>& fallbacks) {
    if ((std::min(g.tw, g.th) >> (split + 1)) < kMinSubTile) return false;
    const std::string from = std::to_string(g.tw >> split), to = std::to_string(g.tw >> ++split);
    ENH_LOGW("tile %s -> %s (%s)", from.c_str(), to.c_str(), reason);
    sink.emit(ENH_EV_FALLBACK, kStageUpscale, done, total,
              {{"kind", "tile"}, {"from", from}, {"to", to}, {"reason", reason}});
    fallbacks.push_back("tile:" + from + "->" + to);
    return true;
  }

  // NFR-MEM-004: each memory warning from the platform makes the next tile half the size. The
  // warnings, not the level: iOS only warns, and Android never says the pressure is over.
  void memory_gate(const Geometry& g, int64_t done, int64_t total,
                   std::vector<std::string>& fallbacks) {
    const uint32_t w = s->memory_warnings.load();
    if (w == warnings_seen) return;
    warnings_seen = w;
    smaller_tile(g, "memory_pressure", done, total, fallbacks);
  }

  // FR-ENH-014, the rung before the error: out of memory with the smallest tiles on every
  // backend. The user may pick a smaller output or region Faces (06 §3.5); the job then runs
  // again from decode. Never without an answer: the batch queue does not answer this one.
  bool retry_smaller();

  // DetectFaces + RestoreFaces (ADR-0012, ADR-0022): YuNet on CPU (tiny), the face model on
  // the backend ladder; each model is freed before the next stage. Faces smaller than
  // kMinFacePx are left alone; a face larger than 512 px in the input gets half the strength
  // (FR-FACE-009).
  std::vector<RestoredFace> restore_faces(const JobRequest& req, const Rgb8& img);
  Rgb8 clean_jpeg(const JobRequest& req, Rgb8 img, int jpeg_quality);
  Rgb8 remove_scratches(const JobRequest& req, Rgb8 img);
  Rgb8 brighten(const JobRequest& req, Rgb8 img);
  // Runs [f](backend) with [id] loaded on each rung of its backend ladder (and CPU fp32 last)
  // until one succeeds; each failed rung is a FALLBACK event of [stage], the last one of kind
  // [kind] ("skipped"). False when every rung failed.
  template <class F>
  bool on_ladder(const JobRequest& req, const std::string& id, int stage, const char* kind, F&& f);

  void run();
  void run_impl(nlohmann::json& result);
};

namespace {

// Backend ladder (ADR-0016): Vulkan fp16 -> Vulkan fp32 -> CPU, minus what the GPU policy
// forbids for this device+driver+model (blocklist rule or crash-sentinel quarantine, S3).
struct Ladder {
  std::vector<BackendConfig> rungs;
  GpuIdentity gpu;
  std::string skipped_reason;  // non-empty: Vulkan rungs removed by policy
};

Ladder backend_ladder(enh_session& s, const JobRequest& r, const std::string& model_id) {
  Ladder l;
  bool want_gpu = r.backend != "cpu" && s.backend_pref != ENH_BACKEND_NCNN_CPU;
  bool only_gpu = r.backend == "vulkan" || s.backend_pref == ENH_BACKEND_NCNN_VULKAN;
  const int dev = want_gpu && s.gpu_allowed.load() ? vulkan_default_device() : -1;
  if (dev >= 0) {
    l.gpu = gpu_identity(dev);
    MatchResult m = s.blocklist.match(l.gpu, model_id);
    SentinelRecord rec{l.gpu, model_id, "vulkan", 0};
    if (m.action == Action::Cpu || m.action == Action::Disable) {
      l.skipped_reason = m.matched.empty() ? "blocklist" : "blocklist:" + m.matched.front()->id;
    } else if (s.sentinel && s.sentinel->quarantined(rec)) {
      l.skipped_reason = "crash_quarantine";
    } else {
      if (m.action != Action::GpuFp32)
        l.rungs.push_back({BackendKind::vulkan, dev, true, s.cpu_threads});
      l.rungs.push_back({BackendKind::vulkan, dev, false, s.cpu_threads});
    }
  }
  if (!only_gpu || l.rungs.empty()) l.rungs.push_back({BackendKind::cpu, 0, true, s.cpu_threads});
  return l;
}

// Crash sentinel around the Vulkan stage (ADR-0016): armed before the first GPU tile, disarmed
// when the stage ends or falls back. A native crash in between leaves it on disk for the next
// session_create() to turn into a quarantine or a local blocklist rule.
class SentinelGuard {
 public:
  SentinelGuard(enh_session& s, const GpuIdentity& gpu, const std::string& model, int tile)
      : s_(s), rec_{gpu, model, "vulkan", tile} {}
  void arm() {
    if (s_.sentinel && !armed_) {
      s_.sentinel->arm(rec_);
      armed_ = true;
    }
  }
  void disarm() {
    if (armed_) {
      s_.sentinel->disarm(rec_);
      armed_ = false;
    }
  }
  ~SentinelGuard() { disarm(); }
  SentinelGuard(const SentinelGuard&) = delete;
  SentinelGuard& operator=(const SentinelGuard&) = delete;
  SentinelGuard(SentinelGuard&&) = delete;
  SentinelGuard& operator=(SentinelGuard&&) = delete;
  std::string key() const { return rec_.key(); }

 private:
  enh_session& s_;
  SentinelRecord rec_;
  bool armed_ = false;
};

int auto_tile(const enh_session& s, const BackendConfig& first) {
  // S2/S3: T0 (CPU, 600 MB) -> 128; T1/T2 -> 256; never 512 on Vulkan (silent corruption).
  if (first.kind == BackendKind::vulkan) return 256;
  return s.tier_level.load() >= 1 ? 256 : 128;
}

// [stage]: "" for the pass that makes the result, "1" for the first pass of 8x.
std::string recipe_hash(const std::string& input_sha, const ModelInfo& m, const Geometry& g,
                        const JobRequest& r, const std::string& stage) {
  Sha256 h;
  std::string model_sha = Sha256::of_file(m.param_path) + Sha256::of_file(m.bin_path);
  std::string s = "v1;in=" + input_sha + ";model=" + model_sha +
                  ";scale=" + std::to_string(r.scale) + ";fast2=" + std::to_string(r.fast2) +
                  ";tile=" + std::to_string(g.tw) + "x" + std::to_string(g.th) +
                  ";pad=" + std::to_string(g.pad) + ";down=" + std::to_string(g.down);
  if (r.crop_w) {
    s += ";crop=" + std::to_string(r.crop_x) + "," + std::to_string(r.crop_y) + "," +
         std::to_string(r.crop_w) + "," + std::to_string(r.crop_h);
  }
  if (!r.jpeg_model.empty()) s += ";jpeg=" + r.jpeg_model + "," + std::to_string(r.jpeg_qf);
  if (!r.scratch_model.empty()) s += ";scratches=" + r.scratch_model + "," + r.inpaint_model;
  if (!r.lowlight_model.empty()) s += ";lowlight=" + r.lowlight_model;
  // ADR-0025: only when on, so the bands of an older job still match on resume.
  if (r.pre_down < 1) s += ";pre_down=" + std::to_string(r.pre_down);
  if (r.sharpen > 0) s += ";sharpen=" + std::to_string(r.sharpen);
  if (!stage.empty()) s += ";stage=" + stage;
  return Sha256::of_string(s);
}

}  // namespace

template <class F>
bool enh_job::on_ladder(const JobRequest& rq, const std::string& id, int stage, const char* kind,
                        F&& f) {
  const ModelInfo m = resolve_model(s->models_dir, id);
  Ladder lad = backend_ladder(*s, rq, id);
  if (lad.rungs.back().kind == BackendKind::cpu)
    lad.rungs.push_back({BackendKind::cpu, 0, false, s->cpu_threads});
  for (size_t rung = 0; rung < lad.rungs.size(); ++rung) {
    enh_status st = ENH_OK;
    try {
      auto be = make_ncnn_backend(lad.rungs[rung]);
      be->load(m);
      std::forward<F>(f)(*be);
      return true;
    } catch (const Error& e) {
      if (e.status() == ENH_E_CANCELLED && stop()) throw Stopped{};
      if (e.status() == ENH_E_MODEL || !recoverable(e.status())) throw;
      st = e.status();
    } catch (const std::bad_alloc&) {
      st = ENH_E_OOM;
    }
    const bool last = rung + 1 >= lad.rungs.size();
    nlohmann::json p = {{"kind", last ? kind : "backend"},
                        {"from", backend_kind_name(lad.rungs[rung])},
                        {"reason", fallback_reason(st)}};
    p["to"] = last ? "skipped" : backend_kind_name(lad.rungs[rung + 1]);
    sink.emit(ENH_EV_FALLBACK, stage, 0, 0, p);
  }
  return false;
}

// S9: FBCNN restore graph, 1x, before faces and SR. A model that fails on every backend leaves
// the image as it is, with a FALLBACK event of kind "jpeg" (ADR-0016), as for faces.
Rgb8 enh_job::clean_jpeg(const JobRequest& rq, Rgb8 img, int jpeg_quality) {
  const float qf = rq.jpeg_qf >= 0 ? float(rq.jpeg_qf) : jpeg_qf_of_quality(jpeg_quality);
  sink.emit(ENH_EV_STAGE, kStageJpeg, 0, 0, {{"stage", "jpeg_clean"}, {"qf", qf}});
  const int pad = resolve_model(s->models_dir, rq.jpeg_model).pad;
  // Tiles multiple of 8 (three stride-2 levels); 256 like SR on T1/T2 (S2/S3).
  constexpr int kTile = 256;
  Rgb8 out;
  if (!on_ladder(rq, rq.jpeg_model, kStageJpeg, "jpeg", [&](InferenceBackend& be) {
        out = jpeg_clean(be, img, qf, kTile, pad, [&](int done, int total) {
          sink.progress(kStageJpeg, done, total, -1, done == total);
          return !stop();
        });
      }))
    return img;
  return out;
}

// S9: HVI-CIDNet once on a downscale (pipeline/lowlight). Failing on every backend leaves the
// image as it is, with a FALLBACK event of kind "lowlight" (ADR-0016).
Rgb8 enh_job::brighten(const JobRequest& rq, Rgb8 img) {
  sink.emit(ENH_EV_STAGE, kStageLowLight, 0, 0, {{"stage", "low_light"}});
  const std::string meta = fs::join(fs::join(s->models_dir, rq.lowlight_model), "model.json");
  const auto j = nlohmann::json::parse(fs::read_text(meta), nullptr, false);
  if (j.is_discarded() || !j.contains("density_k") || !j["density_k"].is_number())
    fail(ENH_E_MODEL, "low-light pack without density_k");
  const float k = j["density_k"].get<float>();
  Rgb8 out;
  if (!on_ladder(rq, rq.lowlight_model, kStageLowLight, "lowlight",
                 [&](InferenceBackend& be) { out = enhance_low_light(be, img, k); }))
    return img;
  sink.progress(kStageLowLight, 1, 1, -1, true);
  return out;
}

// S9: the BOPBTL detector, then MI-GAN on the holes it found. Either failing on every backend
// leaves the image as it is, with a FALLBACK event of kind "scratches" (ADR-0016).
Rgb8 enh_job::remove_scratches(const JobRequest& rq, Rgb8 img) {
  sink.emit(ENH_EV_STAGE, kStageScratches, 0, 0, {{"stage", "scratches"}});
  Mask8 mask;
  // The detector's mask is nearest-upsampled from 256 px: grow it by about half a cell.
  const int grow = std::max(1, std::min(img.w, img.h) / kScratchShortSide / 2 + 1);
  if (!on_ladder(rq, rq.scratch_model, kStageScratches, "scratches", [&](InferenceBackend& be) {
        mask = detect_scratches(be, img, kScratchThreshold, grow);
      }))
    return img;
  const size_t holes = mask.count();
  ENH_LOGI("scratches: %.2f%% of the photo", 100.0 * double(holes) / double(mask.px.size()));
  if (!holes) {
    sink.progress(kStageScratches, 1, 1, -1, true);
    return img;
  }
  Rgb8 out;
  if (!on_ladder(rq, rq.inpaint_model, kStageScratches, "scratches", [&](InferenceBackend& be) {
        out = inpaint(be, img, mask, [&](int done, int total) {
          sink.progress(kStageScratches, done, total, -1, done == total);
          return !stop();
        });
      }))
    return img;
  return out;
}

std::vector<RestoredFace> enh_job::restore_faces(const JobRequest& rq, const Rgb8& img) {
  sink.emit(ENH_EV_STAGE, kStageFaces, 0, 0, {{"stage", "restore_faces"}});
  // ADR-0016: a face that fails on every backend is left as the SR model makes it, with a
  // FALLBACK event; so are all of them when detection itself fails.
  auto skip = [&](enh_status st, int64_t index) {
    nlohmann::json p = {{"kind", "face"}, {"to", "skipped"}, {"reason", fallback_reason(st)}};
    if (index >= 0) p["index"] = index;
    ENH_LOGW("face %lld skipped: %s", (long long)index, fallback_reason(st));
    sink.emit(ENH_EV_FALLBACK, kStageFaces, 0, 0, p);
  };
  std::vector<Face> found;
  try {
    auto det = make_ncnn_backend({BackendKind::cpu, 0, false, s->cpu_threads});
    det->load(resolve_model(s->models_dir, rq.det_model));
    found = find_faces(*det, img);
  } catch (const Error& e) {
    if (!recoverable(e.status())) throw;
    skip(e.status(), -1);
    return {};
  } catch (const std::bad_alloc&) {
    skip(ENH_E_OOM, -1);
    return {};
  }
  // FR-FACE-007: faces turned off stay as the SR model makes them.
  const size_t detected = found.size();
  found.erase(std::remove_if(found.begin(), found.end(),
                             [&](const Face& f) {
                               return std::any_of(
                                   rq.faces_off.begin(), rq.faces_off.end(),
                                   [&](const FaceBox& b) { return iou(f, b) >= kSameFaceIou; });
                             }),
              found.end());
  if (found.size() != detected) ENH_LOGI("faces: %zu turned off", detected - found.size());
  sink.emit(ENH_EV_WARNING, kStageFaces, 0, int64_t(found.size()),
            {{"code", "faces_found"}, {"count", found.size()}, {"off", detected - found.size()}});
  std::vector<RestoredFace> out;
  if (found.empty()) return out;

  const FaceModel fm = resolve_face_model(s->models_dir, rq.face_model);
  Ladder lad = backend_ladder(*s, rq, fm.id);
  // ADR-0016: the face model gets a CPU fp32 rung after CPU fp16.
  if (lad.rungs.back().kind == BackendKind::cpu)
    lad.rungs.push_back({BackendKind::cpu, 0, false, s->cpu_threads});
  size_t rung = 0;
  std::unique_ptr<FaceRestorer> be;
  auto load = [&] {
    for (;;) {
      try {
        be = std::make_unique<FaceRestorer>(fm, lad.rungs[rung]);
        return;
      } catch (const Error& e) {
        if (e.status() == ENH_E_MODEL || rung + 1 >= lad.rungs.size()) throw;
        ++rung;
      }
    }
  };
  try {
    load();
  } catch (const Error& e) {
    if (!recoverable(e.status())) throw;
    skip(e.status(), -1);
    return {};
  }
  // The next rung after a failure; false on the last one.
  // NOLINTNEXTLINE(clang-analyzer-deadcode.DeadStores): false positive, read in the loop below
  auto next_rung = [&](enh_status st) {
    if (rung + 1 >= lad.rungs.size()) return false;
    const std::string from = backend_kind_name(lad.rungs[rung]);
    ++rung;
    sink.emit(ENH_EV_FALLBACK, kStageFaces, 0, 0,
              {{"kind", "backend"},
               {"from", from},
               {"to", backend_kind_name(lad.rungs[rung])},
               {"reason", fallback_reason(st)}});
    be.reset();
    load();
    return true;
  };
  for (size_t i = 0; i < found.size(); ++i) {
    if (stop()) throw Stopped{};
    const Affine align = face_alignment(found[i]);
    const Rgb8 aligned = warp_affine(img, align, kFaceSide, kFaceSide);
    Rgb8 restored;
    for (;;) {
      enh_status st = ENH_OK;
      try {
        restored = be->restore(aligned, rq.face_fidelity);
        if (rq.face_color_match) {
          const double de = match_face_color(restored, aligned);
          ENH_LOGD("face %zu: colour shift dE %.1f", i, de);
        }
        break;
      } catch (const Error& e) {
        if (!recoverable(e.status())) throw;
        st = e.status();
      } catch (const std::bad_alloc&) {
        st = ENH_E_OOM;
      }
      if (!next_rung(st)) {
        skip(st, int64_t(i));
        restored = {};
        break;
      }
    }
    if (restored.w == 0) {
      sink.progress(kStageFaces, int64_t(i + 1), int64_t(found.size()), -1, true);
      continue;
    }
    // FR-FACE-009: a face whose 512 crop covers more than 512 input pixels (the model would
    // lose detail the photo has) gets half the strength.
    const double crop_side_in = kFaceSide / std::hypot(align.a, align.c);
    const float weight = crop_side_in > kFaceSide ? 0.5f : 1.f;
    out.push_back(prepare_paste(align, std::move(restored), rq.scale,
                                float(rq.face_strength) * weight, img.w * rq.scale,
                                img.h * rq.scale));
    sink.progress(kStageFaces, int64_t(i + 1), int64_t(found.size()), -1, true);
  }
  return out;
}

void enh_job::run() {
  nlohmann::json result;
  enh_status final_status = ENH_OK;
  std::string message;
  do {
    try {
      run_impl(result);
    } catch (const Stopped&) {
      // cancel, pause, or a recorded failure. continue runs retry_smaller(), which
      // retries an out-of-memory job and refuses the other two.
      continue;
    } catch (const Error& e) {
      record_error(e.status(), e.what());
    } catch (const std::bad_alloc&) {
      record_error(ENH_E_OOM, "out of memory");
    } catch (const std::exception& e) {
      record_error(ENH_E_INTERNAL, e.what());
    }
  } while (retry_smaller());
  if (failed) {
    std::lock_guard lk(err_mu);
    final_status = err_status;
    message = err_msg;
  } else if (cancel) {
    final_status = ENH_E_CANCELLED;
  } else if (pause) {
    final_status = ENH_E_PAUSED;
  }
  if (final_status == ENH_E_CANCELLED) fs::remove_tree(dir);  // nothing to resume: free disk
  status = final_status;
  if (final_status == ENH_OK) {
    sink.emit(ENH_EV_DONE, kStageFinalize, 0, 0, result);
  } else {
    if (final_status != ENH_E_CANCELLED && final_status != ENH_E_PAUSED) {
      ENH_LOGW("job %s failed: status %d: %s", req.job_id.c_str(), final_status, message.c_str());
    }
    nlohmann::json p = {{"status", final_status}};
    if (!message.empty()) p["message"] = message;
    if (final_status == ENH_E_PAUSED) p["job_dir"] = dir;
    sink.emit(ENH_EV_ERROR, kStageFinalize, 0, 0, p);
  }
}

bool enh_job::retry_smaller() {
  {
    std::lock_guard lk(err_mu);
    if (!failed || err_status != ENH_E_OOM || !sr_started || cancel || pause) return false;
  }
  nlohmann::json opts = nlohmann::json::array();
  if (req.background != "lanczos") {
    if (req.scale == 8) opts.push_back({{"scale", 4}, {"fast2", false}});
    if (req.scale == 4) opts.push_back({{"scale", 2}, {"fast2", false}});
    if (req.scale >= 2 && !req.fast2) opts.push_back({{"scale", 2}, {"fast2", true}});
    if (!req.face_model.empty())
      opts.push_back({{"scale", req.scale}, {"fast2", false}, {"background", "lanczos"}});
  }
  if (opts.empty()) return false;
  {
    std::lock_guard lk(err_mu);
    err_status = ENH_OK;
    err_msg.clear();
  }
  failed = false;
  q1.reset();
  q2.reset();
  nlohmann::json a;
  try {
    a = wait_answer(
        {{"code", "oom_downscale"}, {"scale", req.scale}, {"fast2", req.fast2}, {"options", opts}});
  } catch (const Stopped&) {
    return false;
  }
  if (std::find(opts.begin(), opts.end(), a) == opts.end()) {
    record_error(ENH_E_INVALID, "answer is not one of the options");
    return false;
  }
  req.scale = a["scale"].get<int>();
  req.fast2 = a["fast2"].get<bool>();
  if (a.contains("background")) req.background = a["background"].get<std::string>();
  fs::write_atomic(fs::join(dir, kRequestFile), dump_json(job_request_to_json(req)) + "\n");
  ENH_LOGI("job %s: out of memory, again at scale %d%s%s", req.job_id.c_str(), req.scale,
           req.fast2 ? " fast" : "", req.background == "lanczos" ? " faces only" : "");
  resume = false;
  sr_started = false;
  throttled = false;
  return true;
}

void enh_job::run_impl(nlohmann::json& result) {
  using namespace std::chrono;
  const auto t_start = steady_clock::now();

  // ---- one job at a time ----
  std::unique_lock run_lock(s->run_mu, std::defer_lock);
  if (!run_lock.try_lock()) {
    sink.emit(ENH_EV_STAGE, kStageQueued, 0, 0, {{"stage", "queued"}});
    while (!run_lock.try_lock_for(milliseconds(50))) {
      if (stop()) throw Stopped{};
    }
  }
  if (stop()) throw Stopped{};

  // ---- decode ----
  sink.emit(ENH_EV_STAGE, kStageDecode, 0, 0, {{"stage", "decode"}});
  ImageInfo info = probe_image(req.input);
  ModelInfo model = resolve_model(s->models_dir, req.sr_model);
  if (req.scale == 8 && model.scale != 4) fail(ENH_E_INVALID, "8x needs a x4 model");
  // ADR-0014: 8x only on an input of at most 1.5 MP; above, it is a smaller scale's turn.
  const double in_px = req.crop_w ? double(req.crop_w) * req.crop_h : double(info.w) * info.h;

  auto out_mp = [&](const JobRequest& r) {  // fast 2x: (w/2)*4 = 2w
    if (r.fast2) return std::floor(info.w / 2.0) * 4 * std::floor(info.h / 2.0) * 4 / 1e6;
    return double(info.w) * r.scale * double(info.h) * r.scale / 1e6;
  };
  auto too_large = [&](const JobRequest& r) {
    return out_mp(r) > req.max_output_mp || (r.scale == 8 && in_px > kMaxX8InputPx);
  };
  while (too_large(req)) {
    nlohmann::json opts = nlohmann::json::array();
    for (auto [sc, f2] :
         {std::pair{4, false}, std::pair{2, true}, std::pair{2, false}, std::pair{1, false}}) {
      JobRequest t = req;
      t.scale = sc;
      t.fast2 = f2;
      if ((sc < req.scale || (sc == req.scale && f2 && !req.fast2)) && !too_large(t))
        opts.push_back({{"scale", sc}, {"fast2", f2}});
    }
    if (opts.empty()) fail(ENH_E_LIMIT, "input too large for any scale");
    nlohmann::json a = wait_answer({{"code", "downscale_required"},
                                    {"output_mp", out_mp(req)},
                                    {"max_output_mp", req.max_output_mp},
                                    {"input_mp", in_px / 1e6},
                                    {"options", opts}});
    req.scale = a.value("scale", req.scale);
    req.fast2 = a.value("fast2", false) && req.scale == 2;
    fs::write_atomic(fs::join(dir, kRequestFile), dump_json(job_request_to_json(req)) + "\n");
  }

  std::string input_sha = Sha256::of_file(req.input);
  if (input_sha.empty()) fail(ENH_E_IO, "cannot read input");
  SourceMeta meta;
  Rgb8 img = decode_image(req.input, &info, &meta);
  img = apply_orientation(std::move(img), info.orientation);
  // Kept for enh_export (metaio, ADR-0018): the input may be gone by then.
  if (!meta.exif.empty())
    fs::write_atomic(fs::join(dir, kSourceExifFile), meta.exif.data(), meta.exif.size());
  if (!meta.icc.empty())
    fs::write_atomic(fs::join(dir, kSourceIccFile), meta.icc.data(), meta.icc.size());
  // FR-IMP-007: the SR model sees the image on white; the alpha is kept, oriented like the
  // pixels, and the PNG/WebP export scales it back on (JPEG has none).
  nlohmann::json alpha_json;
  if (!meta.alpha.empty() && meta.alpha.size() != sz(info.w) * sz(info.h)) {
    ENH_LOGW("alpha of %zu px for a %dx%d image: dropped", meta.alpha.size(), info.w, info.h);
    meta.alpha = {};
  }
  if (!meta.alpha.empty()) {
    Rgb8 a3;
    a3.w = int(info.w);
    a3.h = int(info.h);
    a3.px.resize(meta.alpha.size() * 3);
    for (size_t i = 0; i < meta.alpha.size(); ++i)
      a3.px[i * 3] = a3.px[i * 3 + 1] = a3.px[i * 3 + 2] = meta.alpha[i];
    meta.alpha = {};
    a3 = apply_orientation(std::move(a3), info.orientation);
    std::vector<uint8_t> a(sz(a3.w) * sz(a3.h));
    for (size_t i = 0; i < a.size(); ++i) a[i] = a3.px[i * 3];
    fs::write_atomic(fs::join(dir, kAlphaFile), a.data(), a.size());
    alpha_json = {{"file", kAlphaFile}, {"width", a3.w}, {"height", a3.h}};
    sink.emit(ENH_EV_WARNING, kStageDecode, 0, 0, {{"code", "alpha_kept"}});
  }
  if (info.animated)
    sink.emit(ENH_EV_WARNING, kStageDecode, 0, 0, {{"code", "animation_first_frame"}});
  // FR-ENH-015: a fragment preview runs on its part of the photo only (and of the alpha).
  if (req.crop_w) {
    // Compared without the sum: crop_x may be up to INT_MAX (only >= 0 is checked on parse).
    if (req.crop_x > img.w - req.crop_w || req.crop_y > img.h - req.crop_h)
      fail(ENH_E_INVALID, "crop outside the photo");
    img = crop(img, req.crop_x, req.crop_y, req.crop_w, req.crop_h);
    if (!alpha_json.is_null()) {
      const int aw = alpha_json["width"], ah = alpha_json["height"];
      auto a = fs::read_all(fs::join(dir, kAlphaFile));
      if (a.size() != sz(aw) * sz(ah)) fail(ENH_E_IO, "alpha file does not match");
      std::vector<uint8_t> c(sz(req.crop_w) * sz(req.crop_h));
      for (int y = 0; y < req.crop_h; ++y)
        std::memcpy(&c[index2d(0, y, req.crop_w)], &a[index2d(req.crop_x, req.crop_y + y, aw)],
                    sz(req.crop_w));
      fs::write_atomic(fs::join(dir, kAlphaFile), c.data(), c.size());
      alpha_json["width"] = req.crop_w;
      alpha_json["height"] = req.crop_h;
    }
  }
  const int src_w = img.w, src_h = img.h;
  if (stop()) throw Stopped{};

  // ---- JPEG cleanup (S9): the whole (cropped) photo, before faces see it ----
  if (!req.jpeg_model.empty()) {
    img = clean_jpeg(req, std::move(img), info.jpeg_quality);
    if (stop()) throw Stopped{};
  }
  // ---- low light (S9): before the scratch detector, which sees a dark photo badly ----
  if (!req.lowlight_model.empty()) {
    img = brighten(req, std::move(img));
    if (stop()) throw Stopped{};
  }
  // ---- scratch removal (S9): after the cleanup, so the detector sees no blocking ----
  if (!req.scratch_model.empty()) {
    img = remove_scratches(req, std::move(img));
    if (stop()) throw Stopped{};
  }

  // ---- faces (ADR-0012): before the SR model is loaded, so one heavy model is in memory ----
  std::vector<RestoredFace> faces;
  if (!req.face_model.empty() && req.face_strength > 0) {
    faces = restore_faces(req, img);
    if (stop()) throw Stopped{};
  }

  sr_started = true;

  // ---- region Faces (FR-FACE-006): Lanczos background, no SR model ----
  if (req.background == "lanczos") {
    const int ow = src_w * req.scale, oh = src_h * req.scale;
    constexpr int kRows = 256;
    const int bands = (oh + kRows - 1) / kRows;
    BandStore store(dir);
    store.reset();
    Checkpoint ck;
    ck.bands_total = bands;
    ck.out_w = ow;
    ck.out_h = oh;
    ck.recipe_hash = "lanczos:" + input_sha;
    if (req.crop_w) {
      ck.recipe_hash += ";crop=" + std::to_string(req.crop_x) + "," + std::to_string(req.crop_y) +
                        "," + std::to_string(req.crop_w) + "," + std::to_string(req.crop_h);
    }
    PreviewAccumulator preview;
    preview.init(ow, oh, req.preview_max);
    LanczosResampler up(img, ow, oh);
    sink.emit(ENH_EV_STAGE, kStageUpscale, 0, bands, {{"stage", "upscale"}});
    std::vector<uint8_t> band;
    nlohmann::json band_rows = nlohmann::json::array();
    for (int b = 0; b < bands; ++b) {
      if (stop()) throw Stopped{};
      const int y0 = b * kRows, rows = std::min(kRows, oh - y0);
      band.resize(sz(rows) * sz(ow) * 3);
      up.rows(y0, rows, band.data());
      paste_faces(band.data(), ow, y0, rows, faces);
      preview.add_rows(band.data(), y0, rows);
      store.commit(b, band.data(), band.size(), ck);
      band_rows.push_back(rows);
      sink.progress(kStageUpscale, b + 1, bands, -1, b + 1 == bands);
    }
    sink.emit(ENH_EV_STAGE, kStageFinalize, 0, 0, {{"stage", "finalize"}});
    Rgb8 pv = preview.finish();
    jpeg_encode(fs::join(dir, kPreviewFile), pv, 90);
    result = {
        {"schema", 1},
        {"job_id", req.job_id},
        {"job_dir", dir},
        {"width", ow},
        {"height", oh},
        {"band_rows", band_rows},
        {"preview", {{"file", kPreviewFile}, {"width", pv.w}, {"height", pv.h}}},
        {"input",
         {{"width", src_w},
          {"height", src_h},
          {"orientation", info.orientation},
          {"format", info.format}}},
        {"scale", req.scale},
        {"fast2", false},
        {"model", req.face_model},
        {"backend", "lanczos"},
        {"fallbacks", nlohmann::json::array()},
        {"tile", 0},
        {"pad", 0},
        {"resumed_from_band", 0},
        {"recipe_hash", ck.recipe_hash},
        {"timings_ms",
         {{"sr", 0},
          {"total", int64_t(duration<double>(steady_clock::now() - t_start).count() * 1000)}}}};
    if (!alpha_json.is_null()) result["alpha"] = alpha_json;
    fs::write_atomic(fs::join(dir, kResultFile), result.dump(2) + "\n");
    return;
  }
  // ADR-0025: the result keeps the size it has without pre_down (fast 2x: (w/2) * 4); SR sees
  // the input at its effective resolution and a finish pass resamples, sharpens and pastes.
  const int final_w = req.fast2 ? (src_w / 2) * 4 : src_w * req.scale;
  const int final_h = req.fast2 ? (src_h / 2) * 4 : src_h * req.scale;
  const bool pre = req.pre_down < (req.fast2 ? 0.5 : 1.0);
  if (pre) {
    img = resize_area(img, std::max(1, int(std::lround(src_w * req.pre_down))),
                      std::max(1, int(std::lround(src_h * req.pre_down))));
  } else if (req.fast2) {
    img = area_down(img, 2);
  }
  const bool finish = pre || req.sharpen > 0;

  // ---- geometry, backend, store ----
  Ladder lad = backend_ladder(*s, req, model.id);
  std::vector<BackendConfig>& ladder = lad.rungs;
  if (!lad.skipped_reason.empty()) {
    sink.emit(
        ENH_EV_WARNING, kStageDecode, 0, 0,
        {{"code", "gpu_skipped"}, {"reason", lad.skipped_reason}, {"device", lad.gpu.device_name}});
  }
  size_t rung = 0;
  std::unique_ptr<InferenceBackend> be;
  for (;;) {  // first loadable rung
    try {
      be = make_ncnn_backend(ladder[rung]);
      be->load(model);
      break;
    } catch (const Error& e) {
      if (e.status() == ENH_E_MODEL || rung + 1 >= ladder.size()) throw;
      ENH_LOGW("backend %s unavailable: %s", backend_kind_name(ladder[rung]), e.what());
      ++rung;
    }
  }
  const int tile = req.tile > 0 ? req.tile : auto_tile(*s, ladder[rung]);
  // 8x (FR-ENH-003, ADR-0014): x4 into x8/ (a band store of its own, so a resume skips it),
  // then x4 of that with an area /2. Other scales: one pass.
  const bool x8 = req.scale == 8;
  Geometry g1;
  if (x8) g1 = Geometry::make(img.w, img.h, tile, model.pad, model.scale, 1);
  int down = x8 ? 2 : req.fast2 ? 1 : model.scale / req.scale;
  if (pre) {  // the largest area /down whose SR output is still at least the result's size
    down = 1;
    for (int d : {4, 2}) {
      if (model.scale % d == 0 && model.scale / d * img.w >= final_w &&
          model.scale / d * img.h >= final_h) {
        down = d;
        break;
      }
    }
  }
  if (down < 1) fail(ENH_E_INVALID, "scale exceeds model scale");
  Geometry g = x8 ? Geometry::make(g1.out_w, g1.out_h, tile, model.pad, model.scale, down)
                  : Geometry::make(img.w, img.h, tile, model.pad, model.scale, down);

  // ---- GPU correctness gate (ADR-0017, S3), for each network input size the job runs ----
  SentinelGuard sentinel(*s, lad.gpu, model.id, g.tw);
  auto gate = [&](const Geometry& gg) {
    std::unique_ptr<GateCache> cache;
    if (!s->cache_dir.empty())
      cache = std::make_unique<GateCache>(fs::join(s->cache_dir, "gpu/gate.json"));
    const ncnn::Mat in = gate_input(gg.net_in_w(), gg.net_in_h());
    ncnn::Mat ref;
    while (ladder[rung].kind == BackendKind::vulkan) {
      const std::string key = sentinel.key() + "|" + backend_kind_name(ladder[rung]) + "|" +
                              std::to_string(gg.net_in_w()) + "x" + std::to_string(gg.net_in_h());
      std::string verdict = cache ? cache->get(key) : "";
      GateMetrics m;
      if (verdict.empty()) {
        if (ref.empty()) {
          auto cpu = make_ncnn_backend({BackendKind::cpu, 0, true, s->cpu_threads});
          cpu->load(model);
          cpu->run(in, ref);
        }
        sentinel.arm();  // a driver crash inside the gate counts like one in the job
        try {
          ncnn::Mat out;
          be->run(in, out);
          m = compare_tiles(out, ref);
        } catch (const Error& e) {
          if (e.status() != ENH_E_BACKEND && e.status() != ENH_E_NUMERIC) throw;
          m = GateMetrics{};
        }
        sentinel.disarm();
        verdict = m.pass ? "ok" : "bad";
        if (cache) cache->put(key, verdict, m);
        ENH_LOGI("gpu gate %s: %s (psnr %.1f dB, bad %.4f)", backend_kind_name(ladder[rung]),
                 verdict.c_str(), m.psnr, m.bad_frac);
      }
      if (verdict == "ok") break;
      sink.emit(ENH_EV_WARNING, kStageDecode, 0, 0,
                {{"code", "gpu_check_failed"},
                 {"backend", backend_kind_name(ladder[rung])},
                 {"psnr", m.psnr},
                 {"device", lad.gpu.device_name}});
      ++rung;
      be.reset();
      be = make_ncnn_backend(ladder[rung]);
      be->load(model);
    }
    if (stop()) throw Stopped{};
  };
  gate(g);
  if (x8 && (g1.net_in_w() != g.net_in_w() || g1.net_in_h() != g.net_in_h())) gate(g1);

  // The band store of a pass: the band to start from (its checkpoint matches and its bands are
  // whole), else emptied after a check for [need] bytes free (NFR-SIZE-004).
  auto open_bands = [&](BandStore& store, int bands, const std::function<int(int)>& band_rows,
                        int out_w, const Checkpoint& ck, bool may_resume, double need) {
    Checkpoint old;
    if (may_resume && store.load_checkpoint(old) && old.recipe_hash == ck.recipe_hash &&
        old.bands_total == ck.bands_total) {
      bool ok = true;
      for (int b = 0; b <= old.band_idx && ok; ++b)
        ok = fs::file_size(store.band_path(b)) == int64_t(band_rows(b)) * out_w * 3;
      if (ok) {
        store.discard_after(old.band_idx, bands);
        return old.band_idx + 1;
      }
    }
    if (may_resume) sink.emit(ENH_EV_WARNING, kStageDecode, 0, 0, {{"code", "resume_restarted"}});
    store.reset();
    const int64_t avail = fs::free_bytes(dir);
    if (avail >= 0 && double(avail) < need) {
      fail(ENH_E_DISK_FULL, "need " + std::to_string(int64_t(need / 1e6)) + " MB free");
    }
    return 0;
  };
  auto open_store = [&](BandStore& store, const Geometry& gg, const Checkpoint& ck, bool may_resume,
                        double need) {
    return open_bands(
        store, gg.bands(), [&gg](int b) { return gg.band_out_rows(b); }, gg.out_w, ck, may_resume,
        need);
  };
  auto checkpoint = [&](const Geometry& gg, const std::string& stage) {
    Checkpoint ck;
    ck.bands_total = gg.bands();
    ck.out_w = gg.out_w;
    ck.out_h = gg.out_h;
    ck.recipe_hash = recipe_hash(input_sha, model, gg, req, stage);
    return ck;
  };
  auto bytes = [](const Geometry& gg) { return double(gg.out_w) * gg.out_h * 3 * 1.2; };

  BandStore store1(fs::join(dir, kX8Dir));
  Checkpoint ck1;
  int start1 = 0;
  if (x8) {
    ck1 = checkpoint(g1, "1");
    start1 = open_store(store1, g1, ck1, resume, bytes(g1) + bytes(g));
  }
  const bool pass1_done = !x8 || start1 == g1.bands();
  // With a finish pass the SR pass has a store of its own (ADR-0025).
  BandStore store(finish ? fs::join(dir, kPreDir) : dir);
  Checkpoint ck = checkpoint(g, finish ? "pre" : "");
  const double finish_bytes = finish ? double(final_w) * final_h * 3 * 1.2 : 0;
  const int start_band = open_store(store, g, ck, resume && pass1_done, bytes(g) + finish_bytes);
  const bool sr_done = pass1_done && start_band == g.bands();  // only the finish is left

  PreviewAccumulator preview;
  preview.init(finish ? final_w : g.out_w, finish ? final_h : g.out_h, req.preview_max);
  if (start_band > 0 && !finish) {
    std::vector<uint8_t> buf;
    for (int b = 0; b < start_band; ++b) {
      store.read_band(b, buf, sz(g.band_out_rows(b)) * sz(g.out_w) * 3);
      preview.add_rows(buf.data(), g.band_out_y0(b), g.band_out_rows(b));
    }
  }

  // ---- SR banded ----
  if (ladder[rung].kind == BackendKind::vulkan) sentinel.arm();
  const int finish_bands = finish ? (final_h + kFinishRows - 1) / kFinishRows : 0;
  // The finish pass counts one unit per band of the result.
  const int64_t total_tiles = (x8 ? g1.tiles() : 0) + g.tiles() + finish_bands;
  std::atomic<int64_t> done_tiles{x8 && !pass1_done ? int64_t(start1) * g1.tiles_per_band()
                                                    : (x8 ? g1.tiles() : 0) +
                                                          int64_t(start_band) * g.tiles_per_band()};
  sink.emit(ENH_EV_STAGE, kStageUpscale, 0, total_tiles, {{"stage", "upscale"}});
  const int64_t resumed_tiles = done_tiles.load();
  sink.progress(kStageUpscale, done_tiles, total_tiles, -1, true);
  const auto t_sr = steady_clock::now();
  std::vector<std::string> fallbacks;

  auto guarded = [this](auto&& body) {
    return [this, body]() mutable {
      try {
        body();
      } catch (const Error& e) {
        record_error(e.status(), e.what());
      } catch (const std::bad_alloc&) {
        record_error(ENH_E_OOM, "out of memory");
      } catch (const std::exception& e) {
        record_error(ENH_E_INTERNAL, e.what());
      }
    };
  };

  // One pass over [src] from band [first] into [st]; the last pass pastes the faces and feeds
  // the preview.
  auto sr_pass = [&](const Rgb8& src, const Geometry& geo, BandStore& st, const Checkpoint& ckp,
                     int first, bool is_last) {
    q1.reset();
    q2.reset();
    const int tpb = geo.tiles_per_band();
    std::thread prep(guarded([&] {
      const int P = geo.pad, itw = geo.net_in_w(), ith = geo.net_in_h();
      std::vector<int> colidx(sz(itw));
      for (int b = first; b < geo.bands() && !stop(); ++b) {
        for (int j = 0; j < tpb && !stop(); ++j) {
          TileIn t{b, j, ncnn::Mat(itw, ith, 3)};
          const int x0 = geo.xs[sz(j)];
          for (int xx = 0; xx < itw; ++xx) colidx[sz(xx)] = reflect101(x0 - P + xx, geo.in_w);
          for (int yy = 0; yy < ith; ++yy) {
            const uint8_t* row = src.row(reflect101(geo.ys[sz(b)] - P + yy, geo.in_h));
            float* r = t.in.channel(0).row(yy);
            float* gg = t.in.channel(1).row(yy);
            float* bl = t.in.channel(2).row(yy);
            for (int xx = 0; xx < itw; ++xx) {
              const uint8_t* p = row + sz(colidx[sz(xx)]) * 3;
              r[xx] = float(p[0]) * (1.f / 255.f);
              gg[xx] = float(p[1]) * (1.f / 255.f);
              bl[xx] = float(p[2]) * (1.f / 255.f);
            }
          }
          if (!q1.push(std::move(t))) return;
        }
      }
      q1.close();
    }));
    std::thread infer(guarded([&] {
      while (auto t = q1.pop()) {
        if (stop()) break;
        if (ladder[rung].kind == BackendKind::vulkan && !s->gpu_allowed.load()) {
          pause = true;  // iOS background: GPU work is not allowed (ADR-0019)
          request_stop();
          break;
        }
        if (!thermal_gate(*be, done_tiles.load(), total_tiles)) break;
        memory_gate(geo, done_tiles.load(), total_tiles, fallbacks);
        TileOut o{t->band, t->j, {}};
        for (;;) {
          try {
            run_tile(*be, t->in, o.out, geo.pad, geo.model_scale, split);
            break;
          } catch (const Error& e) {
            // ADR-0016: out of memory -> a smaller tile first, then the next backend.
            if (e.status() == ENH_E_OOM &&
                smaller_tile(geo, "oom", done_tiles.load(), total_tiles, fallbacks))
              continue;
            if (!recoverable(e.status()) || rung + 1 >= ladder.size()) throw;
            std::string from = backend_kind_name(ladder[rung]);
            ++rung;
            std::string to = backend_kind_name(ladder[rung]);
            sink.emit(ENH_EV_FALLBACK, kStageUpscale, done_tiles, total_tiles,
                      {{"kind", "backend"},
                       {"from", from},
                       {"to", to},
                       {"reason", fallback_reason(e.status())}});
            std::string edge = from;
            edge += "->";
            edge += to;
            fallbacks.push_back(std::move(edge));
            if (ladder[rung].kind != BackendKind::vulkan) sentinel.disarm();  // GPU stage over
            be.reset();
            be = make_ncnn_backend(ladder[rung]);
            be->load(model);
            throttled = false;  // a new backend runs unthrottled: the next gate applies it again
          }
        }
        const int S = geo.model_scale;
        if (o.out.w != S * geo.net_in_w() || o.out.h != S * geo.net_in_h() || o.out.c != 3) {
          fail(ENH_E_MODEL, "unexpected model output shape");
        }
        if (!q2.push(std::move(o))) return;
      }
      q2.close();
    }));

    std::thread post(guarded([&] {
      const int S = geo.model_scale, P = geo.pad;
      std::vector<uint8_t> band, down_buf;
      auto q = [](float v) -> uint8_t {
        v = v < 0.f ? 0.f : (v > 1.f ? 1.f : v);
        return round_u8(v * 255.f);
      };
      while (auto t = q2.pop()) {
        if (stop()) break;
        const int b = t->band, j = t->j;
        const int rows = geo.band_sr_rows(b);
        if (j == 0) band.assign(sz(rows) * sz(geo.sr_w) * 3, 0);
        const int Y0 = S * geo.band_in_y0(b);
        const int tyoff = S * (geo.ys[sz(b)] - P);
        const int X0 = S * owned_start(geo.xs, j, geo.tw);
        const int X1 = j + 1 < tpb ? S * owned_start(geo.xs, j + 1, geo.tw) : geo.sr_w;
        const int txoff = S * (geo.xs[sz(j)] - P);
        for (int r = 0; r < rows; ++r) {
          const int ty = Y0 + r - tyoff;
          const float* c0 = t->out.channel(0).row(ty);
          const float* c1 = t->out.channel(1).row(ty);
          const float* c2 = t->out.channel(2).row(ty);
          uint8_t* dst = band.data() + sz(r) * sz(geo.sr_w) * 3;
          for (int X = X0; X < X1; ++X) {
            const int tx = X - txoff;
            uint8_t* d = dst + sz(X) * 3;
            d[0] = q(c0[tx]);
            d[1] = q(c1[tx]);
            d[2] = q(c2[tx]);
          }
        }
        const int64_t done = ++done_tiles;
        if (j + 1 == tpb) {
          uint8_t* out = band.data();
          const int orows = geo.band_out_rows(b);
          if (geo.down > 1) {
            down_buf.resize(sz(orows) * sz(geo.out_w) * 3);
            area_down(band.data(), geo.sr_w, rows, geo.down, down_buf.data());
            out = down_buf.data();
          }
          if (is_last && !faces.empty())
            paste_faces(out, geo.out_w, geo.band_out_y0(b), orows, faces);
          if (is_last) preview.add_rows(out, geo.band_out_y0(b), orows);
          st.commit(b, out, sz(orows) * sz(geo.out_w) * 3, ckp);
        }
        const double el = duration<double>(steady_clock::now() - t_sr).count();
        const int64_t here = done - resumed_tiles;
        const int64_t eta =
            here > 0 ? int64_t(el / double(here) * double(total_tiles - done) * 1000) : -1;
        sink.progress(kStageUpscale, done, total_tiles, eta, done == total_tiles);
      }
    }));

    prep.join();
    infer.join();
    post.join();
  };

  if (x8 && !pass1_done) {
    sr_pass(img, g1, store1, ck1, start1, false);
    if (stop()) throw Stopped{};
  }
  if (x8) {  // the second pass's input: the first pass's bands
    Rgb8 mid;
    mid.w = g1.out_w;
    mid.h = g1.out_h;
    mid.px.resize(sz(mid.w) * sz(mid.h) * 3);
    img = Rgb8{};
    std::vector<uint8_t> buf;
    for (int b = 0; b < g1.bands(); ++b) {
      const size_t n = sz(g1.band_out_rows(b)) * sz(g1.out_w) * 3;
      store1.read_band(b, buf, n);
      std::memcpy(mid.row(g1.band_out_y0(b)), buf.data(), n);
    }
    img = std::move(mid);
  }
  sr_pass(img, g, store, ck, start_band, !finish);
  sentinel.disarm();
  if (stop()) throw Stopped{};
  if (x8) fs::remove_tree(fs::join(dir, kX8Dir));
  const double sr_s = duration<double>(steady_clock::now() - t_sr).count();
  const std::string backend_name = be->name();
  be.reset();

  // ---- finish (ADR-0025): resample to the result size, sharpen, paste the faces ----
  nlohmann::json band_rows = nlohmann::json::array();
  int start_finish = 0;
  const std::string finish_hash = finish ? recipe_hash(input_sha, model, g, req, "") : "";
  if (finish) {
    img = Rgb8{};
    auto rows_of = [&](int b) { return std::min(kFinishRows, final_h - b * kFinishRows); };
    BandStore out(dir);
    Checkpoint ckf;
    ckf.bands_total = finish_bands;
    ckf.out_w = final_w;
    ckf.out_h = final_h;
    ckf.recipe_hash = finish_hash;
    start_finish =
        open_bands(out, finish_bands, rows_of, final_w, ckf, resume && sr_done, finish_bytes);
    std::vector<uint8_t> band;
    for (int b = 0; b < start_finish; ++b) {
      out.read_band(b, band, sz(rows_of(b)) * sz(final_w) * 3);
      preview.add_rows(band.data(), b * kFinishRows, rows_of(b));
    }
    StoreRows sr_rows(store, g);
    LanczosResampler up(g.out_w, g.out_h, [&](int y) { return sr_rows.row(y); }, final_w, final_h);
    // Resampled rows [win_y, win_y + win_n): a band and kUsmMargin rows on either side.
    const size_t stride = sz(final_w) * 3;
    std::vector<uint8_t> win;
    int win_y = std::max(0, start_finish * kFinishRows - kUsmMargin), win_n = 0;
    done_tiles = total_tiles - finish_bands + start_finish;
    for (int b = start_finish; b < finish_bands; ++b) {
      if (stop()) throw Stopped{};
      const int y0 = b * kFinishRows, rows = rows_of(b);
      const int lo = std::max(0, y0 - kUsmMargin), hi = std::min(final_h, y0 + rows + kUsmMargin);
      if (lo > win_y) {
        win.erase(win.begin(), win.begin() + std::ptrdiff_t(sz(lo - win_y) * stride));
        win_n -= lo - win_y;
        win_y = lo;
      }
      if (win_y + win_n < hi) {
        const int n = hi - (win_y + win_n);
        win.resize(win.size() + sz(n) * stride);
        up.rows(win_y + win_n, n, win.data() + sz(win_n) * stride);
        win_n += n;
      }
      band.resize(sz(rows) * stride);
      unsharp_luma(
          final_w, final_h, [&](int y) { return win.data() + sz(y - win_y) * stride; }, y0, rows,
          float(req.sharpen), band.data());
      if (!faces.empty()) paste_faces(band.data(), final_w, y0, rows, faces);
      preview.add_rows(band.data(), y0, rows);
      out.commit(b, band.data(), band.size(), ckf);
      const int64_t done = ++done_tiles;
      sink.progress(kStageUpscale, done, total_tiles, -1, done == total_tiles);
    }
    fs::remove_tree(fs::join(dir, kPreDir));
    for (int b = 0; b < finish_bands; ++b) band_rows.push_back(rows_of(b));
  } else {
    for (int b = 0; b < g.bands(); ++b) band_rows.push_back(g.band_out_rows(b));
  }

  // ---- finalize ----
  sink.emit(ENH_EV_STAGE, kStageFinalize, 0, 0, {{"stage", "finalize"}});
  Rgb8 pv = preview.finish();
  jpeg_encode(fs::join(dir, kPreviewFile), pv, 90);

  result = {{"schema", 1},
            {"job_id", req.job_id},
            {"job_dir", dir},
            {"width", finish ? final_w : g.out_w},
            {"height", finish ? final_h : g.out_h},
            {"band_rows", band_rows},
            {"preview", {{"file", kPreviewFile}, {"width", pv.w}, {"height", pv.h}}},
            {"input",
             {{"width", src_w},
              {"height", src_h},
              {"orientation", info.orientation},
              {"format", info.format}}},
            {"scale", req.scale},
            {"fast2", req.fast2},
            {"model", model.id},
            {"backend", backend_name},
            {"fallbacks", fallbacks},
            {"tile", g.tw},
            {"pad", g.pad},
            // ADR-0025: as asked (the recipe, like scale and fast2), and the factor of the input
            // SR ran at: min(fast 2x ? 0.5 : 1, pre_down); 1 without a downscale.
            {"pre_down", req.pre_down},
            {"sr_pre_down", pre         ? req.pre_down
                            : req.fast2 ? 0.5
                                        : 1.0},
            {"sharpen", req.sharpen},
            {"resumed_from_band", finish && sr_done ? start_finish : start_band},
            {"recipe_hash", finish ? finish_hash : ck.recipe_hash},
            {"timings_ms",
             {{"sr", int64_t(sr_s * 1000)},
              {"total", int64_t(duration<double>(steady_clock::now() - t_start).count() * 1000)}}}};
  if (!alpha_json.is_null()) result["alpha"] = alpha_json;
  fs::write_atomic(fs::join(dir, kResultFile), result.dump(2) + "\n");
}

// ---------------------------------------------------------------------------------------------
// C ABI
// ---------------------------------------------------------------------------------------------

namespace {

enh_status create_job(enh_session* s, const JobRequest& r, bool resume, enh_job** out) {
  if (s->work_dir.empty()) fail(ENH_E_INVALID, "session has no work_dir");
  auto j = std::make_unique<enh_job>();
  j->s = s;
  j->req = r;
  j->dir = fs::join(s->work_dir, r.job_id);
  j->resume = resume;
  j->warnings_seen = s->memory_warnings.load();
  fs::mkdirs(j->dir);
  if (!resume)
    fs::write_atomic(fs::join(j->dir, kRequestFile), dump_json(job_request_to_json(r)) + "\n");
  *out = j.release();
  return ENH_OK;
}

template <class F>
enh_status guard(F&& f) {
  try {
    return std::forward<F>(f)();
  } catch (const Error& e) {
    ENH_LOGW("%s", e.what());
    return e.status();
  } catch (const std::bad_alloc&) {
    return ENH_E_OOM;
  } catch (const std::exception& e) {
    ENH_LOGE("%s", e.what());
    return ENH_E_INTERNAL;
  }
}

// The sink is attached after winning the start race and before the runner exists.
template <class Attach>
enh_status start_job(enh_job* j, Attach&& attach) {
  bool expected = false;
  if (!j->started.compare_exchange_strong(expected, true)) return ENH_E_INVALID;
  try {
    std::forward<Attach>(attach)();
  } catch (...) {
    j->started = false;
    throw;
  }
  j->runner = std::thread([j] { j->run(); });
  return ENH_OK;
}

std::string strip_slash(std::string p) {
  while (p.size() > 1 && p.back() == '/') p.pop_back();
  return p;
}

}  // namespace

extern "C" {

intptr_t enh_dart_init(void* api_dl_data) { return dart_api_init(api_dl_data); }

enh_status enh_job_create(enh_session* s, const char* request_json, enh_job** out) {
  if (!s || !request_json || !out) return ENH_E_INVALID;
  return guard([&] { return create_job(s, parse_job_request(request_json), false, out); });
}

enh_status enh_job_resume(enh_session* s, const char* job_dir, enh_job** out) {
  if (!s || !job_dir || !out) return ENH_E_INVALID;
  return guard([&] {
    JobRequest r = parse_job_request(fs::read_text(fs::join(job_dir, kRequestFile)));
    if (strip_slash(fs::join(s->work_dir, r.job_id)) != strip_slash(job_dir)) {
      fail(ENH_E_INVALID, "job_dir is not inside the session work_dir");
    }
    return create_job(s, r, true, out);
  });
}

enh_status enh_job_start(enh_job* j, enh_event_cb cb, int64_t token) {
  if (!j || !cb) return ENH_E_INVALID;
  return guard([&] { return start_job(j, [&] { j->sink.set_callback(cb, token); }); });
}

enh_status enh_job_start_port(enh_job* j, int64_t port, int64_t token) {
  if (!j || !port) return ENH_E_INVALID;
  return guard([&] { return start_job(j, [&] { j->sink.set_port(port, token); }); });
}

enh_status enh_job_set_port(enh_job* j, int64_t port, int64_t token) {
  if (!j) return ENH_E_INVALID;
  return guard([&] {
    j->sink.set_port(port, token);
    return ENH_OK;
  });
}

enh_status enh_job_set_callback(enh_job* j, enh_event_cb cb, int64_t token) {
  if (!j) return ENH_E_INVALID;
  j->sink.set_callback(cb, token);
  return ENH_OK;
}

enh_status enh_job_answer(enh_job* j, const char* answer_json) {
  if (!j || !answer_json) return ENH_E_INVALID;
  auto a = nlohmann::json::parse(answer_json, nullptr, false);
  if (a.is_discarded() || !a.is_object()) return ENH_E_INVALID;
  std::lock_guard lk(j->nu_mu);
  j->answer = std::move(a);
  j->answered = true;
  j->nu_cv.notify_all();
  return ENH_OK;
}

void enh_job_cancel(enh_job* j) {
  if (!j) return;
  j->cancel = true;
  j->request_stop();
}

void enh_job_pause(enh_job* j) {
  if (!j) return;
  j->pause = true;
  j->request_stop();
}

int32_t enh_job_status(enh_job* j) { return j ? j->status.load() : ENH_E_INVALID; }

void enh_job_destroy(enh_job* j) {
  if (!j) return;
  if (j->runner.joinable()) {
    if (j->status.load() < 0) enh_job_cancel(j);
    j->runner.join();
  }
  delete j;
}

}  // extern "C"
