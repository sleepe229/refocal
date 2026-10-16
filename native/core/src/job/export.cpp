// enh_export: streams the BandStore of a finished job into the output file (ADR-0004). JPEG and
// PNG never hold the full image; WebP holds it as YUV/ARGB (encode.hpp). Any number of exports
// from one result, without processing again (FR-EXP-007). Metadata (ADR-0018): the source EXIF
// rewritten by metaio (GPS removed unless asked), the source ICC profile, the XMP AI marker.
//
// Strength (FR-ENH-005, ADR-0012): lerp(lanczos_up(input), sr, strength), applied here rather
// than in the SR stage so changing it needs no reprocessing. Below 1 the input must still exist;
// it is decoded whole (as in the job).
//
// output_json: {"format":"jpeg","quality":92,"lossless":false,"strength":1.0,
//               "metadata":{"exif":true,"gps":false,"ai_marker":true,"creator_tool":"Refocal x"},
//               "thumbnail":{"path":"/abs/thumb.jpg","max_side":512,"quality":80}}
// (all optional; the values shown are the defaults, no thumbnail by default). format: jpeg |
// png | webp; quality: JPEG and lossy WebP; lossless: WebP only. thumbnail: a JPEG of the
// exported pixels (strength applied), <= max_side px, without metadata, accumulated while the
// bands stream (the history preview, FR-HIST-001, PRIV-DATA-002); written before the output is
// renamed into place and removed if the export fails.
// SPDX-License-Identifier: Apache-2.0
#include <unistd.h>

#include <cstdlib>
#include <cstring>
#include <memory>
#include <nlohmann/json.hpp>
#include <type_traits>

#include "enh.h"
#include "image/decode.hpp"
#include "image/encode.hpp"
#include "image/jpeg.hpp"
#include "image/metaio.hpp"
#include "image/ops.hpp"
#include "job/events.hpp"
#include "job/job.hpp"
#include "job/session.hpp"
#include "pipeline/bandstore.hpp"
#include "util/error.hpp"
#include "util/fs.hpp"
#include "util/log.hpp"

using namespace enh;

extern "C" enh_status enh_export(enh_session* s, const char* job_dir, const char* output_json,
                                 const char* dst_path, char** out_json) {
  if (!s || !job_dir || !output_json || !dst_path) return ENH_E_INVALID;
  std::string tmp = std::string(dst_path) + ".part";
  std::string thumb_path, thumb_tmp;
  bool thumb_written = false;  // renamed into place: removed too if the export fails after it
  auto drop_thumbnail = [&] {
    if (!thumb_tmp.empty()) ::unlink(thumb_tmp.c_str());
    if (thumb_written) ::unlink(thumb_path.c_str());
  };
  try {
    auto res = nlohmann::json::parse(fs::read_text(fs::join(job_dir, kResultFile)), nullptr, false);
    if (res.is_discarded() || res.value("schema", 0) != 1) fail(ENH_E_INVALID, "job has no result");
    auto opt = nlohmann::json::parse(output_json, nullptr, false);
    if (opt.is_discarded() || !opt.is_object()) fail(ENH_E_INVALID, "bad output_json");
    const std::string format = opt.value("format", "jpeg");
    const int quality = opt.value("quality", 92);
    const bool lossless = opt.value("lossless", false);
    const double strength = opt.value("strength", 1.0);
    if (format != "jpeg" && format != "png" && format != "webp")
      fail(ENH_E_INVALID, "unsupported format");
    if (quality < 1 || quality > 100) fail(ENH_E_INVALID, "bad quality");
    if (lossless && format != "webp") fail(ENH_E_INVALID, "lossless is for webp");
    if (!(strength >= 0 && strength <= 1)) fail(ENH_E_INVALID, "strength must be 0..1");

    const int w = res.at("width").get<int>(), h = res.at("height").get<int>();
    const auto rows = res.at("band_rows").get<std::vector<int>>();
    const auto md = opt.value("metadata", nlohmann::json::object());
    if (!md.is_object()) fail(ENH_E_INVALID, "bad metadata options");
    int thumb_max = 0, thumb_quality = 0;
    if (opt.contains("thumbnail")) {
      const auto& t = opt["thumbnail"];
      if (!t.is_object() || !t.contains("path") || !t["path"].is_string()) {
        fail(ENH_E_INVALID, "thumbnail needs a path");
      }
      thumb_max = t.value("max_side", 512);
      thumb_quality = t.value("quality", 80);
      if (thumb_max < 16 || thumb_max > 4096) fail(ENH_E_INVALID, "bad thumbnail max_side");
      if (thumb_quality < 1 || thumb_quality > 100) fail(ENH_E_INVALID, "bad thumbnail quality");
      thumb_path = t["path"].get<std::string>();
      thumb_tmp = thumb_path + ".part";
    }

    OutputMeta meta;
    const std::string exif_path = fs::join(job_dir, kSourceExifFile);
    if (md.value("exif", true) && fs::exists(exif_path)) {
      const auto src = fs::read_all(exif_path);
      meta.exif = exif_rewrite(src.data(), src.size(), {w, h, md.value("gps", false)});
    }
    const std::string icc_path = fs::join(job_dir, kSourceIccFile);
    if (fs::exists(icc_path)) meta.icc = fs::read_all(icc_path);  // ADR-0013: always carried
    if (md.value("ai_marker", true)) {
      meta.xmp = ai_marker_xmp(md.value("creator_tool", std::string("Refocal ") + enh_version()));
    }
    nlohmann::json written = {
        {"exif", !meta.exif.empty()}, {"icc", !meta.icc.empty()}, {"ai_marker", !meta.xmp.empty()}};

    // Base of the strength blend: the oriented input, resampled to the result size.
    Rgb8 src;
    std::unique_ptr<LanczosResampler> base;
    if (strength < 1) {
      const auto req = parse_job_request(fs::read_text(fs::join(job_dir, kRequestFile)));
      if (!fs::exists(req.input)) fail(ENH_E_IO, "the original photo is gone");
      ImageInfo info;
      src = apply_orientation(decode_image(req.input, &info), info.orientation);
      base = std::make_unique<LanczosResampler>(src, w, h);
    }

    // FR-IMP-007: PNG and WebP get the input's alpha back, Lanczos-scaled to the result size
    // (kept as three equal channels for the resampler); JPEG stays on white.
    std::unique_ptr<LanczosResampler> alpha_up;
    Rgb8 alpha3;
    if (format != "jpeg" && res.contains("alpha")) {
      const auto& a = res["alpha"];
      const int aw = a.at("width").get<int>(), ah = a.at("height").get<int>();
      const auto raw = fs::read_all(fs::join(job_dir, kAlphaFile));
      if (raw.size() != size_t(aw) * ah) fail(ENH_E_INVALID, "alpha file does not match");
      alpha3.w = aw;
      alpha3.h = ah;
      alpha3.px.resize(raw.size() * 3);
      for (size_t i = 0; i < raw.size(); ++i)
        alpha3.px[i * 3] = alpha3.px[i * 3 + 1] = alpha3.px[i * 3 + 2] = raw[i];
      alpha_up = std::make_unique<LanczosResampler>(alpha3, w, h);
    }
    written["alpha"] = alpha_up != nullptr;

    PreviewAccumulator thumb;
    if (thumb_max) thumb.init(w, h, thumb_max);

    BandStore store(job_dir);
    auto pump = [&](auto& writer) {
      std::vector<uint8_t> buf, lo, a3, alpha;
      int y = 0;
      for (size_t b = 0; b < rows.size(); ++b) {
        const size_t n = size_t(rows[b]) * w * 3;
        store.read_band(int(b), buf, n);
        if (base) {
          lo.resize(n);
          base->rows(y, rows[b], lo.data());
          blend(lo.data(), buf.data(), n, float(strength), buf.data());
        }
        if constexpr (std::is_same_v<std::decay_t<decltype(writer)>, JpegWriter>) {
          writer.write_rows(buf.data(), rows[b]);  // JPEG has no alpha
        } else {
          if (alpha_up) {
            const size_t px = size_t(rows[b]) * w;
            a3.resize(px * 3);
            alpha.resize(px);
            alpha_up->rows(y, rows[b], a3.data());
            for (size_t i = 0; i < px; ++i) alpha[i] = a3[i * 3];
          }
          writer.write_rows(buf.data(), rows[b], alpha_up ? alpha.data() : nullptr);
        }
        if (thumb_max) thumb.add_rows(buf.data(), y, rows[b]);
        y += rows[b];
      }
      if (y != h) fail(ENH_E_INTERNAL, "band rows do not add up");
      writer.finish();
    };
    if (format == "jpeg") {
      JpegWriter jw(tmp, w, h, quality, &meta);
      pump(jw);
    } else if (format == "png") {
      PngWriter pw(tmp, w, h, &meta, alpha_up != nullptr);
      pump(pw);
    } else {
      WebpWriter ww(tmp, w, h, quality, lossless, &meta, alpha_up != nullptr);
      pump(ww);
    }
    Rgb8 tn;
    if (thumb_max) {
      tn = thumb.finish();
      jpeg_encode(thumb_tmp, tn, thumb_quality);
      if (::rename(thumb_tmp.c_str(), thumb_path.c_str()) != 0) fail(ENH_E_IO, "rename failed");
      thumb_written = true;
    }
    if (::rename(tmp.c_str(), dst_path) != 0) fail(ENH_E_IO, "rename failed");
    if (out_json) {
      nlohmann::json r = {{"path", dst_path},
                          {"format", format},
                          {"width", w},
                          {"height", h},
                          {"bytes", fs::file_size(dst_path)},
                          {"strength", strength},
                          {"metadata", written}};
      if (thumb_max) r["thumbnail"] = {{"path", thumb_path}, {"width", tn.w}, {"height", tn.h}};
      std::string d = dump_json(r);
      *out_json = static_cast<char*>(std::malloc(d.size() + 1));
      if (!*out_json) return ENH_E_OOM;
      std::memcpy(*out_json, d.c_str(), d.size() + 1);
    }
    return ENH_OK;
  } catch (const nlohmann::json::exception& e) {
    ::unlink(tmp.c_str());
    drop_thumbnail();
    ENH_LOGW("export: %s", e.what());
    return ENH_E_INVALID;
  } catch (const Error& e) {
    ::unlink(tmp.c_str());
    drop_thumbnail();
    ENH_LOGW("export: %s", e.what());
    return e.status();
  } catch (const std::exception& e) {
    ::unlink(tmp.c_str());
    drop_thumbnail();
    ENH_LOGE("export: %s", e.what());
    return ENH_E_INTERNAL;
  }
}
