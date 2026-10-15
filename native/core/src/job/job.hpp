// Job request (request_json of enh_job_create, schema 1) and helpers shared with export.
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <nlohmann/json.hpp>
#include <string>

namespace enh {

struct JobRequest {
  std::string job_id;  // [A-Za-z0-9_-]{1,64}; job dir = work_dir/<job_id>
  std::string input;   // JPEG/PNG/WebP, or HEIC/AVIF/... via the platform decoder
  std::string sr_model = "sr.general-x4v3";
  int scale = 4;                 // 4 | 2 | 1 (ADR-0014)
  bool fast2 = false;            // scale 2 only: input x0.5 -> x4 (4x cheaper)
  int tile = 0;                  // 0 = auto (tier/backend, S2/S3)
  std::string backend = "auto";  // auto | cpu | vulkan
  int preview_max = 2048;
  double max_output_mp = 200.0;  // larger outputs raise NEEDS_USER (disk: 3 B/px, S2)
  // Faces (ADR-0012, ADR-0022): a face pack id ("" = no face restoration), the detector, and
  // how much of the restored face is blended in (0..1, 0.5 by default).
  std::string face_model;
  std::string det_model = "det.yunet-2023mar";
  double face_strength = 0.5;
};

JobRequest parse_job_request(const std::string& json);  // throws Error(ENH_E_INVALID)
nlohmann::json job_request_to_json(const JobRequest& r);

// Files inside a job directory.
inline constexpr const char* kRequestFile = "request.json";
inline constexpr const char* kResultFile = "result.json";
inline constexpr const char* kPreviewFile = "preview.jpg";
inline constexpr const char* kSourceExifFile = "source.exif";  // TIFF block of the input
inline constexpr const char* kSourceIccFile = "source.icc";

}  // namespace enh
