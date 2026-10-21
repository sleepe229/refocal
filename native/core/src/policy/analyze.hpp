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

// ADR-0025: the photo's effective resolution as a factor in (0, 1]: the largest area downscale
// f in {1, 0.7, 0.5, 0.35, 0.25} (interpolated) at which its strongest edges are already steep
// (median |Sobel| / local 5x5 range over the top 2% of edges >= tau), the geometric mean of an
// isotropic measure and the worst of 4 gradient orientations (motion blur). Full resolution,
// on the 16 tiles of 256 px with most contrast; deterministic. 1 when no edges are found.
double estimate_eff_scale(const Rgb8& img);

// The step of estimate_eff_scale from a steepness profile over its 5 factors (NaN: a level
// without enough edges) to f: the largest factor whose steepness reaches tau, interpolated in
// log f from the last level with edges before it (none: that factor itself); 1 without any
// edges; for tests.
inline constexpr int kEffCrossingLevels = 5;
double eff_crossing(const double (&prof)[kEffCrossingLevels], double tau);

// {"schema": 1, "width", "height", "megapixels", "noise_sigma", "eff_scale", "faces": {"count",
// "largest_px", "detector": bool, "boxes": [[x, y, w, h], ...]}}: the faces a job restores
// (keep_restorable), largest first, in pixels of the oriented input; a box can be passed back
// in the request's faces_off (FR-FACE-007).
nlohmann::json analyze_image(enh_session& s, const std::string& path,
                             const std::string& det_model = "det.yunet-2023mar");

}  // namespace enh
