// refocal-probe: device probe + correctness-checked microbenchmark + GPU blocklist + crash
// sentinel (Refocal spike S3). See README.md for usage and the report schema.
#include <algorithm>
#include <chrono>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <map>
#include <string>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <vector>

#include <gpu.h>
#include <platform.h>
#include <nlohmann/json.hpp>

#include "bench.hpp"
#include "blocklist.hpp"
#include "device_info.hpp"
#include "sentinel.hpp"
#include "tier.hpp"

#ifndef REFOCAL_SPIKES_DIR
#define REFOCAL_SPIKES_DIR "."
#endif

using nlohmann::json;
using namespace refocal;

namespace {

constexpr const char* kProbeVersion = "0.3.0";
constexpr const char* kSrId = "sr.general-x4v3";
constexpr const char* kFaceId = "face.gfpgan-1.4";

struct Args {
    std::string cmd;
    std::map<std::string, std::string> kv;
    std::multimap<std::string, std::string> multi;
    std::vector<std::string> flags;
    bool has(const std::string& k) const {
        return kv.count(k) || std::find(flags.begin(), flags.end(), k) != flags.end();
    }
    std::string get(const std::string& k, const std::string& d = "") const {
        auto it = kv.find(k);
        return it == kv.end() ? d : it->second;
    }
    int geti(const std::string& k, int d) const { return kv.count(k) ? std::atoi(kv.at(k).c_str()) : d; }
    double getd(const std::string& k, double d) const { return kv.count(k) ? std::atof(kv.at(k).c_str()) : d; }
    std::vector<std::string> all(const std::string& k) const {
        std::vector<std::string> v;
        auto r = multi.equal_range(k);
        for (auto it = r.first; it != r.second; ++it) v.push_back(it->second);
        return v;
    }
};

// Options that take a value; everything else starting with -- is a boolean flag.
const std::vector<std::string> kValued = {
    "--data", "--sr-param", "--sr-bin", "--sr-in", "--sr-golden", "--face-param", "--face-bin", "--face-in",
    "--face-golden", "--face-model", "--backends", "--runs", "--face-runs", "--warmup", "--threads", "--corrupt",
    "--blocklist", "--out", "--work-dir", "--state-dir", "--exit-reason", "--timeout", "--model", "--backend",
    "--json-out", "--gpu", "--model-id", "--crash", "--crash-backend", "--block-after", "--min-psnr",
    "--max-bad-frac", "--vendor-id", "--device-name", "--driver-raw", "--driver", "--api-raw", "--platform",
    "--os-version", "--tile", "--t2-ms", "--t1-ms", "--t0-ms", "--max-run-ms"};

Args parse_args(int argc, char** argv) {
    Args a;
    if (argc > 1) a.cmd = argv[1];
    for (int i = 2; i < argc; ++i) {
        std::string k = argv[i];
        if (std::find(kValued.begin(), kValued.end(), k) != kValued.end() && i + 1 < argc) {
            a.kv[k] = argv[++i];
            a.multi.emplace(k, a.kv[k]);
        } else {
            a.flags.push_back(k);
        }
    }
    return a;
}

std::vector<std::string> split(const std::string& s, char sep) {
    std::vector<std::string> v;
    std::string cur;
    for (char c : s) {
        if (c == sep) { if (!cur.empty()) v.push_back(cur); cur.clear(); } else cur += c;
    }
    if (!cur.empty()) v.push_back(cur);
    return v;
}

std::string iso_now() {
    char b[32];
    std::time_t t = std::time(nullptr);
    std::strftime(b, sizeof b, "%Y-%m-%dT%H:%M:%SZ", std::gmtime(&t));
    return b;
}

std::string self_exe() {
    char b[4096];
    ssize_t n = readlink("/proc/self/exe", b, sizeof b - 1);
    if (n <= 0) return "refocal-probe";
    b[n] = 0;
    return b;
}

struct Paths {
    std::string sr_param, sr_bin, sr_in, sr_golden, face_param, face_bin, face_in, face_golden;
};

Paths resolve_paths(const Args& a) {
    Paths p;
    std::string face_model = a.get("--face-model", "gfpgan14s");
    if (a.has("--data")) {  // flat on-device layout (adb push)
        std::string d = a.get("--data");
        p.sr_param = d + "/sr_compact_dn050.ncnn.param";
        p.sr_bin = d + "/sr_compact_dn050.ncnn.bin";
        p.sr_in = d + "/golden_in_3x160x160.f32";
        p.sr_golden = d + "/golden_out_dn050_3x640x640.f32";
        p.face_param = d + "/" + face_model + ".ncnn.param";
        p.face_bin = d + "/" + face_model + ".ncnn.bin";
        p.face_in = d + "/face_in_3x512x512.f32";
        p.face_golden = d + "/face_out_gfpgan14_3x512x512.f32";
    } else {  // desktop: repo layout
        std::string s = REFOCAL_SPIKES_DIR;
        p.sr_param = s + "/_shared/models/sr_compact_dn050.ncnn.param";
        p.sr_bin = s + "/_shared/models/sr_compact_dn050.ncnn.bin";
        p.sr_in = s + "/_shared/models/golden_in_3x160x160.f32";
        p.sr_golden = s + "/_shared/models/golden_out_dn050_3x640x640.f32";
        p.face_param = s + "/s1-gfpgan/out/models/" + face_model + ".ncnn.param";
        p.face_bin = s + "/s1-gfpgan/out/models/" + face_model + ".ncnn.bin";
        p.face_in = s + "/s3-gpu-probe/data/golden/face_in_3x512x512.f32";
        p.face_golden = s + "/s3-gpu-probe/data/golden/face_out_gfpgan14_3x512x512.f32";
    }
    auto ov = [&](const char* k, std::string& dst) { if (a.has(k)) dst = a.get(k); };
    ov("--sr-param", p.sr_param); ov("--sr-bin", p.sr_bin); ov("--sr-in", p.sr_in); ov("--sr-golden", p.sr_golden);
    ov("--face-param", p.face_param); ov("--face-bin", p.face_bin); ov("--face-in", p.face_in);
    ov("--face-golden", p.face_golden);
    return p;
}

ModelSpec sr_spec(const Paths& p) {
    ModelSpec m;
    m.id = std::string(kSrId) + "@dn050";  // "<pack id>@<model variant/version>"
    m.param = p.sr_param; m.bin = p.sr_bin; m.input_file = p.sr_in; m.golden_file = p.sr_golden;
    m.c = 3; m.h = m.w = 160; m.oc = 3; m.oh = m.ow = 640; m.lo = 0; m.hi = 1;
    m.tile128 = true;
    return m;
}

ModelSpec face_spec(const Paths& p) {
    ModelSpec m;
    // original (un-rewritten) graph gets its own version tag so blocklist entries for it do not
    // hit the ADR-0023 rewrite: the local key is driver + "<pack>@<version>"
    m.id = std::string(kFaceId) + (p.face_param.find("gfpgan14s") != std::string::npos ? "@rewrite" : "@original");
    m.param = p.face_param; m.bin = p.face_bin; m.input_file = p.face_in; m.golden_file = p.face_golden;
    m.c = 3; m.h = m.w = 512; m.oc = 3; m.oh = m.ow = 512; m.lo = -1; m.hi = 1;
    m.face = true;
    return m;
}

Gate gate_from(const Args& a) {
    Gate g;
    g.min_psnr = a.getd("--min-psnr", g.min_psnr);
    g.max_bad_frac = a.getd("--max-bad-frac", g.max_bad_frac);
    return g;
}

std::string corrupt_for(const Args& a, const std::string& backend) {
    for (auto& c : a.all("--corrupt")) {  // "vk1-fp16:zero" or "*:noise"
        auto pos = c.find(':');
        if (pos == std::string::npos) continue;
        std::string b = c.substr(0, pos);
        if (b == "*" || b == backend) return c.substr(pos + 1);
    }
    return "";
}

[[noreturn]] void crash_now(const std::string& how) {
    std::fprintf(stderr, "[refocal-probe] simulated driver crash (%s) inside GPU stage\n", how.c_str());
    std::fflush(stderr);
    if (how == "segv") {
        std::signal(SIGSEGV, SIG_DFL);
        std::raise(SIGSEGV);
    }
    std::abort();
}

GpuIdentity gpu_identity(const std::vector<GpuDesc>& gpus, int idx) {
    for (auto& g : gpus)
        if (g.index == idx) return g.id;
    return {};
}

Blocklist build_blocklist(const Args& a, const SentinelStore* store, json* sources) {
    Blocklist bl;
    auto add = [&](ParseResult pr, const std::string& name) {
        if (sources)
            sources->push_back({{"source", name}, {"rules", pr.rules.size()}, {"errors", pr.errors},
                                {"warnings", pr.warnings}, {"revoke", pr.revoke}});
        bl.add(std::move(pr));
    };
    if (!a.has("--no-builtin")) add(parse_blocklist(builtin_blocklist_json(), "builtin"), "builtin");
    for (auto& f : a.all("--blocklist")) {
        std::string text;
        if (!read_file(f, text)) {
            if (sources) sources->push_back({{"source", f}, {"errors", {"cannot read file"}}});
            continue;
        }
        add(parse_blocklist(text, "manifest"), f);
    }
    if (store) add(store->local_rules(), "local");
    return bl;
}

json match_json(const MatchResult& m) {
    json ids = json::array();
    for (auto* r : m.matched) ids.push_back({{"id", r->id}, {"source", r->source}, {"action", action_name(r->action)},
                                             {"reason", r->reason}});
    return {{"action", action_name(m.action)}, {"rules", ids}};
}

// ---------------------------------------------------------------- child process
struct ChildResult {
    int exit_code = -1;
    int signal = 0;
    bool timeout = false;
    double wall_ms = 0;
    long maxrss_kb = 0;
    json result;
};

ChildResult spawn_child(const std::vector<std::string>& args, int timeout_s, const std::string& json_out) {
    ChildResult cr;
    ::unlink(json_out.c_str());
    auto t0 = std::chrono::steady_clock::now();
    pid_t pid = fork();
    if (pid == 0) {
        std::vector<char*> av;
        for (auto& s : args) av.push_back(const_cast<char*>(s.c_str()));
        av.push_back(nullptr);
        execv(av[0], av.data());
        _exit(127);
    }
    int status = 0;
    struct rusage ru {};
    while (true) {
        pid_t r = wait4(pid, &status, WNOHANG, &ru);
        if (r == pid) break;
        double el = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
        if (el > timeout_s) {
            kill(pid, SIGKILL);
            wait4(pid, &status, 0, &ru);
            cr.timeout = true;
            break;
        }
        usleep(20000);
    }
    cr.wall_ms = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
    cr.maxrss_kb = ru.ru_maxrss;
    if (WIFEXITED(status)) cr.exit_code = WEXITSTATUS(status);
    if (WIFSIGNALED(status)) cr.signal = WTERMSIG(status);
    std::string text;
    if (!cr.timeout && read_file(json_out, text)) {
        cr.result = json::parse(text, nullptr, false);
        if (cr.result.is_discarded()) cr.result = json();
    }
    return cr;
}

int cmd_bench_one(const Args& a) {
    Paths p = resolve_paths(a);
    ModelSpec m = a.get("--model", "sr") == "face" ? face_spec(p) : sr_spec(p);
    BackendSpec b;
    if (!parse_backend(a.get("--backend", "cpu-fp16"), b)) {
        std::fprintf(stderr, "bad --backend\n");
        return 2;
    }
    BenchConfig cfg;
    cfg.threads = a.geti("--threads", 0);
    cfg.warmup = a.geti("--warmup", 1);
    cfg.runs = a.geti("--runs", 5);
    cfg.corrupt = a.get("--corrupt");
    cfg.gate = gate_from(a);
    cfg.max_run_ms = a.getd("--max-run-ms", 0);
    if (a.has("--crash")) {  // simulated driver crash in the middle of the GPU stage
        BenchConfig c1 = cfg;
        c1.runs = 1;
        c1.warmup = 0;
        run_bench(m, b, c1);  // one real inference first, then die
        crash_now(a.get("--crash"));
    }
    json r = run_bench(m, b, cfg);
    std::string out = a.get("--json-out");
    if (!out.empty()) write_file_atomic(out, r.dump(2));
    else std::printf("%s\n", r.dump(2).c_str());
    return 0;
}

// ---------------------------------------------------------------- probe
int cmd_probe(const Args& a) {
    auto t_start = std::chrono::steady_clock::now();
    std::string work = a.get("--work-dir", "probe-out");
    ::mkdir(work.c_str(), 0755);
    std::string state = a.get("--state-dir", work + "/state");
    SentinelPolicy pol;
    pol.block_after = a.geti("--block-after", 2);
    SentinelStore store(state, pol);
    StartupReport st = store.on_startup(parse_exit_reason(a.get("--exit-reason", "unknown")));

    HostDesc host = probe_host();
    std::vector<GpuDesc> gpus = a.has("--no-gpu") ? std::vector<GpuDesc>{} : probe_gpus();
    json sources = json::array();
    Blocklist bl = build_blocklist(a, &store, &sources);
    Paths paths = resolve_paths(a);

    std::vector<std::string> backends;
    if (a.has("--backends")) {
        backends = split(a.get("--backends"), ',');
    } else {
        for (auto& g : gpus) {
            backends.push_back("vk" + std::to_string(g.index) + "-fp16");
            backends.push_back("vk" + std::to_string(g.index) + "-fp32");
        }
        backends.push_back("cpu-fp16");
    }
    std::vector<std::string> models = {"sr"};
    if (a.has("--face")) models.push_back("face");
    if (a.has("--face-only")) models = {"face"};

    int runs = a.geti("--runs", 5), face_runs = a.geti("--face-runs", 3), warmup = a.geti("--warmup", 1);
    int timeout_s = a.geti("--timeout", 300);
    bool isolate = !a.has("--no-isolate");
    std::string exe = self_exe();

    json results = json::array();
    for (auto& model : models) {
        ModelSpec ms = model == "face" ? face_spec(paths) : sr_spec(paths);
        for (auto& bname : backends) {
            BackendSpec b;
            if (!parse_backend(bname, b)) {
                results.push_back({{"backend", bname}, {"model", ms.id}, {"status", "error"}, {"error", "bad backend"}});
                continue;
            }
            json r;
            SentinelRecord rec;
            rec.model = ms.id;
            rec.backend = bname;
            rec.tile = ms.w;
            json bl_info = {{"action", "none"}};
            if (b.gpu >= 0) {
                rec.gpu = gpu_identity(gpus, b.gpu);
                MatchResult m = bl.match(rec.gpu, ms.id);
                bl_info = match_json(m);
                bool skip = m.action >= Action::Cpu || (m.action == Action::GpuFp32 && b.fp16);
                bool quar = store.quarantined(rec);
                if ((skip || quar) && !a.has("--ignore-blocklist")) {
                    results.push_back({{"backend", bname}, {"model", ms.id}, {"gpu_index", b.gpu},
                                       {"status", quar ? "skipped_quarantine" : "skipped_blocklist"},
                                       {"blocklist", bl_info}});
                    std::fprintf(stderr, "[probe] %-9s %-26s skipped (%s)\n", bname.c_str(), ms.id.c_str(),
                                 quar ? "quarantine" : action_name(m.action));
                    continue;
                }
                store.arm(rec);
            }
            std::string crash = bname == a.get("--crash-backend") ? a.get("--crash", "abort") : "";
            std::string corrupt = corrupt_for(a, bname);
            if (isolate) {
                std::string jo = work + "/child-" + model + "-" + bname + ".json";
                std::vector<std::string> av = {exe, "bench-one", "--model", model, "--backend", bname,
                                               "--runs", std::to_string(model == "face" ? face_runs : runs),
                                               "--warmup", std::to_string(warmup), "--json-out", jo,
                                               "--sr-param", paths.sr_param, "--sr-bin", paths.sr_bin,
                                               "--sr-in", paths.sr_in, "--sr-golden", paths.sr_golden,
                                               "--face-param", paths.face_param, "--face-bin", paths.face_bin,
                                               "--face-in", paths.face_in, "--face-golden", paths.face_golden};
                if (a.has("--threads")) { av.push_back("--threads"); av.push_back(a.get("--threads")); }
                if (a.has("--max-run-ms")) { av.push_back("--max-run-ms"); av.push_back(a.get("--max-run-ms")); }
                if (a.has("--min-psnr")) { av.push_back("--min-psnr"); av.push_back(a.get("--min-psnr")); }
                if (a.has("--max-bad-frac")) { av.push_back("--max-bad-frac"); av.push_back(a.get("--max-bad-frac")); }
                if (!corrupt.empty()) { av.push_back("--corrupt"); av.push_back(corrupt); }
                if (!crash.empty()) { av.push_back("--crash"); av.push_back(crash); }
                ChildResult cr = spawn_child(av, timeout_s, jo);
                if (cr.result.is_object()) {
                    r = cr.result;
                } else {
                    r = {{"backend", bname}, {"model", ms.id}, {"gpu_index", b.gpu}};
                    if (cr.timeout) {
                        r["status"] = "timeout";
                        r["error"] = "no result after " + std::to_string(timeout_s) + " s (GPU hang?)";
                    } else if (cr.signal) {
                        r["status"] = "crash";
                        r["error"] = std::string("killed by signal ") + std::to_string(cr.signal) + " (" +
                                     strsignal(cr.signal) + ")";
                    } else {
                        r["status"] = "error";
                        r["error"] = "child exited with code " + std::to_string(cr.exit_code) + " and no result";
                    }
                }
                r["wall_ms"] = cr.wall_ms;
                r["peak_rss_mb"] = cr.maxrss_kb / 1024.0;
                if (b.gpu >= 0) {
                    if (r["status"] == "crash" || r["status"] == "timeout") {
                        store.record_confirmed_crash(rec, r["error"].get<std::string>());
                        r["sentinel"] = "confirmed crash -> local blocklist (driver+model pinned)";
                    } else {
                        store.disarm(rec);
                    }
                }
            } else {
                BenchConfig cfg;
                cfg.threads = a.geti("--threads", 0);
                cfg.warmup = warmup;
                cfg.runs = model == "face" ? face_runs : runs;
                cfg.corrupt = corrupt;
                cfg.gate = gate_from(a);
                if (!crash.empty()) crash_now(crash);  // sentinel stays on disk -> next start
                auto t0 = std::chrono::steady_clock::now();
                r = run_bench(ms, b, cfg);
                r["wall_ms"] = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
                if (b.gpu >= 0) store.disarm(rec);
            }
            r["blocklist"] = bl_info;
            if (b.gpu >= 0 && r.value("status", "") == "wrong_output" && a.has("--record-wrong-output")) {
                // benchmark failure -> local rule (05 §11 "провал бенчмарка"); key = driver + model
                SentinelRecord rr = rec;
                // fp16 garbage -> keep the GPU in fp32 (re-verified by the fp32 backend of this probe);
                // fp32 garbage -> CPU. "Strongest wins" merges both if both fail.
                Action act = b.fp16 ? Action::GpuFp32 : Action::Cpu;
                store.record_confirmed_crash(rr, "benchmark wrong_output: " + r.value("reason", ""), act);
                r["sentinel"] = std::string("wrong_output -> local blocklist, action ") + action_name(act);
            }
            std::fprintf(stderr, "[probe] %-9s %-26s %-12s median %8.1f ms  tile128 %7.1f ms  PSNR %6.2f dB  load %7.1f ms\n",
                         bname.c_str(), ms.id.c_str(), r.value("status", "?").c_str(), r.value("median_ms", 0.0),
                         r.value("tile128_median_ms", 0.0), r.value("psnr_db", 0.0), r.value("load_ms", 0.0));
            results.push_back(r);
        }
    }

    // ---- summary
    TierThresholds th;
    th.t2_tile128_ms = a.getd("--t2-ms", th.t2_tile128_ms);
    th.t1_tile128_ms = a.getd("--t1-ms", th.t1_tile128_ms);
    th.t0_tile128_ms = a.getd("--t0-ms", th.t0_tile128_ms);
    th.require_soc_for_t2 = a.has("--require-soc-for-t2");
    std::string best;
    double best_ms = 1e30;
    bool best_gpu = false;
    json healthy = json::array(), per_backend_tier = json::object();
    int soc_t2 = soc_in_t2_list(host.soc);
    for (auto& r : results) {
        if (r.value("model", "").rfind(kSrId, 0) != 0 || r.value("status", "") != "ok") continue;
        healthy.push_back(r["backend"]);
        double ms = r.value("tile128_median_ms", r.value("median_ms", 1e30));
        TierInput ti{host.ram_gb, r["backend"], r.value("gpu_index", -1) >= 0, ms, soc_t2};
        per_backend_tier[r["backend"].get<std::string>()] = suggest_tier(ti, th).tier;
        if (ms < best_ms) {
            best_ms = ms;
            best = r["backend"];
            best_gpu = r.value("gpu_index", -1) >= 0;
        }
    }
    TierInput ti{host.ram_gb, best, best_gpu, best_ms, soc_t2};
    TierDecision td = suggest_tier(ti, th);
    bool sr_ran = false;
    for (auto& r : results) sr_ran |= r.value("model", "").rfind(kSrId, 0) == 0;
    if (!sr_ran) td = {"n/a", {"compact SR not benchmarked (--face-only)"}, false};
    json routing = json::object();
    for (auto& model : {std::string(kSrId), std::string(kFaceId)}) {
        std::string rb;
        double rms = 1e30;
        for (auto& r : results) {
            if (r.value("model", "").rfind(model, 0) != 0 || r.value("status", "") != "ok") continue;
            double ms = r.value("median_ms", 1e30);
            if (ms < rms) { rms = ms; rb = r["backend"]; }
        }
        if (!rb.empty()) routing[model] = {{"backend", rb}, {"median_ms", rms}};
    }
    double wall = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t_start).count();
    json report = {
        {"schema", "refocal-probe/1"},
        {"probe_version", kProbeVersion},
        {"ncnn_version", NCNN_VERSION_STRING},
        {"timestamp", iso_now()},
        {"host", to_json(host)},
        {"gpus", json::array()},
        {"config", {{"runs", runs}, {"face_runs", face_runs}, {"warmup", warmup}, {"isolate", isolate},
                    {"gate", {{"min_psnr", gate_from(a).min_psnr}, {"max_bad_frac", gate_from(a).max_bad_frac},
                              {"bad_level_u8", gate_from(a).bad_level}}},
                    {"thresholds", {{"t0_ram_gb", th.t0_ram_gb}, {"t2_ram_gb", th.t2_ram_gb},
                                    {"t2_tile128_ms", th.t2_tile128_ms}, {"t1_tile128_ms", th.t1_tile128_ms},
                                    {"t0_tile128_ms", th.t0_tile128_ms}, {"require_soc_for_t2", th.require_soc_for_t2}}},
                    {"face_model", paths.face_param}}},
        {"blocklist_sources", sources},
        {"sentinel_startup", {{"found", st.sentinel_found}, {"key", st.key}, {"exit_reason", exit_reason_name(st.reason)},
                              {"hits", st.hits}, {"blocked_now", st.blocked_now},
                              {"quarantined_now", st.quarantined_now}, {"note", st.note}}},
        {"results", results},
        {"summary", {{"healthy_sr_backends", healthy},
                     {"selected_backend", best},
                     {"selected_tile128_ms", best.empty() ? json() : json(best_ms)},
                     {"soc_in_t2_list", soc_t2},
                     {"tier", td.tier},
                     {"tier_reasons", td.reasons},
                     {"below_t0_budget", td.below_t0_budget},
                     {"tier_if_only_backend", per_backend_tier},
                     {"routing", routing},
                     {"probe_wall_ms", wall}}}};
    for (auto& g : gpus) report["gpus"].push_back(to_json(g));
    std::string out = a.get("--out", work + "/report.json");
    write_file_atomic(out, report.dump(2) + "\n");
    std::fprintf(stderr, "[probe] tier %s via %s; report: %s\n", td.tier.c_str(), best.empty() ? "-" : best.c_str(),
                 out.c_str());
    return 0;
}

// ---------------------------------------------------------------- stage (app simulation)
int cmd_stage(const Args& a) {
    SentinelPolicy pol;
    pol.block_after = a.geti("--block-after", 2);
    pol.quarantine_first_hit = !a.has("--no-quarantine");
    SentinelStore store(a.get("--state-dir", "probe-out/state"), pol);
    StartupReport st = store.on_startup(parse_exit_reason(a.get("--exit-reason", "unknown")));
    std::vector<GpuDesc> gpus = probe_gpus();
    int gpu = a.geti("--gpu", 0);
    std::string model_id = a.get("--model-id", kSrId);
    bool fp16 = !a.has("--fp32");
    Blocklist bl = build_blocklist(a, &store, nullptr);

    SentinelRecord rec;
    rec.gpu = gpu_identity(gpus, gpu);
    rec.model = model_id;
    rec.tile = a.geti("--tile", 256);
    MatchResult m = bl.match(rec.gpu, model_id);
    std::string backend, why;
    if (gpu >= (int)gpus.size()) {
        backend = fp16 ? "cpu-fp16" : "cpu-fp32";
        why = "no such GPU";
    } else if (m.action == Action::Disable) {
        backend = "disabled";
        why = "blocklist: disable";
    } else if (m.action == Action::Cpu) {
        backend = "cpu-fp16";
        why = "blocklist: cpu";
    } else if (store.quarantined(rec)) {
        backend = "cpu-fp16";
        why = "sentinel quarantine (first hit, this session only)";
    } else if (m.action == Action::GpuFp32) {
        backend = "vk" + std::to_string(gpu) + "-fp32";
        why = "blocklist: gpu_fp32";
    } else {
        backend = "vk" + std::to_string(gpu) + (fp16 ? "-fp16" : "-fp32");
        why = "gpu allowed";
    }
    rec.backend = backend;
    json out = {{"startup", {{"found", st.sentinel_found}, {"key", st.key}, {"exit_reason", exit_reason_name(st.reason)},
                             {"hits", st.hits}, {"blocked_now", st.blocked_now}, {"quarantined_now", st.quarantined_now},
                             {"note", st.note}}},
                {"gpu", rec.gpu.device_name},
                {"driver", format_driver_version(rec.gpu.vendor_id, rec.gpu.driver_version)},
                {"model", model_id},
                {"backend", backend},
                {"why", why},
                {"blocklist", match_json(m)},
                {"hits_now", store.hits(rec)}};
    BackendSpec b;
    bool is_gpu = parse_backend(backend, b) && b.gpu >= 0;
    std::printf("%s\n", out.dump().c_str());
    std::fflush(stdout);
    if (backend == "disabled" || a.has("--no-run")) return 0;
    Paths p = resolve_paths(a);
    ModelSpec ms = model_id.rfind("face.", 0) == 0 ? face_spec(p) : sr_spec(p);
    ms.tile128 = false;
    BenchConfig cfg;
    cfg.runs = 1;
    cfg.warmup = 0;
    if (is_gpu) store.arm(rec);
    if (a.has("--crash") && is_gpu) {
        run_bench(ms, b, cfg);  // real GPU work first ...
        crash_now(a.get("--crash"));  // ... then die mid-stage, sentinel stays on disk
    }
    json r = run_bench(ms, b, cfg);
    if (is_gpu) store.disarm(rec);
    std::fprintf(stderr, "[stage] %s %s -> %s PSNR %.2f\n", model_id.c_str(), backend.c_str(),
                 r.value("status", "?").c_str(), r.value("psnr_db", 0.0));
    return 0;
}

// ---------------------------------------------------------------- match (offline rule check)
int cmd_match(const Args& a) {
    GpuIdentity g;
    g.vendor_id = (uint32_t)std::stoul(a.get("--vendor-id", "0"), nullptr, 0);
    g.device_name = a.get("--device-name");
    if (a.has("--driver-raw")) g.driver_version = (uint32_t)std::stoul(a.get("--driver-raw"), nullptr, 0);
    if (a.has("--api-raw")) g.api_version = (uint32_t)std::stoul(a.get("--api-raw"), nullptr, 0);
    g.platform = a.get("--platform", "android");
    g.os_version = a.get("--os-version");
    json sources = json::array();
    Blocklist bl = build_blocklist(a, nullptr, &sources);
    MatchResult m = bl.match(g, a.get("--model-id", kSrId));
    json out = {{"gpu", g.device_name}, {"vendor", vendor_name(g.vendor_id)},
                {"driver", format_driver_version(g.vendor_id, g.driver_version, g.platform)},
                {"match", match_json(m)}, {"sources", sources}};
    std::printf("%s\n", out.dump(2).c_str());
    return 0;
}

int cmd_calib(const Args& a) {
    Paths p = resolve_paths(a);
    BackendSpec b;
    if (!parse_backend(a.get("--backend", "cpu-fp16"), b)) return 2;
    json r = run_tiled(sr_spec(p), b, a.geti("--threads", 0), 1152, 864, a.geti("--tile", 128), 16);
    std::printf("%s\n", r.dump().c_str());
    return 0;
}

int cmd_info() {
    json j = {{"host", to_json(probe_host())}, {"gpus", json::array()}, {"ncnn_version", NCNN_VERSION_STRING}};
    for (auto& g : probe_gpus()) j["gpus"].push_back(to_json(g));
    std::printf("%s\n", j.dump(2).c_str());
    return 0;
}

void usage() {
    std::fprintf(stderr,
                 "refocal-probe %s\n"
                 "  info                               device/driver info (JSON)\n"
                 "  probe [--face] [--face-model gfpgan14s|gfpgan14] [--backends vk0-fp16,cpu-fp16,...]\n"
                 "        [--runs 5] [--face-runs 3] [--data DIR] [--blocklist FILE]... [--work-dir DIR]\n"
                 "        [--corrupt BACKEND:MODE] [--crash-backend B [--crash abort|segv]] [--no-isolate]\n"
                 "        [--ignore-blocklist] [--record-wrong-output] [--out report.json]\n"
                 "  stage --state-dir DIR --gpu N --model-id ID [--crash abort|segv] [--exit-reason R]\n"
                 "        [--no-quarantine] [--block-after 2] [--blocklist FILE]... [--no-run]\n"
                 "  match --vendor-id 0x13B5 --device-name NAME --driver-raw 0x... [--os-version 34]\n"
                 "        --model-id ID [--blocklist FILE]...\n",
                 kProbeVersion);
}

}  // namespace

int main(int argc, char** argv) {
    Args a = parse_args(argc, argv);
    if (a.cmd == "info") return cmd_info();
    if (a.cmd == "probe") return cmd_probe(a);
    if (a.cmd == "bench-one") return cmd_bench_one(a);
    if (a.cmd == "stage") return cmd_stage(a);
    if (a.cmd == "match") return cmd_match(a);
    if (a.cmd == "calib") return cmd_calib(a);
    usage();
    return a.cmd.empty() || a.cmd == "help" || a.cmd == "--help" ? 0 : 2;
}
