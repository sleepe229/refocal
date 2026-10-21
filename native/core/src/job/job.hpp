// Job request (request_json of enh_job_create, schema 1) and helpers shared with export.
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <nlohmann/json.hpp>
#include <string>
#include <vector>

#include "pipeline/faces.hpp"

namespace enh {

struct JobRequest {
  std::string job_id;  // [A-Za-z0-9_-]{1,64}; job dir = work_dir/<job_id>
  std::string input;   // JPEG/PNG/WebP, or HEIC/AVIF/... via the platform decoder
  std::string sr_model = "sr.general-x4v3";
  int scale = 4;                 // 8 | 4 | 2 | 1 (ADR-0014; 8: x4 twice, input <= 1.5 MP)
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
  // FR-FACE-005: CodeFormer's fidelity w (0 detail .. 1 likeness); other face models ignore it.
  double face_fidelity = 0.7;
  bool face_color_match = true;  // FR-FACE-008: on by default
  // FR-FACE-006 region: "sr" (the SR model, regions All/Background) or "lanczos" (region Faces:
  // only faces are restored, the rest is a Lanczos-3 upscale and the SR model is not run).
  std::string background = "sr";
  // FR-FACE-007: faces the user turned off, as enh_analyze listed them (input pixels after
  // EXIF orientation). A detected face matching one of them is not restored.
  std::vector<FaceBox> faces_off;
  // FR-ENH-015 fragment preview: only this part of the oriented input (x, y, w, h; w = 0: the
  // whole input). Each side 16..2048.
  int crop_x = 0, crop_y = 0, crop_w = 0, crop_h = 0;
  // S9 JPEG cleanup: a JPEG pack id ("" = off) run 1x before faces and SR, and its quality
  // factor 0..1 (1 - quality/100); < 0: from the input's quantization table (quality 50 when
  // the input is not a JPEG).
  std::string jpeg_model;
  double jpeg_qf = -1;
  // S9 scratch removal: the detector and the inpainting pack ids (both or neither; "" = off),
  // run 1x after the JPEG cleanup, before faces and SR.
  std::string scratch_model;
  std::string inpaint_model;
  // S9 low light: the HVI-CIDNet pack id ("" = off), run 1x after the JPEG cleanup, before the
  // scratch removal.
  std::string lowlight_model;
  // ADR-0025: SR runs on the input area-downscaled to this factor (its effective resolution,
  // enh_analyze "eff_scale"), and its result is Lanczos-resampled to the size it has without
  // it. With fast2 the factor is min(0.5, pre_down). (0, 1]; 1: off; not with 8x.
  double pre_down = 1.0;
  // ADR-0025: luma unsharp mask of the result before the faces are pasted (unsharp_luma
  // amount), 0..1.5; 0: off.
  double sharpen = 0.0;
};

JobRequest parse_job_request(const std::string& json);  // throws Error(ENH_E_INVALID)
nlohmann::json job_request_to_json(const JobRequest& r);

// Files inside a job directory.
inline constexpr const char* kRequestFile = "request.json";
inline constexpr const char* kResultFile = "result.json";
inline constexpr const char* kPreviewFile = "preview.jpg";
inline constexpr const char* kSourceExifFile = "source.exif";  // TIFF block of the input
inline constexpr const char* kSourceIccFile = "source.icc";
// FR-IMP-007: the input's alpha, oriented, 1 byte per pixel (result.json "alpha" has its size).
inline constexpr const char* kAlphaFile = "alpha.raw";
// FR-ENH-003: the first pass of 8x (x4), a band store of its own; removed when the job is done.
inline constexpr const char* kX8Dir = "x8";
inline constexpr double kMaxX8InputPx = 1.5e6;  // ADR-0014
// ADR-0025: the SR pass of a job with pre_down or sharpen, a band store of its own; the result
// bands are made from it (resample, sharpen, faces) and it is removed when the job is done.
inline constexpr const char* kPreDir = "pre";
}  // namespace enh
