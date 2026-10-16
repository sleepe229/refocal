// CompareViewer tiles (06 §5, S7): regions of a finished job's result, straight from the
// BandStore (rows are addressable in the uncompressed bands, ADR-0004), and the same regions
// of the original scaled to the result's coordinates. Tiles are rendered on demand, so no
// pyramid is stored on disk. Thread-safe: each render opens the band files it reads; the
// original is decoded once, on first use.
// SPDX-License-Identifier: Apache-2.0
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <memory>
#include <mutex>
#include <nlohmann/json.hpp>
#include <string>
#include <vector>

#include "enh.h"
#include "image/decode.hpp"
#include "image/ops.hpp"
#include "job/job.hpp"
#include "util/error.hpp"
#include "util/fs.hpp"
#include "util/log.hpp"

using namespace enh;

struct enh_viewer {
  std::string dir, input;
  int w = 0, h = 0;
  std::vector<int> band_rows, band_y0;

  std::once_flag decoded;
  std::unique_ptr<Rgb8> original;  // null when the input cannot be read
  enh_status original_status = ENH_OK;
};

namespace {

constexpr int kMaxFactor = 1 << 12;
constexpr int64_t kMaxTileSide = 1024;

// Rows [y, y + n) of the result, columns [x, x + w), into dst (RGB8, n rows of w).
void read_result_rows(const enh_viewer& v, int y, int n, int x, int w, uint8_t* dst) {
  std::FILE* f = nullptr;
  int open_band = -1;
  auto close = [&] {
    if (f) std::fclose(f);
    f = nullptr;
  };
  for (int r = 0; r < n; ++r) {
    const int row = y + r;
    const auto it = std::upper_bound(v.band_y0.begin(), v.band_y0.end(), row);
    const int b = int(it - v.band_y0.begin()) - 1;
    if (b != open_band) {
      close();
      char name[32];
      std::snprintf(name, sizeof name, "bands/%04d.raw", b);
      f = std::fopen(fs::join(v.dir, name).c_str(), "rb");
      if (!f) fail(ENH_E_IO, "cannot read the result");
      open_band = b;
    }
    const int64_t off = (int64_t(row - v.band_y0[size_t(b)]) * v.w + x) * 3;
    if (fseeko(f, off_t(off), SEEK_SET) != 0 ||
        std::fread(dst + size_t(r) * w * 3, 1, size_t(w) * 3, f) != size_t(w) * 3) {
      close();
      fail(ENH_E_IO, "cannot read the result");
    }
  }
  close();
}

void render_result(const enh_viewer& v, int x, int y, int w, int h, int f, uint8_t* rgba) {
  const int ow = (w + f - 1) / f, oh = (h + f - 1) / f;
  std::vector<uint8_t> row(size_t(w) * 3);  // one row at a time: f can be large
  std::vector<uint64_t> acc(size_t(ow) * 3);
  for (int oy = 0; oy < oh; ++oy) {
    const int y0 = y + oy * f, n = std::min(f, y + h - y0);
    std::fill(acc.begin(), acc.end(), 0);
    for (int r = 0; r < n; ++r) {
      read_result_rows(v, y0 + r, 1, x, w, row.data());
      const uint8_t* p = row.data();
      for (int c = 0; c < w; ++c)
        for (int k = 0; k < 3; ++k) acc[size_t(c / f) * 3 + k] += p[c * 3 + k];
    }
    uint8_t* out = rgba + size_t(oy) * ow * 4;
    for (int ox = 0; ox < ow; ++ox) {
      const uint64_t cnt = uint64_t(n) * uint64_t(std::min(f, w - ox * f));
      for (int k = 0; k < 3; ++k)
        out[ox * 4 + k] = uint8_t((acc[size_t(ox) * 3 + k] + cnt / 2) / cnt);
      out[ox * 4 + 3] = 255;
    }
  }
}

// The original under the same region: each output pixel is the mean of the input pixels it
// covers when it covers at least one, else a bilinear sample (zoomed past the input's size).
void render_original(const enh_viewer& v, int x, int y, int w, int h, int f, uint8_t* rgba) {
  const Rgb8& in = *v.original;
  const int ow = (w + f - 1) / f, oh = (h + f - 1) / f;
  const double sx = double(in.w) / v.w, sy = double(in.h) / v.h;
  for (int oy = 0; oy < oh; ++oy) {
    const double a0 = (y + oy * f) * sy, a1 = std::min(y + h, y + (oy + 1) * f) * sy;
    for (int ox = 0; ox < ow; ++ox) {
      const double b0 = (x + ox * f) * sx, b1 = std::min(x + w, x + (ox + 1) * f) * sx;
      uint8_t* out = rgba + (size_t(oy) * ow + ox) * 4;
      out[3] = 255;
      if (a1 - a0 >= 1 && b1 - b0 >= 1) {
        const int r0 = int(a0), r1 = std::min(in.h, int(std::ceil(a1)));
        const int c0 = int(b0), c1 = std::min(in.w, int(std::ceil(b1)));
        uint64_t acc[3] = {0, 0, 0};
        for (int r = r0; r < r1; ++r) {
          const uint8_t* p = in.row(r);
          for (int c = c0; c < c1; ++c)
            for (int k = 0; k < 3; ++k) acc[k] += p[c * 3 + k];
        }
        const uint64_t cnt = uint64_t(r1 - r0) * uint64_t(c1 - c0);
        for (int k = 0; k < 3; ++k) out[k] = uint8_t((acc[k] + cnt / 2) / cnt);
      } else {
        const double fy = std::clamp((a0 + a1) / 2 - 0.5, 0.0, in.h - 1.0);
        const double fx = std::clamp((b0 + b1) / 2 - 0.5, 0.0, in.w - 1.0);
        const int r = int(fy), c = int(fx);
        const int r2 = std::min(r + 1, in.h - 1), c2 = std::min(c + 1, in.w - 1);
        const double ty = fy - r, tx = fx - c;
        for (int k = 0; k < 3; ++k) {
          const double top = in.row(r)[c * 3 + k] * (1 - tx) + in.row(r)[c2 * 3 + k] * tx;
          const double bot = in.row(r2)[c * 3 + k] * (1 - tx) + in.row(r2)[c2 * 3 + k] * tx;
          out[k] = uint8_t(std::lround(top * (1 - ty) + bot * ty));
        }
      }
    }
  }
}

}  // namespace

extern "C" {

enh_status enh_viewer_open(const char* job_dir, enh_viewer** out) {
  if (!job_dir || !out) return ENH_E_INVALID;
  try {
    auto v = std::make_unique<enh_viewer>();
    v->dir = job_dir;
    const auto res =
        nlohmann::json::parse(fs::read_text(fs::join(v->dir, kResultFile)), nullptr, false);
    if (res.is_discarded() || res.value("schema", 0) != 1) return ENH_E_INVALID;
    v->w = res.at("width").get<int>();
    v->h = res.at("height").get<int>();
    v->band_rows = res.at("band_rows").get<std::vector<int>>();
    int y = 0;
    for (int r : v->band_rows) {
      if (r <= 0) return ENH_E_INVALID;
      v->band_y0.push_back(y);
      y += r;
    }
    if (v->w <= 0 || y != v->h) return ENH_E_INVALID;
    v->input = parse_job_request(fs::read_text(fs::join(v->dir, kRequestFile))).input;
    *out = v.release();
    return ENH_OK;
  } catch (const Error& e) {
    return e.status();
  } catch (const std::exception&) {
    return ENH_E_INVALID;
  }
}

enh_status enh_viewer_render(enh_viewer* v, int32_t source, int64_t x, int64_t y, int64_t w,
                             int64_t h, int32_t factor, uint8_t* rgba, int64_t rgba_size) {
  if (!v || !rgba || (source != 0 && source != 1) || factor < 1 || factor > kMaxFactor) {
    return ENH_E_INVALID;
  }
  if (x < 0 || y < 0 || w <= 0 || h <= 0 || x + w > v->w || y + h > v->h) return ENH_E_INVALID;
  const int64_t ow = (w + factor - 1) / factor, oh = (h + factor - 1) / factor;
  if (ow > kMaxTileSide || oh > kMaxTileSide || rgba_size < ow * oh * 4) return ENH_E_INVALID;
  try {
    if (source == 0) {
      render_result(*v, int(x), int(y), int(w), int(h), factor, rgba);
      return ENH_OK;
    }
    std::call_once(v->decoded, [v] {
      try {
        ImageInfo info;
        v->original = std::make_unique<Rgb8>(
            apply_orientation(decode_image(v->input, &info), info.orientation));
      } catch (const Error& e) {
        v->original_status = e.status();
      } catch (const std::bad_alloc&) {
        v->original_status = ENH_E_OOM;
      }
    });
    if (!v->original) return v->original_status;
    render_original(*v, int(x), int(y), int(w), int(h), factor, rgba);
    return ENH_OK;
  } catch (const Error& e) {
    return e.status();
  } catch (const std::bad_alloc&) {
    return ENH_E_OOM;
  } catch (const std::exception&) {
    return ENH_E_INTERNAL;
  }
}

void enh_viewer_close(enh_viewer* v) { delete v; }

}  // extern "C"
