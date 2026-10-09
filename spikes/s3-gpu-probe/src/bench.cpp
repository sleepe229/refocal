#include "bench.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <random>

#include <benchmark.h>
#include <cpu.h>
#include <gpu.h>
#include <net.h>

namespace refocal {

bool parse_backend(const std::string& s, BackendSpec& out) {
    out.name = s;
    size_t dash = s.find('-');
    if (dash == std::string::npos) return false;
    std::string dev = s.substr(0, dash), prec = s.substr(dash + 1);
    if (prec != "fp16" && prec != "fp32") return false;
    out.fp16 = prec == "fp16";
    if (dev == "cpu") {
        out.gpu = -1;
        return true;
    }
    if (dev.rfind("vk", 0) == 0 && dev.size() > 2) {
        try { out.gpu = std::stoi(dev.substr(2)); } catch (...) { return false; }
        return out.gpu >= 0;
    }
    return false;
}

bool load_f32(const std::string& path, size_t count, std::vector<float>& out) {
    FILE* f = std::fopen(path.c_str(), "rb");
    if (!f) return false;
    out.resize(count);
    size_t n = std::fread(out.data(), sizeof(float), count, f);
    std::fclose(f);
    return n == count;
}

static int to_u8(float x, float lo, float hi) {
    if (!std::isfinite(x)) return 0;
    float v = std::round((x - lo) / (hi - lo) * 255.f);
    return (int)std::clamp(v, 0.f, 255.f);
}

Metrics compare_u8(const std::vector<float>& out, const std::vector<float>& ref, float lo, float hi, int bad_level) {
    Metrics m;
    double se = 0;
    long bad = 0;
    size_t n = std::min(out.size(), ref.size());
    for (size_t i = 0; i < n; ++i) {
        if (!std::isfinite(out[i])) ++m.nonfinite;
        int d = to_u8(out[i], lo, hi) - to_u8(ref[i], lo, hi);
        int a = std::abs(d);
        se += (double)d * d;
        if (a > bad_level) ++bad;
        m.max_abs_u8 = std::max(m.max_abs_u8, a);
    }
    double mse = n ? se / n : 1e9;
    m.psnr = mse <= 0 ? 99.0 : std::min(99.0, 10.0 * std::log10(255.0 * 255.0 / mse));
    m.bad_frac = n ? (double)bad / n : 1.0;
    return m;
}

void apply_corruption(std::vector<float>& v, int c, int h, int w, const std::string& mode) {
    size_t plane = (size_t)h * w;
    if (mode == "zero") {  // what rsqrt(inf)=0 overflow looks like (S1)
        std::fill(v.begin(), v.end(), 0.f);
    } else if (mode == "noise") {  // uniform +-0.1 of full range
        std::mt19937 rng(42);
        std::uniform_real_distribution<float> d(-0.1f, 0.1f);
        for (auto& x : v) x += d(rng);
    } else if (mode == "nan") {
        v[v.size() / 2] = NAN;
    } else if (mode == "block32") {  // one stale/unwritten 32x32 block (localized driver bug)
        for (int q = 0; q < c; ++q)
            for (int y = 0; y < 32 && y < h; ++y)
                for (int x = 0; x < 32 && x < w; ++x) v[q * plane + (size_t)y * w + x] = 0.f;
    } else if (mode == "half") {  // bottom half never written (partial dispatch)
        for (int q = 0; q < c; ++q)
            for (size_t i = plane / 2; i < plane; ++i) v[q * plane + i] = 0.f;
    } else if (mode == "swap_rb") {  // channel order bug
        if (c >= 3) std::swap_ranges(v.begin(), v.begin() + plane, v.begin() + 2 * plane);
    } else if (mode == "offset") {  // small global bias (~2 levels of 255): must NOT be flagged
        for (auto& x : v) x += 2.f / 255.f;
    }
}

static void mat_from_chw(ncnn::Mat& m, const float* data, int c, int h, int w) {
    m.create(w, h, c);
    for (int q = 0; q < c; ++q) std::copy(data + (size_t)q * h * w, data + (size_t)(q + 1) * h * w, (float*)m.channel(q));
}

static std::vector<float> chw_from_mat(const ncnn::Mat& m) {
    std::vector<float> v((size_t)m.c * m.h * m.w);
    for (int q = 0; q < m.c; ++q) {
        const float* p = m.channel(q);
        std::copy(p, p + (size_t)m.h * m.w, v.begin() + (size_t)q * m.h * m.w);
    }
    return v;
}

static double median(std::vector<double> v) {
    if (v.empty()) return 0;
    std::sort(v.begin(), v.end());
    return v.size() % 2 ? v[v.size() / 2] : 0.5 * (v[v.size() / 2 - 1] + v[v.size() / 2]);
}

nlohmann::json run_bench(const ModelSpec& m, const BackendSpec& b, const BenchConfig& cfg) {
    nlohmann::json r = {{"backend", b.name}, {"model", m.id}, {"precision", b.fp16 ? "fp16" : "fp32"},
                        {"gpu_index", b.gpu}, {"status", "error"}};
    std::vector<float> in, golden;
    if (!load_f32(m.input_file, (size_t)m.c * m.h * m.w, in) ||
        !load_f32(m.golden_file, (size_t)m.oc * m.oh * m.ow, golden)) {
        r["error"] = "cannot read golden input/output";
        return r;
    }
    double t0 = ncnn::get_current_time();
    if (b.gpu >= 0) {
        if (ncnn::create_gpu_instance() != 0 || b.gpu >= ncnn::get_gpu_count()) {
            r["error"] = "vulkan device not available";
            return r;
        }
    }
    int threads = cfg.threads > 0 ? cfg.threads : ncnn::get_big_cpu_count();
    r["threads"] = threads;
    nlohmann::json out_json;
    {
        ncnn::Net net;
        net.opt.num_threads = threads;
        net.opt.use_fp16_packed = b.fp16;
        net.opt.use_fp16_storage = b.fp16;
        net.opt.use_fp16_arithmetic = b.fp16;
        if (b.gpu >= 0) {
            net.opt.use_vulkan_compute = true;
            net.set_vulkan_device(b.gpu);
            const ncnn::GpuInfo& gi = ncnn::get_gpu_info(b.gpu);
            r["fp16_effective"] = b.fp16 && gi.support_fp16_storage();
        } else {
            net.opt.use_vulkan_compute = false;
            if (m.face) {
                net.opt.use_winograd_convolution = false;
                net.opt.use_sgemm_convolution = false;
            }
#if defined(__aarch64__)
            r["fp16_effective"] = b.fp16 && ncnn::cpu_support_arm_asimdhp();
#else
            r["fp16_effective"] = false;  // x86: no fp16 arithmetic, computes in fp32
#endif
        }
        if (net.load_param(m.param.c_str()) != 0 || net.load_model(m.bin.c_str()) != 0) {
            r["error"] = "load_param/load_model failed";
            goto done;
        }
        r["load_ms"] = ncnn::get_current_time() - t0;

        auto run_once = [&](const float* data, int h, int w, std::vector<float>* out, int* oh, int* ow) -> int {
            ncnn::Mat inm;
            mat_from_chw(inm, data, m.c, h, w);
            ncnn::Extractor ex = net.create_extractor();
            if (ex.input("in0", inm) != 0) return -1;
            ncnn::Mat o;
            int rc = ex.extract("out0", o);
            if (rc != 0) return rc;
            if (o.empty()) return -2;
            if (out) {
                *out = chw_from_mat(o);
                *oh = o.h;
                *ow = o.w;
                if (o.c != m.oc) return -3;
            }
            return 0;
        };

        std::vector<float> out;
        int oh = 0, ow = 0;
        std::vector<double> times;
        for (int i = 0; i < cfg.warmup + cfg.runs; ++i) {
            double s = ncnn::get_current_time();
            int rc = run_once(in.data(), m.h, m.w, &out, &oh, &ow);
            double e = ncnn::get_current_time() - s;
            if (rc != 0) {
                r["error"] = "extract failed rc=" + std::to_string(rc);
                goto done;
            }
            if (i == 0) r["first_run_ms"] = e;
            if (i == 0 && cfg.max_run_ms > 0 && e > cfg.max_run_ms) {  // correctness still checked below
                times.push_back(e);
                r["too_slow"] = true;
                break;
            }
            if (i >= cfg.warmup) times.push_back(e);
        }
        r["runs"] = (int)times.size();
        r["median_ms"] = median(times);
        r["min_ms"] = *std::min_element(times.begin(), times.end());
        r["max_ms"] = *std::max_element(times.begin(), times.end());
        r["input"] = std::to_string(m.w) + "x" + std::to_string(m.h);

        if (oh != m.oh || ow != m.ow) {
            r["status"] = "wrong_output";
            r["reason"] = "shape " + std::to_string(ow) + "x" + std::to_string(oh);
            goto done;
        }
        if (!cfg.corrupt.empty()) {
            apply_corruption(out, m.oc, oh, ow, cfg.corrupt);
            r["corrupt"] = cfg.corrupt;
        }
        Metrics mt = compare_u8(out, golden, m.lo, m.hi, cfg.gate.bad_level);
        r["psnr_db"] = std::round(mt.psnr * 100) / 100;
        r["bad_frac"] = mt.bad_frac;
        r["max_abs_err_u8"] = mt.max_abs_u8;
        r["nonfinite"] = mt.nonfinite;
        double omin = 1e30, omax = -1e30;
        for (float x : out)
            if (std::isfinite(x)) { omin = std::min<double>(omin, x); omax = std::max<double>(omax, x); }
        r["out_min"] = omin;
        r["out_max"] = omax;
        std::vector<std::string> why;
        if (mt.nonfinite > 0) why.push_back("nan_inf");
        if (mt.psnr < cfg.gate.min_psnr) why.push_back("psnr<" + std::to_string((int)cfg.gate.min_psnr));
        if (mt.bad_frac > cfg.gate.max_bad_frac) why.push_back("bad_frac");
        if (why.empty() && r.value("too_slow", false)) {
            r["status"] = "too_slow";
            r["reason"] = "warm-up run " + std::to_string((int)times[0]) + " ms > budget " +
                          std::to_string((int)cfg.max_run_ms) + " ms; output correct";
            goto done;
        }
        if (why.empty()) {
            r["status"] = "ok";
        } else {
            r["status"] = "wrong_output";
            std::string s;
            for (auto& w : why) s += (s.empty() ? "" : ",") + w;
            r["reason"] = s;
        }

        if (m.tile128) {  // timing only: 128x128 centre crop
            std::vector<float> crop((size_t)m.c * 128 * 128);
            int y0 = (m.h - 128) / 2, x0 = (m.w - 128) / 2;
            for (int q = 0; q < m.c; ++q)
                for (int y = 0; y < 128; ++y)
                    std::copy(&in[(size_t)q * m.h * m.w + (size_t)(y0 + y) * m.w + x0],
                              &in[(size_t)q * m.h * m.w + (size_t)(y0 + y) * m.w + x0 + 128],
                              &crop[(size_t)q * 128 * 128 + (size_t)y * 128]);
            std::vector<double> t128;
            for (int i = 0; i < cfg.warmup + cfg.runs; ++i) {
                double s = ncnn::get_current_time();
                std::vector<float> o2;
                int h2, w2;
                if (run_once(crop.data(), 128, 128, &o2, &h2, &w2) != 0) break;
                if (i >= cfg.warmup) t128.push_back(ncnn::get_current_time() - s);
            }
            if (!t128.empty()) r["tile128_median_ms"] = median(t128);
        }
    }
done:
    r["total_ms"] = ncnn::get_current_time() - t0;
    if (b.gpu >= 0) ncnn::destroy_gpu_instance();
    return r;
}

nlohmann::json run_tiled(const ModelSpec& m, const BackendSpec& b, int threads, int W, int H, int tile, int pad) {
    nlohmann::json r = {{"backend", b.name}, {"model", m.id}, {"image", std::to_string(W) + "x" + std::to_string(H)},
                        {"tile", tile}, {"pad", pad}};
    std::vector<float> golden_in;
    if (!load_f32(m.input_file, (size_t)m.c * m.h * m.w, golden_in)) { r["error"] = "no input"; return r; }
    // synthetic image: golden tile mirrored-repeated over W x H (realistic content statistics)
    std::vector<float> img((size_t)m.c * W * H);
    for (int q = 0; q < m.c; ++q)
        for (int y = 0; y < H; ++y)
            for (int x = 0; x < W; ++x) {
                int sy = (y / m.h) % 2 ? m.h - 1 - y % m.h : y % m.h;
                int sx = (x / m.w) % 2 ? m.w - 1 - x % m.w : x % m.w;
                img[(size_t)q * W * H + (size_t)y * W + x] = golden_in[(size_t)q * m.h * m.w + (size_t)sy * m.w + sx];
            }
    if (b.gpu >= 0 && ncnn::create_gpu_instance() != 0) { r["error"] = "no vulkan"; return r; }
    {
        ncnn::Net net;
        net.opt.num_threads = threads > 0 ? threads : ncnn::get_big_cpu_count();
        net.opt.use_fp16_packed = net.opt.use_fp16_storage = net.opt.use_fp16_arithmetic = b.fp16;
        net.opt.use_vulkan_compute = b.gpu >= 0;
        if (b.gpu >= 0) net.set_vulkan_device(b.gpu);
        net.load_param(m.param.c_str());
        net.load_model(m.bin.c_str());
        int core = tile - 2 * pad;
        int nx = (W + core - 1) / core, ny = (H + core - 1) / core;
        std::vector<float> crop((size_t)m.c * tile * tile);
        auto run_tile = [&](int tx, int ty) {
            int x0 = std::clamp(tx * core - pad, 0, W - tile), y0 = std::clamp(ty * core - pad, 0, H - tile);
            for (int q = 0; q < m.c; ++q)
                for (int y = 0; y < tile; ++y)
                    std::copy(&img[(size_t)q * W * H + (size_t)(y0 + y) * W + x0],
                              &img[(size_t)q * W * H + (size_t)(y0 + y) * W + x0 + tile],
                              &crop[(size_t)q * tile * tile + (size_t)y * tile]);
            ncnn::Mat inm;
            mat_from_chw(inm, crop.data(), m.c, tile, tile);
            ncnn::Extractor ex = net.create_extractor();
            ex.input("in0", inm);
            ncnn::Mat o;
            ex.extract("out0", o);
            std::vector<float> v = chw_from_mat(o);  // include download + copy like the real pipeline
            (void)v;
        };
        run_tile(0, 0);  // warm-up (pipeline creation for this shape)
        double t0 = ncnn::get_current_time();
        for (int ty = 0; ty < ny; ++ty)
            for (int tx = 0; tx < nx; ++tx) run_tile(tx, ty);
        double total = ncnn::get_current_time() - t0;
        r["tiles"] = nx * ny;
        r["total_ms"] = total;
        r["ms_per_tile"] = total / (nx * ny);
        r["us_per_input_px"] = total * 1000.0 / ((double)W * H);
    }
    if (b.gpu >= 0) ncnn::destroy_gpu_instance();
    return r;
}

}  // namespace refocal
