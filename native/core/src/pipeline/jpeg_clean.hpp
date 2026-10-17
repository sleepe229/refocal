// JPEG cleanup (S9, 1.1): the FBCNN restore graph removes blocking and ringing in a 1x pass
// before SR. It takes the tile and the JPEG quality factor qf = 1 - quality/100 (from the
// file's quantization table, or set by the user). Tiles have a reflect pad; the network input
// is rounded up to a multiple of 8 (three stride-2 levels) by reflecting a little further.
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <functional>

#include "backend/backend.hpp"
#include "image/image.hpp"

namespace enh {

inline constexpr int kJpegCleanMultiple = 8;

// qf of an IJG quality 1..100; quality 0 (unknown) gives the default of quality 50.
float jpeg_qf_of_quality(int quality);

// Runs [be] (inputs: tile, qf as a 1x1x1 Mat) over [img]. [tick](done, total) after each tile;
// returning false stops (the caller throws). Throws enh::Error from the backend.
Rgb8 jpeg_clean(InferenceBackend& be, const Rgb8& img, float qf, int tile, int pad,
                const std::function<bool(int, int)>& tick = {});

}  // namespace enh
