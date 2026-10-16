// Analyze (ADR-0012, FR-ENH-007): what Auto decides from: size, faces (YuNet when the detector
// is installed), and a noise estimate (Immerkaer 1996: the Laplacian-difference operator on the
// luma of a copy <= 1024 px; sigma in 8-bit levels).
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <nlohmann/json.hpp>
#include <string>

#include "image/image.hpp"

struct enh_session;

namespace enh {

// sigma of additive Gaussian noise, in 8-bit levels.
double estimate_noise(const Rgb8& img);

// {"schema": 1, "width", "height", "megapixels", "noise_sigma", "faces": {"count",
// "largest_px", "detector": bool, "boxes": [[x, y, w, h], ...]}}: the faces a job restores
// (keep_restorable), largest first, in pixels of the oriented input; a box can be passed back
// in the request's faces_off (FR-FACE-007).
nlohmann::json analyze_image(enh_session& s, const std::string& path,
                             const std::string& det_model = "det.yunet-2023mar");

}  // namespace enh
