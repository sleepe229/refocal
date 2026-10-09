// S2 spike: streaming 12 MP -> x4 (192 MP) SR through an on-disk BandStore.
//
// Pipeline: decode JPEG (RGB8, held in memory) -> [fast2: area /2] -> tiled SR
// (one band = one row of tiles) -> [x2: area /2 per band] -> BandStore band file
// (raw RGB8 or LZ4) + fsync + checkpoint.json -> incremental preview (area accumulate)
// -> final JPEG/PNG export streamed band by band from the BandStore.
//
// The full output image is never held in memory.

#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <csetjmp>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

#include <malloc.h>

#include <jpeglib.h>
#include <lz4.h>
#include <png.h>

#include "gpu.h"
#include "net.h"
#include "sha256.h"

#ifndef S2_DEFAULT_MODEL
#define S2_DEFAULT_MODEL "sr_compact_dn050"
#endif

// ----------------------------------------------------------------------------
// Utilities
// ----------------------------------------------------------------------------

using Clock = std::chrono::steady_clock;
static double now_s() {
  return std::chrono::duration<double>(Clock::now().time_since_epoch()).count();
}
static const double g_t0 = now_s();

[[noreturn]] static void die(const char* fmt, ...) __attribute__((format(printf, 1, 2)));
static void die(const char* fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  fprintf(stderr, "s2_stream: error: ");
  vfprintf(stderr, fmt, ap);
  fprintf(stderr, "\n");
  va_end(ap);
  exit(2);
}

static void logf(const char* fmt, ...) __attribute__((format(printf, 1, 2)));
static void logf(const char* fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  fprintf(stderr, "[%8.3f] ", now_s() - g_t0);
  vfprintf(stderr, fmt, ap);
  fprintf(stderr, "\n");
  va_end(ap);
}

// /proc/self/status field in kB.
static long proc_status_kb(const char* key) {
  FILE* f = fopen("/proc/self/status", "r");
  if (!f) return -1;
  char line[256];
  long v = -1;
  size_t kl = strlen(key);
  while (fgets(line, sizeof(line), f)) {
    if (strncmp(line, key, kl) == 0 && line[kl] == ':') {
      v = atol(line + kl + 1);
      break;
    }
  }
  fclose(f);
  return v;
}
// Resets VmHWM to current RSS (Linux >= 4.0), so per-stage peaks can be measured.
static void reset_hwm() {
  int fd = open("/proc/self/clear_refs", O_WRONLY);
  if (fd >= 0) {
    if (write(fd, "5", 1) != 1) { /* ignore */ }
    close(fd);
  }
}

// Sum of DRM-reported resident GPU memory of this process (i915 fdinfo, kB). On an integrated
// GPU these are system-RAM pages that VmRSS does not (fully) include; a unified-memory OS
// (iOS phys_footprint) would count them. Returns 0 when not available (e.g. NVIDIA).
static long drm_resident_kb() {
  long total = 0;
  DIR* d = opendir("/proc/self/fdinfo");
  if (!d) return 0;
  std::vector<long> seen;
  while (dirent* e = readdir(d)) {
    if (e->d_name[0] == '.') continue;
    std::string p = std::string("/proc/self/fdinfo/") + e->d_name;
    FILE* f = fopen(p.c_str(), "r");
    if (!f) continue;
    char line[256];
    long client = -1, res = 0;
    bool drm = false;
    while (fgets(line, sizeof(line), f)) {
      if (strncmp(line, "drm-client-id:", 14) == 0) { client = atol(line + 14); drm = true; }
      else if (strncmp(line, "drm-resident-", 13) == 0) {
        const char* c = strchr(line, ':');
        if (c) {
          long v = atol(c + 1);
          if (strstr(c, "MiB")) v *= 1024;
          else if (!strstr(c, "KiB")) v /= 1024;
          res += v;
        }
      }
    }
    fclose(f);
    if (drm && std::find(seen.begin(), seen.end(), client) == seen.end()) {
      seen.push_back(client);
      total += res;
    }
  }
  closedir(d);
  return total;
}
static long g_drm_peak_kb = 0;
static long g_combined_peak_kb = 0;  // max over samples of VmRSS + DRM resident
static void sample_drm() {
  long dkb = drm_resident_kb();
  long rss = proc_status_kb("VmRSS");
  g_drm_peak_kb = std::max(g_drm_peak_kb, dkb);
  g_combined_peak_kb = std::max(g_combined_peak_kb, rss + dkb);
}

static void fsync_dir(const std::string& dir) {
  int fd = open(dir.c_str(), O_RDONLY | O_DIRECTORY);
  if (fd >= 0) {
    fsync(fd);
    close(fd);
  }
}

static void mkdirs(const std::string& path) {
  std::string cur;
  for (size_t i = 0; i < path.size(); ++i) {
    cur.push_back(path[i]);
    if (path[i] == '/' || i + 1 == path.size()) mkdir(cur.c_str(), 0755);
  }
}

static bool file_exists(const std::string& p) {
  struct stat st;
  return stat(p.c_str(), &st) == 0;
}
static long long file_size(const std::string& p) {
  struct stat st;
  if (stat(p.c_str(), &st) != 0) return -1;
  return st.st_size;
}
static long long file_disk_bytes(const std::string& p) {
  struct stat st;
  if (stat(p.c_str(), &st) != 0) return -1;
  return (long long)st.st_blocks * 512;
}

// Writes the full buffer, then fsyncs (optional), closes, and atomically renames.
static void write_file_atomic(const std::string& path, const void* data, size_t n, bool do_fsync) {
  std::string tmp = path + ".tmp";
  int fd = open(tmp.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
  if (fd < 0) die("open %s: %s", tmp.c_str(), strerror(errno));
  const uint8_t* p = static_cast<const uint8_t*>(data);
  size_t left = n;
  while (left > 0) {
    ssize_t w = write(fd, p, left);
    if (w < 0) {
      if (errno == EINTR) continue;
      die("write %s: %s", tmp.c_str(), strerror(errno));
    }
    p += w;
    left -= size_t(w);
  }
  if (do_fsync && fsync(fd) != 0) die("fsync %s: %s", tmp.c_str(), strerror(errno));
  close(fd);
  if (rename(tmp.c_str(), path.c_str()) != 0) die("rename %s: %s", tmp.c_str(), strerror(errno));
}

static std::vector<uint8_t> read_file(const std::string& path) {
  std::vector<uint8_t> v;
  FILE* f = fopen(path.c_str(), "rb");
  if (!f) die("open %s: %s", path.c_str(), strerror(errno));
  fseek(f, 0, SEEK_END);
  long n = ftell(f);
  fseek(f, 0, SEEK_SET);
  v.resize(size_t(n));
  if (n > 0 && fread(v.data(), 1, size_t(n), f) != size_t(n)) die("read %s", path.c_str());
  fclose(f);
  return v;
}

// ----------------------------------------------------------------------------
// Stats
// ----------------------------------------------------------------------------

struct Stats {
  std::mutex mu;
  std::map<std::string, double> t;          // accumulated seconds per stage
  std::vector<std::pair<std::string, long>> hwm_log;  // (label, VmHWM kB) at boundaries
  std::map<std::string, long> stage_peak_kb;  // per-stage peak (HWM reset at stage start)
  std::map<std::string, double> num;          // misc numbers
  std::map<std::string, std::string> str;
  void add(const std::string& k, double s) {
    std::lock_guard<std::mutex> g(mu);
    t[k] += s;
  }
  void mark(const std::string& label) {
    long hwm = proc_status_kb("VmHWM");
    long rss = proc_status_kb("VmRSS");
    std::lock_guard<std::mutex> g(mu);
    hwm_log.push_back({label, hwm});
    logf("mem[%s] VmHWM=%.1f MB VmRSS=%.1f MB", label.c_str(), hwm / 1024.0, rss / 1024.0);
  }
};
static Stats g_stats;
static long g_global_peak_kb = 0;  // max over all stage peaks (HWM is reset per stage)

struct ScopedTimer {
  std::string k;
  double t0;
  explicit ScopedTimer(std::string key) : k(std::move(key)), t0(now_s()) {}
  ~ScopedTimer() { g_stats.add(k, now_s() - t0); }
};

// Stage boundary: record the peak of the stage that just ended, then reset HWM.
static void stage_end(const std::string& stage) {
  sample_drm();
  long hwm = proc_status_kb("VmHWM");
  long rss = proc_status_kb("VmRSS");
  {
    std::lock_guard<std::mutex> g(g_stats.mu);
    g_stats.stage_peak_kb[stage] = std::max(g_stats.stage_peak_kb[stage], hwm);
    g_stats.hwm_log.push_back({stage, hwm});
  }
  g_global_peak_kb = std::max(g_global_peak_kb, hwm);
  logf("stage %-14s peak VmHWM=%7.1f MB, now VmRSS=%7.1f MB", stage.c_str(), hwm / 1024.0,
       rss / 1024.0);
  reset_hwm();
}

// ----------------------------------------------------------------------------
// Args
// ----------------------------------------------------------------------------

struct Args {
  std::string input;
  std::string job = "job";
  std::string model = S2_DEFAULT_MODEL;  // prefix: <model>.ncnn.param / .bin
  int tile = 256;     // core tile size in input px (network input = tile + 2*pad); 0 = whole image
  int pad = 16;       // input px
  int feather = 0;    // output px (0 = off, 8 = spec default)
  std::string scale = "4";  // 4 | 2 | fast2
  std::string backend = "cpu";  // cpu | vkN
  int threads = 8;
  bool fp16 = true;   // fp16 storage (CPU) / fp16 storage+arith (Vulkan)
  bool lz4 = false;
  int lz4_accel = 1;
  bool resume = false;
  bool sync_io = false;
  bool do_fsync = true;
  std::string out_jpeg, out_png, out_preview;
  int jpeg_q = 92;
  int png_level = 6;
  int preview_max = 2048;
  std::string stats_json;
  bool keep_job = true;
  bool drop_cache = false;  // evict band files from the page cache after commit (cold export reads)
};

static void usage() {
  fprintf(stderr,
          "usage: s2_stream --input in.jpg [options]\n"
          "  --job DIR            BandStore job dir (default: job)\n"
          "  --model PREFIX       ncnn model prefix (default: %s)\n"
          "  --tile T             core tile, input px (128/256/512; 0 = whole image, no tiling)\n"
          "  --pad P              tile padding, input px (default 16)\n"
          "  --feather F          linear feather width on tile seams, output px (default 0)\n"
          "  --scale 4|2|fast2    x4; x4 + area /2 per band; input /2 then x4\n"
          "  --backend cpu|vkN    ncnn CPU or Vulkan device N\n"
          "  --threads N          CPU threads (default 8)\n"
          "  --fp16 0|1           fp16 storage (default 1)\n"
          "  --lz4                LZ4-compress band files\n"
          "  --sync-io            write bands synchronously (no overlap with inference)\n"
          "  --no-fsync           skip fsync (for I/O cost comparison only)\n"
          "  --drop-cache         evict band files from page cache after commit (cold reads)\n"
          "  --resume             continue an interrupted job from checkpoint.json\n"
          "  --out-jpeg F --out-png F --out-preview F\n"
          "  --jpeg-q Q (92) --png-level L (6) --preview-max N (2048)\n"
          "  --stats F            write JSON stats\n",
          S2_DEFAULT_MODEL);
}

static Args parse_args(int argc, char** argv) {
  Args a;
  for (int i = 1; i < argc; ++i) {
    std::string k = argv[i];
    auto next = [&]() -> std::string {
      if (i + 1 >= argc) die("missing value for %s", k.c_str());
      return argv[++i];
    };
    if (k == "--input") a.input = next();
    else if (k == "--job") a.job = next();
    else if (k == "--model") a.model = next();
    else if (k == "--tile") a.tile = std::stoi(next());
    else if (k == "--pad") a.pad = std::stoi(next());
    else if (k == "--feather") a.feather = std::stoi(next());
    else if (k == "--scale") a.scale = next();
    else if (k == "--backend") a.backend = next();
    else if (k == "--threads") a.threads = std::stoi(next());
    else if (k == "--fp16") a.fp16 = std::stoi(next()) != 0;
    else if (k == "--lz4") a.lz4 = true;
    else if (k == "--lz4-accel") a.lz4_accel = std::stoi(next());
    else if (k == "--sync-io") a.sync_io = true;
    else if (k == "--no-fsync") a.do_fsync = false;
    else if (k == "--resume") a.resume = true;
    else if (k == "--drop-cache") a.drop_cache = true;
    else if (k == "--out-jpeg") a.out_jpeg = next();
    else if (k == "--out-png") a.out_png = next();
    else if (k == "--out-preview") a.out_preview = next();
    else if (k == "--jpeg-q") a.jpeg_q = std::stoi(next());
    else if (k == "--png-level") a.png_level = std::stoi(next());
    else if (k == "--preview-max") a.preview_max = std::stoi(next());
    else if (k == "--stats") a.stats_json = next();
    else if (k == "-h" || k == "--help") { usage(); exit(0); }
    else { usage(); die("unknown option %s", k.c_str()); }
  }
  if (a.input.empty()) { usage(); die("--input is required"); }
  if (a.scale != "4" && a.scale != "2" && a.scale != "fast2") die("bad --scale");
  if (a.tile == 0) a.pad = 0;
  if (a.feather < 0 || a.feather > 4 * a.pad) die("--feather must be in [0, 4*pad]");
  return a;
}

// ----------------------------------------------------------------------------
// Image I/O
// ----------------------------------------------------------------------------

struct Rgb8 {
  int w = 0, h = 0;
  std::vector<uint8_t> px;  // w*h*3
};

struct JpegErr {
  jpeg_error_mgr pub;
  jmp_buf jb;
};
static void jpeg_err_exit(j_common_ptr c) {
  JpegErr* e = reinterpret_cast<JpegErr*>(c->err);
  char msg[JMSG_LENGTH_MAX];
  (*c->err->format_message)(c, msg);
  fprintf(stderr, "libjpeg: %s\n", msg);
  longjmp(e->jb, 1);
}

static Rgb8 decode_jpeg(const std::string& path) {
  FILE* f = fopen(path.c_str(), "rb");
  if (!f) die("open %s", path.c_str());
  jpeg_decompress_struct cinfo;
  JpegErr jerr;
  cinfo.err = jpeg_std_error(&jerr.pub);
  jerr.pub.error_exit = jpeg_err_exit;
  if (setjmp(jerr.jb)) die("jpeg decode failed: %s", path.c_str());
  jpeg_create_decompress(&cinfo);
  jpeg_stdio_src(&cinfo, f);
  jpeg_read_header(&cinfo, TRUE);
  cinfo.out_color_space = JCS_RGB;
  jpeg_start_decompress(&cinfo);
  Rgb8 img;
  img.w = int(cinfo.output_width);
  img.h = int(cinfo.output_height);
  img.px.resize(size_t(img.w) * img.h * 3);
  while (cinfo.output_scanline < cinfo.output_height) {
    JSAMPROW row = img.px.data() + size_t(cinfo.output_scanline) * img.w * 3;
    jpeg_read_scanlines(&cinfo, &row, 1);
  }
  jpeg_finish_decompress(&cinfo);
  jpeg_destroy_decompress(&cinfo);
  fclose(f);
  return img;
}

// Area (box) downscale by 2 of `rows` rows of RGB8 (rows even), width w -> w/2.
static void area_down2(const uint8_t* src, int w, int rows, uint8_t* dst) {
  int ow = w / 2;
  for (int y = 0; y < rows / 2; ++y) {
    const uint8_t* r0 = src + size_t(2 * y) * w * 3;
    const uint8_t* r1 = r0 + size_t(w) * 3;
    uint8_t* d = dst + size_t(y) * ow * 3;
    for (int x = 0; x < ow; ++x) {
      for (int c = 0; c < 3; ++c) {
        int s = r0[(2 * x) * 3 + c] + r0[(2 * x + 1) * 3 + c] + r1[(2 * x) * 3 + c] +
                r1[(2 * x + 1) * 3 + c];
        d[x * 3 + c] = uint8_t((s + 2) >> 2);
      }
    }
  }
}

// JPEG encoder fed row by row.
struct JpegWriter {
  jpeg_compress_struct cinfo;
  JpegErr jerr;
  FILE* f = nullptr;
  void open(const std::string& path, int w, int h, int q) {
    f = fopen(path.c_str(), "wb");
    if (!f) die("open %s", path.c_str());
    cinfo.err = jpeg_std_error(&jerr.pub);
    jerr.pub.error_exit = jpeg_err_exit;
    if (setjmp(jerr.jb)) die("jpeg encode failed");
    jpeg_create_compress(&cinfo);
    jpeg_stdio_dest(&cinfo, f);
    cinfo.image_width = JDIMENSION(w);
    cinfo.image_height = JDIMENSION(h);
    cinfo.input_components = 3;
    cinfo.in_color_space = JCS_RGB;
    jpeg_set_defaults(&cinfo);
    jpeg_set_quality(&cinfo, q, TRUE);
    jpeg_start_compress(&cinfo, TRUE);
  }
  void rows(const uint8_t* data, int n, int w) {
    if (setjmp(jerr.jb)) die("jpeg encode failed");
    for (int i = 0; i < n; ++i) {
      JSAMPROW r = const_cast<uint8_t*>(data + size_t(i) * w * 3);
      jpeg_write_scanlines(&cinfo, &r, 1);
    }
  }
  void close() {
    jpeg_finish_compress(&cinfo);
    jpeg_destroy_compress(&cinfo);
    fclose(f);
  }
};

static void write_jpeg_whole(const std::string& path, const uint8_t* px, int w, int h, int q) {
  JpegWriter jw;
  jw.open(path, w, h, q);
  jw.rows(px, h, w);
  jw.close();
}

struct PngWriter {
  png_structp png = nullptr;
  png_infop info = nullptr;
  FILE* f = nullptr;
  void open(const std::string& path, int w, int h, int level) {
    f = fopen(path.c_str(), "wb");
    if (!f) die("open %s", path.c_str());
    png = png_create_write_struct(PNG_LIBPNG_VER_STRING, nullptr, nullptr, nullptr);
    info = png_create_info_struct(png);
    if (setjmp(png_jmpbuf(png))) die("png encode failed");
    png_init_io(png, f);
    png_set_compression_level(png, level);
    png_set_IHDR(png, info, png_uint_32(w), png_uint_32(h), 8, PNG_COLOR_TYPE_RGB,
                 PNG_INTERLACE_NONE, PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT);
    png_write_info(png, info);
  }
  void rows(const uint8_t* data, int n, int w) {
    if (setjmp(png_jmpbuf(png))) die("png encode failed");
    for (int i = 0; i < n; ++i) png_write_row(png, data + size_t(i) * w * 3);
  }
  void close() {
    png_write_end(png, nullptr);
    png_destroy_write_struct(&png, &info);
    fclose(f);
  }
};

// ----------------------------------------------------------------------------
// Geometry
// ----------------------------------------------------------------------------

// Tile origins along one axis: fixed tile size t, last tile shifted inward.
static std::vector<int> tile_origins(int n, int t) {
  std::vector<int> o;
  if (t >= n) {
    o.push_back(0);
    return o;
  }
  for (int x = 0; x + t < n; x += t) o.push_back(x);
  o.push_back(n - t);
  return o;
}
// Owned (non-overlapping) span start of tile i.
static int owned_start(const std::vector<int>& o, int i, int t) { return i == 0 ? 0 : o[i - 1] + t; }

static inline int reflect101(int i, int n) {
  if (n == 1) return 0;
  while (i < 0 || i >= n) {
    if (i < 0) i = -i;
    if (i >= n) i = 2 * n - 2 - i;
  }
  return i;
}

struct Geometry {
  int in_w, in_h;    // SR input (after fast2 downscale)
  int tw, th;        // tile core size (fixed)
  int pad;
  int sr_w, sr_h;    // x4 output
  int down;          // 1 or 2 (x2 mode)
  int out_w, out_h;  // stored / exported image
  std::vector<int> xs, ys;
  int bands() const { return int(ys.size()); }
  int band_in_y0(int b) const { return owned_start(ys, b, th); }
  int band_in_y1(int b) const { return b + 1 < bands() ? owned_start(ys, b + 1, th) : in_h; }
  int band_out_rows(int b) const { return 4 * (band_in_y1(b) - band_in_y0(b)) / down; }
};

// ----------------------------------------------------------------------------
// Inference backend (ncnn)
// ----------------------------------------------------------------------------

struct Backend {
  ncnn::Net net;
  bool vulkan = false;
  int device = -1;
  std::string name;
  void init(const Args& a) {
    if (a.backend.rfind("vk", 0) == 0) {
      vulkan = true;
      device = std::stoi(a.backend.substr(2));
      if (device >= ncnn::get_gpu_count()) die("vulkan device %d not available", device);
      net.set_vulkan_device(device);
      name = std::string("vulkan:") + ncnn::get_gpu_info(device).device_name();
    } else if (a.backend == "cpu") {
      name = "cpu";
    } else {
      die("bad --backend %s", a.backend.c_str());
    }
    net.opt.use_vulkan_compute = vulkan;
    net.opt.num_threads = a.threads;
    net.opt.lightmode = true;
    net.opt.use_fp16_storage = a.fp16;
    net.opt.use_fp16_packed = a.fp16;
    net.opt.use_fp16_arithmetic = vulkan && a.fp16;
    net.opt.use_bf16_storage = false;
    std::string param = a.model + ".ncnn.param", bin = a.model + ".ncnn.bin";
    if (net.load_param(param.c_str()) != 0) die("load_param %s", param.c_str());
    if (net.load_model(bin.c_str()) != 0) die("load_model %s", bin.c_str());
  }
  void run(const ncnn::Mat& in, ncnn::Mat& out) {
    ncnn::Extractor ex = net.create_extractor();
    ex.input("in0", in);
    if (ex.extract("out0", out) != 0) die("ncnn extract failed");
  }
};

// ----------------------------------------------------------------------------
// BandStore writer (async, depth 1 => at most 2 bands in RAM)
// ----------------------------------------------------------------------------

struct BandJob {
  int idx = -1;
  std::vector<uint8_t> data;  // rows * out_w * 3
  std::vector<uint8_t> tail;  // feather tail (x4 resolution), may be empty
};

struct Checkpoint {
  int band_idx = -1;
  int bands_total = 0;
  std::string recipe_hash, model_sha256, input_sha256, backend, format, scale;
  int tile = 0, pad = 0, feather = 0, out_w = 0, out_h = 0;
};

static std::string checkpoint_json(const Checkpoint& c) {
  char buf[2048];
  snprintf(buf, sizeof(buf),
           "{\n  \"version\": 1,\n  \"band_idx\": %d,\n  \"bands_total\": %d,\n"
           "  \"recipe_hash\": \"%s\",\n  \"model_sha256\": \"%s\",\n  \"input_sha256\": \"%s\",\n"
           "  \"backend\": \"%s\",\n  \"tile\": %d,\n  \"pad\": %d,\n  \"feather\": %d,\n"
           "  \"scale\": \"%s\",\n  \"format\": \"%s\",\n  \"out_w\": %d,\n  \"out_h\": %d\n}\n",
           c.band_idx, c.bands_total, c.recipe_hash.c_str(), c.model_sha256.c_str(),
           c.input_sha256.c_str(), c.backend.c_str(), c.tile, c.pad, c.feather, c.scale.c_str(),
           c.format.c_str(), c.out_w, c.out_h);
  return buf;
}

// Tiny extractor for our own flat JSON.
static std::string json_get(const std::string& js, const std::string& key) {
  std::string k = "\"" + key + "\"";
  size_t p = js.find(k);
  if (p == std::string::npos) return {};
  p = js.find(':', p + k.size());
  if (p == std::string::npos) return {};
  ++p;
  while (p < js.size() && (js[p] == ' ' || js[p] == '\t')) ++p;
  if (p < js.size() && js[p] == '"') {
    size_t e = js.find('"', p + 1);
    return js.substr(p + 1, e - p - 1);
  }
  size_t e = js.find_first_of(",}\n", p);
  return js.substr(p, e - p);
}

static Checkpoint parse_checkpoint(const std::string& js) {
  Checkpoint c;
  c.band_idx = std::stoi(json_get(js, "band_idx"));
  c.bands_total = std::stoi(json_get(js, "bands_total"));
  c.recipe_hash = json_get(js, "recipe_hash");
  c.model_sha256 = json_get(js, "model_sha256");
  c.input_sha256 = json_get(js, "input_sha256");
  c.backend = json_get(js, "backend");
  c.tile = std::stoi(json_get(js, "tile"));
  c.pad = std::stoi(json_get(js, "pad"));
  c.feather = std::stoi(json_get(js, "feather"));
  c.scale = json_get(js, "scale");
  c.format = json_get(js, "format");
  c.out_w = std::stoi(json_get(js, "out_w"));
  c.out_h = std::stoi(json_get(js, "out_h"));
  return c;
}

struct LzHeader {
  char magic[4];  // "S2B1"
  uint32_t rows, width;
  uint32_t raw_size, comp_size;
  uint32_t reserved;
};

struct BandStore {
  std::string job, bands_dir;
  bool lz4 = false;
  int lz4_accel = 1;
  bool do_fsync = true;
  bool drop_cache = false;
  Checkpoint ck;  // template; band_idx updated on commit

  std::string band_path(int i) const {
    char b[32];
    snprintf(b, sizeof(b), "/%04d.%s", i, lz4 ? "lz4" : "raw");
    return bands_dir + b;
  }
  std::string tail_path(int i) const {
    char b[32];
    snprintf(b, sizeof(b), "/%04d.tail", i);
    return bands_dir + b;
  }
  std::string ck_path() const { return job + "/checkpoint.json"; }

  // Called on the writer thread.
  void commit(const BandJob& j, int width) {
    double t0 = now_s();
    std::vector<uint8_t> comp;
    const void* payload = j.data.data();
    size_t n = j.data.size();
    if (lz4) {
      int bound = LZ4_compressBound(int(n));
      comp.resize(sizeof(LzHeader) + size_t(bound));
      double tc = now_s();
      int cs = LZ4_compress_fast(reinterpret_cast<const char*>(j.data.data()),
                                 reinterpret_cast<char*>(comp.data() + sizeof(LzHeader)), int(n),
                                 bound, lz4_accel);
      g_stats.add("lz4_compress", now_s() - tc);
      if (cs <= 0) die("LZ4 compression failed");
      LzHeader h{{'S', '2', 'B', '1'}, uint32_t(n / (size_t(width) * 3)), uint32_t(width),
                 uint32_t(n), uint32_t(cs), 0};
      memcpy(comp.data(), &h, sizeof(h));
      comp.resize(sizeof(LzHeader) + size_t(cs));
      payload = comp.data();
      n = comp.size();
    }
    double tw = now_s();
    write_file_atomic(band_path(j.idx), payload, n, do_fsync);
    if (!j.tail.empty()) write_file_atomic(tail_path(j.idx), j.tail.data(), j.tail.size(), do_fsync);
    if (do_fsync) fsync_dir(bands_dir);
    if (drop_cache) {
      int fd = open(band_path(j.idx).c_str(), O_RDONLY);
      if (fd >= 0) {
        fdatasync(fd);
        posix_fadvise(fd, 0, 0, POSIX_FADV_DONTNEED);
        close(fd);
      }
    }
    g_stats.add("band_file_write", now_s() - tw);
    double tk = now_s();
    ck.band_idx = j.idx;
    std::string js = checkpoint_json(ck);
    write_file_atomic(ck_path(), js.data(), js.size(), do_fsync);
    if (do_fsync) fsync_dir(job);
    g_stats.add("checkpoint", now_s() - tk);
    g_stats.add("band_write_total", now_s() - t0);
    logf("band %d committed (%zu bytes)", j.idx, n);
  }

  // Reads band i into `out` (raw RGB8). Returns rows.
  void read_band(int i, std::vector<uint8_t>& out, size_t expect_bytes) const {
    std::string p = band_path(i);
    if (!lz4) {
      out.resize(expect_bytes);
      FILE* f = fopen(p.c_str(), "rb");
      if (!f) die("open %s", p.c_str());
      if (fread(out.data(), 1, expect_bytes, f) != expect_bytes) die("short band %s", p.c_str());
      fclose(f);
      return;
    }
    std::vector<uint8_t> comp = read_file(p);
    LzHeader h;
    memcpy(&h, comp.data(), sizeof(h));
    if (memcmp(h.magic, "S2B1", 4) != 0 || h.raw_size != expect_bytes) die("bad lz4 band %s", p.c_str());
    out.resize(expect_bytes);
    double td = now_s();
    int r = LZ4_decompress_safe(reinterpret_cast<const char*>(comp.data() + sizeof(LzHeader)),
                                reinterpret_cast<char*>(out.data()), int(h.comp_size),
                                int(h.raw_size));
    g_stats.add("lz4_decompress", now_s() - td);
    if (r != int(h.raw_size)) die("lz4 decompress failed %s", p.c_str());
  }
};

class AsyncWriter {
 public:
  AsyncWriter(BandStore* s, int width, bool sync) : store_(s), width_(width), sync_(sync) {
    if (!sync_) th_ = std::thread([this] { loop(); });
  }
  ~AsyncWriter() { finish(); }
  // Blocks while the writer is still busy with the previous band.
  void submit(BandJob&& j) {
    if (sync_) {
      store_->commit(j, width_);
      recycle(std::move(j.data));
      return;
    }
    double t0 = now_s();
    std::unique_lock<std::mutex> lk(mu_);
    cv_.wait(lk, [&] { return !job_ && !busy_; });
    g_stats.add("io_stall", now_s() - t0);
    job_ = std::move(j);
    cv_.notify_all();
  }
  void wait_idle() {
    if (sync_) return;
    double t0 = now_s();
    std::unique_lock<std::mutex> lk(mu_);
    cv_.wait(lk, [&] { return !job_ && !busy_; });
    g_stats.add("io_stall", now_s() - t0);
  }
  void finish() {
    if (sync_ || !th_.joinable()) return;
    {
      std::unique_lock<std::mutex> lk(mu_);
      cv_.wait(lk, [&] { return !job_ && !busy_; });
      stop_ = true;
      cv_.notify_all();
    }
    th_.join();
  }
  // Buffer recycling to avoid re-faulting 25-100 MB per band.
  std::vector<uint8_t> take_buffer() {
    std::lock_guard<std::mutex> g(mu_);
    std::vector<uint8_t> b;
    if (!free_.empty()) {
      b = std::move(free_.back());
      free_.pop_back();
    }
    return b;
  }

 private:
  void recycle(std::vector<uint8_t>&& b) {
    std::lock_guard<std::mutex> g(mu_);
    if (free_.size() < 1) free_.push_back(std::move(b));
  }
  void loop() {
    for (;;) {
      BandJob j;
      {
        std::unique_lock<std::mutex> lk(mu_);
        cv_.wait(lk, [&] { return job_.has_value() || stop_; });
        if (stop_ && !job_) return;
        j = std::move(*job_);
        job_.reset();
        busy_ = true;
      }
      store_->commit(j, width_);
      {
        std::lock_guard<std::mutex> g(mu_);
        if (free_.size() < 1) free_.push_back(std::move(j.data));
        busy_ = false;
      }
      cv_.notify_all();
    }
  }
  BandStore* store_;
  int width_;
  bool sync_;
  std::thread th_;
  std::mutex mu_;
  std::condition_variable cv_;
  std::optional<BandJob> job_;
  bool busy_ = false, stop_ = false;
  std::vector<std::vector<uint8_t>> free_;
};

// ----------------------------------------------------------------------------
// Preview (area accumulation)
// ----------------------------------------------------------------------------

struct Preview {
  int w = 0, h = 0, pw = 0, ph = 0;
  std::vector<int> colmap;
  std::vector<uint32_t> sum;  // ph*pw*3
  std::vector<uint32_t> colcount, rowcount;
  void init(int W, int H, int maxside) {
    w = W;
    h = H;
    int m = std::max(W, H);
    if (m <= maxside) {
      pw = W;
      ph = H;
    } else {
      pw = std::max(1, int(std::lround(double(W) * maxside / m)));
      ph = std::max(1, int(std::lround(double(H) * maxside / m)));
    }
    colmap.resize(size_t(W));
    colcount.assign(size_t(pw), 0);
    rowcount.assign(size_t(ph), 0);
    for (int x = 0; x < W; ++x) {
      colmap[x] = int((long long)x * pw / W);
      colcount[colmap[x]]++;
    }
    for (int y = 0; y < H; ++y) rowcount[size_t((long long)y * ph / H)]++;
    sum.assign(size_t(pw) * ph * 3, 0);
  }
  void add_rows(const uint8_t* data, int y0, int n) {
    for (int i = 0; i < n; ++i) {
      int py = int((long long)(y0 + i) * ph / h);
      uint32_t* s = sum.data() + size_t(py) * pw * 3;
      const uint8_t* r = data + size_t(i) * w * 3;
      for (int x = 0; x < w; ++x) {
        uint32_t* d = s + colmap[x] * 3;
        d[0] += r[x * 3];
        d[1] += r[x * 3 + 1];
        d[2] += r[x * 3 + 2];
      }
    }
  }
  std::vector<uint8_t> finalize() const {
    std::vector<uint8_t> out(size_t(pw) * ph * 3);
    for (int y = 0; y < ph; ++y)
      for (int x = 0; x < pw; ++x) {
        uint32_t cnt = rowcount[y] * colcount[x];
        for (int c = 0; c < 3; ++c) {
          size_t i = (size_t(y) * pw + x) * 3 + c;
          out[i] = uint8_t(cnt ? (sum[i] + cnt / 2) / cnt : 0);
        }
      }
    return out;
  }
};

// ----------------------------------------------------------------------------
// Export
// ----------------------------------------------------------------------------

static void export_image(const BandStore& store, const Geometry& g, const std::string& path,
                         bool png, const Args& a) {
  std::string key = png ? "encode_png" : "encode_jpeg";
  double t0 = now_s();
  JpegWriter jw;
  PngWriter pw;
  if (png) pw.open(path, g.out_w, g.out_h, a.png_level);
  else jw.open(path, g.out_w, g.out_h, a.jpeg_q);
  std::vector<uint8_t> buf;
  double t_read = 0;
  for (int b = 0; b < g.bands(); ++b) {
    int rows = g.band_out_rows(b);
    double tr = now_s();
    store.read_band(b, buf, size_t(rows) * g.out_w * 3);
    t_read += now_s() - tr;
    if (png) pw.rows(buf.data(), rows, g.out_w);
    else jw.rows(buf.data(), rows, g.out_w);
  }
  if (png) pw.close();
  else jw.close();
  g_stats.add(key, now_s() - t0);
  g_stats.add(key + "_read", t_read);
  g_stats.num[key + "_bytes"] = double(file_size(path));
  logf("%s: %s %lld bytes in %.2f s (band read %.2f s)", key.c_str(), path.c_str(),
       file_size(path), now_s() - t0, t_read);
}

// ----------------------------------------------------------------------------
// Main
// ----------------------------------------------------------------------------

static void write_stats(const Args& a, const Geometry& g, const std::string& path) {
  FILE* f = fopen(path.c_str(), "w");
  if (!f) die("open %s", path.c_str());
  fprintf(f, "{\n");
  fprintf(f, "  \"args\": {\"input\": \"%s\", \"tile\": %d, \"pad\": %d, \"feather\": %d, "
             "\"scale\": \"%s\", \"backend\": \"%s\", \"threads\": %d, \"fp16\": %d, "
             "\"lz4\": %d, \"sync_io\": %d, \"fsync\": %d, \"resume\": %d},\n",
          a.input.c_str(), a.tile, a.pad, a.feather, a.scale.c_str(), a.backend.c_str(), a.threads,
          int(a.fp16), int(a.lz4), int(a.sync_io), int(a.do_fsync), int(a.resume));
  fprintf(f, "  \"geometry\": {\"in_w\": %d, \"in_h\": %d, \"sr_w\": %d, \"sr_h\": %d, "
             "\"out_w\": %d, \"out_h\": %d, \"tiles_x\": %zu, \"bands\": %zu},\n",
          g.in_w, g.in_h, g.sr_w, g.sr_h, g.out_w, g.out_h, g.xs.size(), g.ys.size());
  // seam boundaries in x4 (sr) output coordinates
  fprintf(f, "  \"seams_x\": [");
  for (size_t j = 1; j < g.xs.size(); ++j)
    fprintf(f, "%s%d", j > 1 ? ", " : "", 4 * owned_start(g.xs, int(j), g.tw));
  fprintf(f, "],\n  \"seams_y\": [");
  for (size_t j = 1; j < g.ys.size(); ++j)
    fprintf(f, "%s%d", j > 1 ? ", " : "", 4 * owned_start(g.ys, int(j), g.th));
  fprintf(f, "],\n  \"times_s\": {");
  bool first = true;
  for (auto& [k, v] : g_stats.t) {
    fprintf(f, "%s\"%s\": %.4f", first ? "" : ", ", k.c_str(), v);
    first = false;
  }
  fprintf(f, "},\n  \"stage_peak_mb\": {");
  first = true;
  for (auto& [k, v] : g_stats.stage_peak_kb) {
    fprintf(f, "%s\"%s\": %.1f", first ? "" : ", ", k.c_str(), v / 1024.0);
    first = false;
  }
  fprintf(f, "},\n  \"peak_rss_mb\": %.1f,\n  \"num\": {", g_global_peak_kb / 1024.0);
  first = true;
  for (auto& [k, v] : g_stats.num) {
    fprintf(f, "%s\"%s\": %.6g", first ? "" : ", ", k.c_str(), v);
    first = false;
  }
  fprintf(f, "},\n  \"str\": {");
  first = true;
  for (auto& [k, v] : g_stats.str) {
    fprintf(f, "%s\"%s\": \"%s\"", first ? "" : ", ", k.c_str(), v.c_str());
    first = false;
  }
  fprintf(f, "}\n}\n");
  fclose(f);
}

int main(int argc, char** argv) {
  Args a = parse_args(argc, argv);
  double t_start = now_s();
  reset_hwm();

  bool vk = a.backend.rfind("vk", 0) == 0;
  stage_end("process_start");
  if (vk) {
    ScopedTimer t("gpu_init");
    ncnn::create_gpu_instance();
  }
  if (vk) stage_end("gpu_init");

  // ---- identity / hashes ---------------------------------------------------
  std::string model_sha;
  {
    Sha256 h;
    for (const char* ext : {".ncnn.param", ".ncnn.bin"}) {
      std::vector<uint8_t> d = read_file(a.model + ext);
      h.update(d.data(), d.size());
    }
    model_sha = h.hex();
  }
  std::string input_sha = Sha256::of_file(a.input);
  if (input_sha.empty()) die("cannot read %s", a.input.c_str());

  // ---- model load -------------------------------------------------------------
  Backend* be = new Backend();
  {
    ScopedTimer t("model_load");
    be->init(a);
  }
  g_stats.str["backend_name"] = be->name;
  logf("backend %s, threads %d, fp16 %d", be->name.c_str(), a.threads, int(a.fp16));
  stage_end("model_load");

  // ---- decode -----------------------------------------------------------------
  Rgb8 img;
  {
    ScopedTimer t("decode");
    img = decode_jpeg(a.input);
  }
  logf("decoded %dx%d", img.w, img.h);
  const int orig_w = img.w, orig_h = img.h;
  if (a.scale == "fast2") {
    ScopedTimer t("fast2_downscale");
    Rgb8 half;
    half.w = img.w / 2;
    half.h = img.h / 2;
    half.px.resize(size_t(half.w) * half.h * 3);
    area_down2(img.px.data(), img.w, half.h * 2, half.px.data());  // odd last col/row dropped
    img = std::move(half);
  }
  stage_end("decode");

  // ---- geometry -----------------------------------------------------------
  Geometry g;
  g.in_w = img.w;
  g.in_h = img.h;
  int T = a.tile == 0 ? std::max(img.w, img.h) : a.tile;
  g.tw = std::min(T, img.w);
  g.th = std::min(T, img.h);
  g.pad = a.pad;
  if (g.pad >= std::min(img.w, img.h)) die("pad too large for image");
  g.sr_w = img.w * 4;
  g.sr_h = img.h * 4;
  g.down = a.scale == "2" ? 2 : 1;
  g.out_w = g.sr_w / g.down;
  g.out_h = g.sr_h / g.down;
  g.xs = tile_origins(img.w, g.tw);
  g.ys = tile_origins(img.h, g.th);
  const int nb = g.bands();
  logf("SR input %dx%d, tile %dx%d pad %d, grid %zux%zu, out %dx%d (%.1f MP)", g.in_w, g.in_h,
       g.tw, g.th, g.pad, g.xs.size(), g.ys.size(), g.out_w, g.out_h,
       double(g.out_w) * g.out_h / 1e6);

  // ---- BandStore / checkpoint --------------------------------------------
  BandStore store;
  store.job = a.job;
  store.bands_dir = a.job + "/bands";
  store.lz4 = a.lz4;
  store.lz4_accel = a.lz4_accel;
  store.do_fsync = a.do_fsync;
  store.drop_cache = a.drop_cache;
  Checkpoint& ck = store.ck;
  ck.bands_total = nb;
  ck.model_sha256 = model_sha;
  ck.input_sha256 = input_sha;
  ck.backend = a.backend + (a.fp16 ? ":fp16" : ":fp32");
  ck.tile = a.tile;
  ck.pad = a.pad;
  ck.feather = a.feather;
  ck.scale = a.scale;
  ck.format = a.lz4 ? "lz4" : "raw";
  ck.out_w = g.out_w;
  ck.out_h = g.out_h;
  {
    char rb[512];
    snprintf(rb, sizeof(rb), "in=%s;model=%s;tile=%d;pad=%d;feather=%d;scale=%s;fmt=%s",
             input_sha.c_str(), model_sha.c_str(), a.tile, a.pad, a.feather, a.scale.c_str(),
             ck.format.c_str());
    ck.recipe_hash = Sha256::of_string(rb);
  }

  int start_band = 0;
  if (a.resume) {
    if (!file_exists(store.ck_path())) die("--resume: no checkpoint in %s", a.job.c_str());
    std::vector<uint8_t> js = read_file(store.ck_path());
    Checkpoint old = parse_checkpoint(std::string(js.begin(), js.end()));
    if (old.recipe_hash != ck.recipe_hash) die("--resume: recipe_hash mismatch");
    if (old.model_sha256 != ck.model_sha256) die("--resume: model mismatch");
    if (old.backend != ck.backend) die("--resume: backend mismatch (%s vs %s)", old.backend.c_str(), ck.backend.c_str());
    for (int b = 0; b <= old.band_idx; ++b)
      if (!file_exists(store.band_path(b))) die("--resume: missing band %d", b);
    start_band = old.band_idx + 1;
    logf("resume: checkpoint band_idx=%d -> continuing at band %d of %d", old.band_idx,
         start_band, nb);
    g_stats.num["resume_start_band"] = start_band;
    // discard partially-written files of uncommitted bands
    for (int b = start_band; b < nb; ++b) {
      unlink((store.band_path(b) + ".tmp").c_str());
      unlink(store.band_path(b).c_str());
      unlink(store.tail_path(b).c_str());
      unlink((store.tail_path(b) + ".tmp").c_str());
    }
  } else {
    // fresh job: clear old bands
    mkdirs(store.bands_dir);
    if (DIR* d = opendir(store.bands_dir.c_str())) {
      while (dirent* e = readdir(d))
        if (e->d_name[0] != '.') unlink((store.bands_dir + "/" + e->d_name).c_str());
      closedir(d);
    }
    unlink(store.ck_path().c_str());
    // NFR-SIZE-004: free space check (raw estimate + 20%)
    struct statvfs vs;
    double need = double(g.out_w) * g.out_h * 3 * 1.2;
    if (statvfs(store.bands_dir.c_str(), &vs) == 0) {
      double avail = double(vs.f_bavail) * vs.f_frsize;
      g_stats.num["disk_need_bytes"] = need;
      if (avail < need) die("not enough disk space: need %.0f MB, have %.0f MB", need / 1e6, avail / 1e6);
    }
  }

  // ---- preview -----------------------------------------------------------
  Preview pv;
  pv.init(g.out_w, g.out_h, a.preview_max);
  std::vector<uint8_t> prev_tail;  // feather tail from previous band (x4 res, F rows x sr_w)
  const int F = a.feather;
  if (start_band > 0) {
    // Rebuild preview from committed bands (cheap vs. inference), reload feather tail.
    ScopedTimer t("resume_rebuild");
    std::vector<uint8_t> buf;
    int y = 0;
    for (int b = 0; b < start_band; ++b) {
      int rows = g.band_out_rows(b);
      store.read_band(b, buf, size_t(rows) * g.out_w * 3);
      pv.add_rows(buf.data(), y, rows);
      y += rows;
    }
    if (F > 0) prev_tail = read_file(store.tail_path(start_band - 1));
  }
  stage_end("setup");

  // ---- SR banded loop ------------------------------------------------------
  {
    AsyncWriter writer(&store, g.out_w, a.sync_io);
    const int P = g.pad;
    const int itw = g.tw + 2 * P, ith = g.th + 2 * P;  // network input size
    const int otw = 4 * itw;                          // network output width
    std::vector<int> colidx(static_cast<size_t>(itw));
    std::vector<float> hext;  // horizontal feather: prev tile's F columns x band rows x 3
    ncnn::Mat in(itw, ith, 3), out;
    int out_y = 0;
    for (int b = 0; b < start_band; ++b) out_y += g.band_out_rows(b);

    for (int b = start_band; b < nb; ++b) {
      double tb0 = now_s();
      const int y0 = g.band_in_y0(b), y1 = g.band_in_y1(b);
      const int brows4 = 4 * (y1 - y0);  // band rows at x4
      const int Y0 = 4 * y0;            // first owned output row (x4 coords)
      const int tyoff = 4 * (g.ys[b] - P);  // x4 row of tile output row 0
      std::vector<uint8_t> band = writer.take_buffer();
      band.resize(size_t(brows4) * g.sr_w * 3);
      std::vector<uint8_t> tail;
      bool want_tail = F > 0 && b + 1 < nb;
      if (want_tail) tail.assign(size_t(F) * g.sr_w * 3, 0);

      for (size_t j = 0; j < g.xs.size(); ++j) {
        const int x0 = g.xs[j];
        // prep: reflect-padded tile, CHW float [0,1]
        {
          ScopedTimer t("prep");
          for (int xx = 0; xx < itw; ++xx) colidx[xx] = reflect101(x0 - P + xx, g.in_w);
          for (int yy = 0; yy < ith; ++yy) {
            int ry = reflect101(g.ys[b] - P + yy, g.in_h);
            const uint8_t* src = img.px.data() + size_t(ry) * g.in_w * 3;
            float* r = in.channel(0).row(yy);
            float* gg = in.channel(1).row(yy);
            float* bl = in.channel(2).row(yy);
            for (int xx = 0; xx < itw; ++xx) {
              const uint8_t* p = src + colidx[xx] * 3;
              r[xx] = p[0] * (1.f / 255.f);
              gg[xx] = p[1] * (1.f / 255.f);
              bl[xx] = p[2] * (1.f / 255.f);
            }
          }
        }
        {
          ScopedTimer t("infer");
          be->run(in, out);
        }
        if (out.w != otw || out.h != 4 * ith || out.c != 3) die("unexpected output shape");
        // post: crop owned region into band buffer, feather, quantize
        {
          ScopedTimer t("post");
          const int X0 = 4 * owned_start(g.xs, int(j), g.tw);
          const int X1 = j + 1 < g.xs.size() ? 4 * owned_start(g.xs, int(j) + 1, g.tw) : g.sr_w;
          const int txoff = 4 * (x0 - P);
          auto q = [](float v) -> uint8_t {
            v = v < 0.f ? 0.f : (v > 1.f ? 1.f : v);
            return uint8_t(v * 255.f + 0.5f);
          };
          for (int r = 0; r < brows4; ++r) {
            int ty = Y0 + r - tyoff;
            uint8_t* dst = band.data() + (size_t(r) * g.sr_w) * 3;
            const float* c0 = out.channel(0).row(ty);
            const float* c1 = out.channel(1).row(ty);
            const float* c2 = out.channel(2).row(ty);
            for (int X = X0; X < X1; ++X) {
              int tx = X - txoff;
              float v0 = c0[tx], v1 = c1[tx], v2 = c2[tx];
              int k = X - X0;
              if (F > 0 && j > 0 && k < F) {
                float w = (k + 0.5f) / F;
                const float* e = hext.data() + (size_t(r) * F + k) * 3;
                v0 = (1 - w) * e[0] + w * v0;
                v1 = (1 - w) * e[1] + w * v1;
                v2 = (1 - w) * e[2] + w * v2;
              }
              dst[X * 3] = q(v0);
              dst[X * 3 + 1] = q(v1);
              dst[X * 3 + 2] = q(v2);
            }
          }
          if (F > 0 && j + 1 < g.xs.size()) {
            // save this tile's prediction of the next tile's first F columns
            hext.resize(size_t(brows4) * F * 3);
            for (int r = 0; r < brows4; ++r) {
              int ty = Y0 + r - tyoff;
              for (int k = 0; k < F; ++k) {
                int tx = X1 + k - txoff;
                float* e = hext.data() + (size_t(r) * F + k) * 3;
                e[0] = out.channel(0).row(ty)[tx];
                e[1] = out.channel(1).row(ty)[tx];
                e[2] = out.channel(2).row(ty)[tx];
              }
            }
          }
          if (want_tail) {
            // this tile's prediction of the next band's first F rows (owned columns only)
            for (int k = 0; k < F; ++k) {
              int ty = Y0 + brows4 + k - tyoff;
              uint8_t* dst = tail.data() + size_t(k) * g.sr_w * 3;
              for (int X = X0; X < X1; ++X) {
                int tx = X - txoff;
                dst[X * 3] = q(out.channel(0).row(ty)[tx]);
                dst[X * 3 + 1] = q(out.channel(1).row(ty)[tx]);
                dst[X * 3 + 2] = q(out.channel(2).row(ty)[tx]);
              }
            }
          }
        }
      }
      // vertical feather with previous band's tail
      if (F > 0 && b > 0) {
        ScopedTimer t("post");
        if (prev_tail.size() != size_t(F) * g.sr_w * 3) die("feather tail size mismatch");
        for (int k = 0; k < F && k < brows4; ++k) {
          float w = (k + 0.5f) / F;
          uint8_t* dst = band.data() + size_t(k) * g.sr_w * 3;
          const uint8_t* tp = prev_tail.data() + size_t(k) * g.sr_w * 3;
          for (int i = 0; i < g.sr_w * 3; ++i)
            dst[i] = uint8_t((1 - w) * tp[i] + w * dst[i] + 0.5f);
        }
      }
      // x2: area downscale per band
      BandJob job;
      job.idx = b;
      if (g.down == 2) {
        ScopedTimer t("downscale_x2");
        std::vector<uint8_t> d(size_t(brows4 / 2) * g.out_w * 3);
        area_down2(band.data(), g.sr_w, brows4, d.data());
        job.data = std::move(d);
        band.clear();
        band.shrink_to_fit();
      } else {
        job.data = std::move(band);
      }
      const int rows = int(job.data.size() / (size_t(g.out_w) * 3));
      {
        ScopedTimer t("preview");
        pv.add_rows(job.data.data(), out_y, rows);
      }
      out_y += rows;
      if (want_tail) job.tail = tail;
      prev_tail = std::move(tail);
      sample_drm();
      logf("band %d/%d computed in %.2f s", b, nb, now_s() - tb0);
      writer.submit(std::move(job));
    }
    writer.wait_idle();
    writer.finish();
  }
  stage_end("sr_banded");
  double t_sr_end = now_s();

  // free the model and input before export (one heavy object at a time)
  delete be;
  be = nullptr;
  img.px.clear();
  img.px.shrink_to_fit();
  if (vk) {
    ncnn::destroy_gpu_instance();  // release the driver before export (one heavy object at a time)
    vk = false;
  }
  malloc_trim(0);  // return freed arenas to the OS so the export stage peak is meaningful

  // ---- preview -------------------------------------------------------------
  if (!a.out_preview.empty()) {
    ScopedTimer t("preview");
    std::vector<uint8_t> p = pv.finalize();
    write_jpeg_whole(a.out_preview, p.data(), pv.pw, pv.ph, 85);
    g_stats.num["preview_w"] = pv.pw;
    g_stats.num["preview_h"] = pv.ph;
  }
  pv.sum.clear();
  pv.sum.shrink_to_fit();

  // BandStore size
  long long store_bytes = 0, store_disk = 0;
  for (int b = 0; b < nb; ++b) {
    store_bytes += file_size(store.band_path(b));
    store_disk += file_disk_bytes(store.band_path(b));
    if (F > 0 && b + 1 < nb) store_bytes += file_size(store.tail_path(b));
  }
  g_stats.num["bandstore_bytes"] = double(store_bytes);
  g_stats.num["bandstore_disk_bytes"] = double(store_disk);
  g_stats.num["raw_bytes"] = double(g.out_w) * g.out_h * 3;
  stage_end("preview");

  // ---- export --------------------------------------------------------------
  if (!a.out_jpeg.empty()) {
    export_image(store, g, a.out_jpeg, false, a);
    stage_end("encode_jpeg");
  }
  if (!a.out_png.empty()) {
    export_image(store, g, a.out_png, true, a);
    stage_end("encode_png");
  }

  if (vk) ncnn::destroy_gpu_instance();
  double total = now_s() - t_start;
  g_stats.num["total_s"] = total;
  g_stats.num["drm_resident_peak_mb"] = g_drm_peak_kb / 1024.0;
  g_stats.num["rss_plus_drm_peak_mb"] = g_combined_peak_kb / 1024.0;
  g_stats.num["to_sr_done_s"] = t_sr_end - t_start;
  g_stats.num["input_mp"] = double(orig_w) * orig_h / 1e6;
  logf("done: total %.2f s, peak RSS %.1f MB, BandStore %.1f MB (%d bands)", total,
       g_global_peak_kb / 1024.0, store_bytes / 1e6, nb);
  for (auto& [k, v] : g_stats.t) logf("  %-20s %8.3f s", k.c_str(), v);
  if (!a.stats_json.empty()) write_stats(a, g, a.stats_json);
  return 0;
}
