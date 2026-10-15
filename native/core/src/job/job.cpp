// Job runner (ADR-0006, ADR-0012 for the 0.1 subset): decode (any format) -> orient -> [fast 2x] ->
// SR banded (prep -> infer -> post, depth-2 queues) -> BandStore -> preview -> result.
// Cancel/pause are checked at tile boundaries; queued tiles are dropped, the tile in flight
// finishes (S6: latency <= 1 tile). Exactly one terminal event per started job.
// SPDX-License-Identifier: Apache-2.0
#include "job/job.hpp"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <optional>
#include <regex>
#include <thread>
#include <vector>

#include <net.h>

#include "backend/backend.hpp"
#include "enh.h"
#include "image/decode.hpp"
#include "image/jpeg.hpp"
#include "image/ops.hpp"
#include "job/events.hpp"
#include "job/session.hpp"
#include "pipeline/bandstore.hpp"
#include "pipeline/geometry.hpp"
#include "policy/gpu_gate.hpp"
#include "policy/gpu_identity.hpp"
#include "util/error.hpp"
#include "util/fs.hpp"
#include "util/log.hpp"
#include "util/sha256.hpp"

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
    r.tile = j.value("tile", r.tile);
    r.backend = j.value("backend", r.backend);
    r.preview_max = j.value("preview_max", r.preview_max);
    r.max_output_mp = j.value("max_output_mp", r.max_output_mp);
  } catch (const nlohmann::json::exception& e) {
    fail(ENH_E_INVALID, std::string("bad request: ") + e.what());
  }
  static const std::regex id_re("[A-Za-z0-9_-]{1,64}");
  if (!std::regex_match(r.job_id, id_re)) fail(ENH_E_INVALID, "bad job_id");
  if (r.input.empty()) fail(ENH_E_INVALID, "empty input");
  if (r.scale != 1 && r.scale != 2 && r.scale != 4) fail(ENH_E_INVALID, "scale must be 1, 2 or 4");
  if (r.fast2 && r.scale != 2) fail(ENH_E_INVALID, "fast2 requires scale 2");
  if (r.tile != 0 && (r.tile < 32 || r.tile > 1024)) fail(ENH_E_INVALID, "tile out of range");
  if (r.backend != "auto" && r.backend != "cpu" && r.backend != "vulkan") fail(ENH_E_INVALID, "bad backend");
  if (r.preview_max < 64 || r.preview_max > 8192) fail(ENH_E_INVALID, "bad preview_max");
  return r;
}

nlohmann::json job_request_to_json(const JobRequest& r) {
  return {{"schema", 1},           {"job_id", r.job_id},   {"input", r.input},
          {"sr_model", r.sr_model}, {"scale", r.scale},     {"fast2", r.fast2},
          {"tile", r.tile},         {"backend", r.backend}, {"preview_max", r.preview_max},
          {"max_output_mp", r.max_output_mp}};
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
  return c.kind == BackendKind::vulkan ? (c.fp16 ? "vulkan_fp16" : "vulkan_fp32") : "cpu";
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
      if (hot) sink.emit(ENH_EV_WARNING, kStageUpscale, done, total, {{"code", "thermal_throttle"}});
    }
    if (hot) {
      for (int i = 0; i < kThermalPauseMs / 50 && !stop(); ++i) std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
    return !stop();
  }

  bool throttled = false;  // inference thread only

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
      if (m.action != Action::GpuFp32) l.rungs.push_back({BackendKind::vulkan, dev, true, s.cpu_threads});
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
  std::string key() const { return rec_.key(); }

 private:
  enh_session& s_;
  SentinelRecord rec_;
  bool armed_ = false;
};

int auto_tile(const enh_session& s, const BackendConfig& first) {
  // S2/S3: T0 (CPU, 600 MB) -> 128; T1/T2 -> 256; never 512 on Vulkan (silent corruption).
  if (first.kind == BackendKind::vulkan) return 256;
  return s.tier == "T1" || s.tier == "T2" ? 256 : 128;
}

std::string recipe_hash(const std::string& input_sha, const ModelInfo& m, const Geometry& g,
                        const JobRequest& r) {
  Sha256 h;
  std::string model_sha = Sha256::of_file(m.param_path) + Sha256::of_file(m.bin_path);
  std::string s = "v1;in=" + input_sha + ";model=" + model_sha + ";scale=" + std::to_string(r.scale) +
                  ";fast2=" + std::to_string(r.fast2) + ";tile=" + std::to_string(g.tw) + "x" +
                  std::to_string(g.th) + ";pad=" + std::to_string(g.pad) +
                  ";down=" + std::to_string(g.down);
  return Sha256::of_string(s);
}

}  // namespace

void enh_job::run() {
  nlohmann::json result;
  enh_status final_status = ENH_OK;
  std::string message;
  try {
    run_impl(result);
  } catch (const Stopped&) {
  } catch (const Error& e) {
    record_error(e.status(), e.what());
  } catch (const std::bad_alloc&) {
    record_error(ENH_E_OOM, "out of memory");
  } catch (const std::exception& e) {
    record_error(ENH_E_INTERNAL, e.what());
  }
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

  auto out_mp = [&](const JobRequest& r) {  // fast 2x: (w/2)*4 = 2w
    if (r.fast2) return std::floor(info.w / 2.0) * 4 * std::floor(info.h / 2.0) * 4 / 1e6;
    return double(info.w) * r.scale * double(info.h) * r.scale / 1e6;
  };
  while (out_mp(req) > req.max_output_mp) {
    nlohmann::json opts = nlohmann::json::array();
    for (auto [sc, f2] : {std::pair{2, true}, std::pair{2, false}, std::pair{1, false}}) {
      JobRequest t = req;
      t.scale = sc;
      t.fast2 = f2;
      if ((sc < req.scale || (sc == req.scale && f2 && !req.fast2)) && out_mp(t) <= req.max_output_mp)
        opts.push_back({{"scale", sc}, {"fast2", f2}});
    }
    if (opts.empty()) fail(ENH_E_LIMIT, "input too large for any scale");
    nlohmann::json a = wait_answer({{"code", "downscale_required"},
                                    {"output_mp", out_mp(req)},
                                    {"max_output_mp", req.max_output_mp},
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
  if (!meta.exif.empty()) fs::write_atomic(fs::join(dir, kSourceExifFile), meta.exif.data(), meta.exif.size());
  if (!meta.icc.empty()) fs::write_atomic(fs::join(dir, kSourceIccFile), meta.icc.data(), meta.icc.size());
  if (info.alpha) sink.emit(ENH_EV_WARNING, kStageDecode, 0, 0, {{"code", "alpha_flattened"}});
  if (info.animated) sink.emit(ENH_EV_WARNING, kStageDecode, 0, 0, {{"code", "animation_first_frame"}});
  const int src_w = img.w, src_h = img.h;
  if (req.fast2) img = area_down(img, 2);
  if (stop()) throw Stopped{};

  // ---- geometry, backend, store ----
  Ladder lad = backend_ladder(*s, req, model.id);
  std::vector<BackendConfig>& ladder = lad.rungs;
  if (!lad.skipped_reason.empty()) {
    sink.emit(ENH_EV_WARNING, kStageDecode, 0, 0,
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
  const int down = req.fast2 ? 1 : model.scale / req.scale;
  if (down < 1) fail(ENH_E_INVALID, "scale exceeds model scale");
  Geometry g = Geometry::make(img.w, img.h, tile, model.pad, model.scale, down);

  // ---- GPU correctness gate (ADR-0017, S3) ----
  SentinelGuard sentinel(*s, lad.gpu, model.id, g.tw);
  if (ladder[rung].kind == BackendKind::vulkan) {
    std::unique_ptr<GateCache> cache;
    if (!s->cache_dir.empty()) cache = std::make_unique<GateCache>(fs::join(s->cache_dir, "gpu/gate.json"));
    const ncnn::Mat in = gate_input(g.net_in_w(), g.net_in_h());
    ncnn::Mat ref;
    while (ladder[rung].kind == BackendKind::vulkan) {
      const std::string key = sentinel.key() + "|" + backend_kind_name(ladder[rung]) + "|" +
                              std::to_string(g.net_in_w()) + "x" + std::to_string(g.net_in_h());
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
                {{"code", "gpu_check_failed"}, {"backend", backend_kind_name(ladder[rung])},
                 {"psnr", m.psnr}, {"device", lad.gpu.device_name}});
      ++rung;
      be.reset();
      be = make_ncnn_backend(ladder[rung]);
      be->load(model);
    }
    if (stop()) throw Stopped{};
  }

  BandStore store(dir);
  Checkpoint ck;
  ck.bands_total = g.bands();
  ck.out_w = g.out_w;
  ck.out_h = g.out_h;
  ck.recipe_hash = recipe_hash(input_sha, model, g, req);

  int start_band = 0;
  Checkpoint old;
  if (resume && store.load_checkpoint(old) && old.recipe_hash == ck.recipe_hash &&
      old.bands_total == ck.bands_total) {
    bool ok = true;
    for (int b = 0; b <= old.band_idx && ok; ++b)
      ok = fs::file_size(store.band_path(b)) == int64_t(g.band_out_rows(b)) * g.out_w * 3;
    if (ok) {
      start_band = old.band_idx + 1;
      store.discard_after(old.band_idx, g.bands());
    }
  }
  if (start_band == 0) {
    if (resume) sink.emit(ENH_EV_WARNING, kStageDecode, 0, 0, {{"code", "resume_restarted"}});
    store.reset();
    const double need = double(g.out_w) * g.out_h * 3 * 1.2;  // NFR-SIZE-004: estimate + 20%
    const int64_t avail = fs::free_bytes(dir);
    if (avail >= 0 && double(avail) < need) {
      fail(ENH_E_DISK_FULL, "need " + std::to_string(int64_t(need / 1e6)) + " MB free");
    }
  }

  PreviewAccumulator preview;
  preview.init(g.out_w, g.out_h, req.preview_max);
  if (start_band > 0) {
    std::vector<uint8_t> buf;
    for (int b = 0; b < start_band; ++b) {
      store.read_band(b, buf, size_t(g.band_out_rows(b)) * g.out_w * 3);
      preview.add_rows(buf.data(), g.band_out_y0(b), g.band_out_rows(b));
    }
  }

  // ---- SR banded ----
  if (ladder[rung].kind == BackendKind::vulkan) sentinel.arm();
  sink.emit(ENH_EV_STAGE, kStageUpscale, 0, g.tiles(), {{"stage", "upscale"}});
  const int tpb = g.tiles_per_band();
  const int64_t total_tiles = g.tiles();
  std::atomic<int64_t> done_tiles{int64_t(start_band) * tpb};
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

  std::thread prep(guarded([&] {
    const int P = g.pad, itw = g.net_in_w(), ith = g.net_in_h();
    std::vector<int> colidx(static_cast<size_t>(itw));
    for (int b = start_band; b < g.bands() && !stop(); ++b) {
      for (int j = 0; j < tpb && !stop(); ++j) {
        TileIn t{b, j, ncnn::Mat(itw, ith, 3)};
        const int x0 = g.xs[j];
        for (int xx = 0; xx < itw; ++xx) colidx[xx] = reflect101(x0 - P + xx, g.in_w);
        for (int yy = 0; yy < ith; ++yy) {
          const uint8_t* src = img.row(reflect101(g.ys[b] - P + yy, g.in_h));
          float* r = t.in.channel(0).row(yy);
          float* gg = t.in.channel(1).row(yy);
          float* bl = t.in.channel(2).row(yy);
          for (int xx = 0; xx < itw; ++xx) {
            const uint8_t* p = src + colidx[xx] * 3;
            r[xx] = p[0] * (1.f / 255.f);
            gg[xx] = p[1] * (1.f / 255.f);
            bl[xx] = p[2] * (1.f / 255.f);
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
      TileOut o{t->band, t->j, {}};
      for (;;) {
        try {
          be->run(t->in, o.out);
          break;
        } catch (const Error& e) {
          bool recoverable = e.status() == ENH_E_BACKEND || e.status() == ENH_E_NUMERIC;
          if (!recoverable || rung + 1 >= ladder.size()) throw;
          std::string from = backend_kind_name(ladder[rung]);
          ++rung;
          std::string to = backend_kind_name(ladder[rung]);
          sink.emit(ENH_EV_FALLBACK, kStageUpscale, done_tiles, total_tiles,
                    {{"from", from}, {"to", to},
                     {"reason", e.status() == ENH_E_NUMERIC ? "numeric" : "backend_error"}});
          fallbacks.push_back(from + "->" + to);
          if (ladder[rung].kind != BackendKind::vulkan) sentinel.disarm();  // GPU stage over
          be.reset();
          be = make_ncnn_backend(ladder[rung]);
          be->load(model);
          throttled = false;  // a new backend runs unthrottled: the next gate applies it again
        }
      }
      const int S = g.model_scale;
      if (o.out.w != S * g.net_in_w() || o.out.h != S * g.net_in_h() || o.out.c != 3) {
        fail(ENH_E_MODEL, "unexpected model output shape");
      }
      if (!q2.push(std::move(o))) return;
    }
    q2.close();
  }));

  std::thread post(guarded([&] {
    const int S = g.model_scale, P = g.pad;
    std::vector<uint8_t> band, down_buf;
    auto q = [](float v) -> uint8_t {
      v = v < 0.f ? 0.f : (v > 1.f ? 1.f : v);
      return uint8_t(v * 255.f + 0.5f);
    };
    while (auto t = q2.pop()) {
      if (stop()) break;
      const int b = t->band, j = t->j;
      const int rows = g.band_sr_rows(b);
      if (j == 0) band.assign(size_t(rows) * g.sr_w * 3, 0);
      const int Y0 = S * g.band_in_y0(b);
      const int tyoff = S * (g.ys[b] - P);
      const int X0 = S * owned_start(g.xs, j, g.tw);
      const int X1 = j + 1 < tpb ? S * owned_start(g.xs, j + 1, g.tw) : g.sr_w;
      const int txoff = S * (g.xs[j] - P);
      for (int r = 0; r < rows; ++r) {
        const int ty = Y0 + r - tyoff;
        const float* c0 = t->out.channel(0).row(ty);
        const float* c1 = t->out.channel(1).row(ty);
        const float* c2 = t->out.channel(2).row(ty);
        uint8_t* dst = band.data() + size_t(r) * g.sr_w * 3;
        for (int X = X0; X < X1; ++X) {
          const int tx = X - txoff;
          dst[X * 3] = q(c0[tx]);
          dst[X * 3 + 1] = q(c1[tx]);
          dst[X * 3 + 2] = q(c2[tx]);
        }
      }
      const int64_t done = ++done_tiles;
      if (j + 1 == tpb) {
        const uint8_t* out = band.data();
        const int orows = g.band_out_rows(b);
        if (g.down > 1) {
          down_buf.resize(size_t(orows) * g.out_w * 3);
          area_down(band.data(), g.sr_w, rows, g.down, down_buf.data());
          out = down_buf.data();
        }
        preview.add_rows(out, g.band_out_y0(b), orows);
        store.commit(b, out, size_t(orows) * g.out_w * 3, ck);
      }
      const double el = duration<double>(steady_clock::now() - t_sr).count();
      const int64_t here = done - resumed_tiles;
      const int64_t eta = here > 0 ? int64_t(el / here * (total_tiles - done) * 1000) : -1;
      sink.progress(kStageUpscale, done, total_tiles, eta, done == total_tiles);
    }
  }));

  prep.join();
  infer.join();
  post.join();
  sentinel.disarm();
  if (stop()) throw Stopped{};
  const double sr_s = duration<double>(steady_clock::now() - t_sr).count();
  const std::string backend_name = be->name();
  be.reset();

  // ---- finalize ----
  sink.emit(ENH_EV_STAGE, kStageFinalize, 0, 0, {{"stage", "finalize"}});
  Rgb8 pv = preview.finish();
  jpeg_encode(fs::join(dir, kPreviewFile), pv, 90);

  nlohmann::json band_rows = nlohmann::json::array();
  for (int b = 0; b < g.bands(); ++b) band_rows.push_back(g.band_out_rows(b));
  result = {{"schema", 1},
            {"job_id", req.job_id},
            {"job_dir", dir},
            {"width", g.out_w},
            {"height", g.out_h},
            {"band_rows", band_rows},
            {"preview", {{"file", kPreviewFile}, {"width", pv.w}, {"height", pv.h}}},
            {"input",
             {{"width", src_w}, {"height", src_h}, {"orientation", info.orientation}, {"format", info.format}}},
            {"scale", req.scale},
            {"fast2", req.fast2},
            {"model", model.id},
            {"backend", backend_name},
            {"fallbacks", fallbacks},
            {"tile", g.tw},
            {"pad", g.pad},
            {"resumed_from_band", start_band},
            {"recipe_hash", ck.recipe_hash},
            {"timings_ms",
             {{"sr", int64_t(sr_s * 1000)},
              {"total", int64_t(duration<double>(steady_clock::now() - t_start).count() * 1000)}}}};
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
  fs::mkdirs(j->dir);
  if (!resume) fs::write_atomic(fs::join(j->dir, kRequestFile), dump_json(job_request_to_json(r)) + "\n");
  *out = j.release();
  return ENH_OK;
}

template <class F>
enh_status guard(F&& f) {
  try {
    return f();
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
    attach();
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
