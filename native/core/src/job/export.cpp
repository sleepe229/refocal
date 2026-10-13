// enh_export: streams the BandStore of a finished job into the output file (ADR-0004); the full
// image is never in memory. JPEG with metadata (ADR-0018): the source EXIF rewritten by metaio
// (GPS removed unless asked), the source ICC profile, the XMP AI marker. PNG/WebP/HEIC are 0.3.
//
// output_json: {"format":"jpeg","quality":92,
//               "metadata":{"exif":true,"gps":false,"ai_marker":true,"creator_tool":"Refocal x"}}
// (all optional; the values shown are the defaults).
// SPDX-License-Identifier: Apache-2.0
#include <unistd.h>

#include <cstdlib>
#include <cstring>

#include <nlohmann/json.hpp>

#include "enh.h"
#include "image/jpeg.hpp"
#include "image/metaio.hpp"
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
  try {
    auto res = nlohmann::json::parse(fs::read_text(fs::join(job_dir, kResultFile)), nullptr, false);
    if (res.is_discarded() || res.value("schema", 0) != 1) fail(ENH_E_INVALID, "job has no result");
    auto opt = nlohmann::json::parse(output_json, nullptr, false);
    if (opt.is_discarded() || !opt.is_object()) fail(ENH_E_INVALID, "bad output_json");
    const std::string format = opt.value("format", "jpeg");
    const int quality = opt.value("quality", 92);
    if (format != "jpeg") fail(ENH_E_INVALID, "unsupported format (0.1: jpeg)");
    if (quality < 1 || quality > 100) fail(ENH_E_INVALID, "bad quality");

    const int w = res.at("width").get<int>(), h = res.at("height").get<int>();
    const auto rows = res.at("band_rows").get<std::vector<int>>();
    const auto md = opt.value("metadata", nlohmann::json::object());
    if (!md.is_object()) fail(ENH_E_INVALID, "bad metadata options");

    JpegMeta meta;
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
    nlohmann::json written = {{"exif", !meta.exif.empty()}, {"icc", !meta.icc.empty()},
                              {"ai_marker", !meta.xmp.empty()}};

    BandStore store(job_dir);
    {
      JpegWriter jw(tmp, w, h, quality, &meta);
      std::vector<uint8_t> buf;
      int y = 0;
      for (size_t b = 0; b < rows.size(); ++b) {
        store.read_band(int(b), buf, size_t(rows[b]) * w * 3);
        jw.write_rows(buf.data(), rows[b]);
        y += rows[b];
      }
      if (y != h) fail(ENH_E_INTERNAL, "band rows do not add up");
      jw.finish();
    }
    if (::rename(tmp.c_str(), dst_path) != 0) fail(ENH_E_IO, "rename failed");
    if (out_json) {
      nlohmann::json r = {{"path", dst_path}, {"format", format}, {"width", w}, {"height", h},
                          {"bytes", fs::file_size(dst_path)}, {"metadata", written}};
      std::string d = dump_json(r);
      *out_json = static_cast<char*>(std::malloc(d.size() + 1));
      if (!*out_json) return ENH_E_OOM;
      std::memcpy(*out_json, d.c_str(), d.size() + 1);
    }
    return ENH_OK;
  } catch (const nlohmann::json::exception& e) {
    ::unlink(tmp.c_str());
    ENH_LOGW("export: %s", e.what());
    return ENH_E_INVALID;
  } catch (const Error& e) {
    ::unlink(tmp.c_str());
    ENH_LOGW("export: %s", e.what());
    return e.status();
  } catch (const std::exception& e) {
    ::unlink(tmp.c_str());
    ENH_LOGE("export: %s", e.what());
    return ENH_E_INTERNAL;
  }
}
