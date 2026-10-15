// Faces (ADR-0012: DetectFaces -> RestoreFaces -> FacePaste in SRBanded; ADR-0022/0023):
// YuNet detection on a <= 640 px copy, 5-point similarity alignment to the FFHQ-512 template,
// restoration of each aligned face by the face model (GFPGAN: 512x512, values in [-1, 1]),
// and pasting the restored faces into the SR output band by band with a feathered mask,
// weighted by faceStrength.
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <cstdint>
#include <vector>

#include "image/image.hpp"

namespace enh {

class InferenceBackend;

// A detected face in image coordinates: box, 5 landmarks (right eye, left eye, nose, mouth
// right, mouth left as YuNet reports them), confidence.
struct Face {
  float x = 0, y = 0, w = 0, h = 0;
  float lm[10] = {};
  float score = 0;
};

inline constexpr int kYunetSide = 640;

// YuNet 2023mar (input BGR 0..255, 640x640; 12 outputs: cls/obj/bbox/kps at strides 8/16/32,
// as OpenCV FaceDetectorYN decodes them). The image is scaled to fit 640 and padded. Largest
// face first.
std::vector<Face> detect_faces(InferenceBackend& yunet, const Rgb8& img, float min_score = 0.7f,
                               float nms_iou = 0.3f);

// dst = A * src: x' = a*x + b*y + tx, y' = c*x + d*y + ty.
struct Affine {
  double a = 1, b = 0, tx = 0, c = 0, d = 1, ty = 0;
  Affine inverse() const;
  Affine scaled(double s) const;  // source coordinates multiplied by s first (the SR scale)
  void apply(double x, double y, double* ox, double* oy) const {
    *ox = a * x + b * y + tx;
    *oy = c * x + d * y + ty;
  }
};

inline constexpr int kFaceSide = 512;

// Least-squares similarity (rotation, uniform scale, translation; no reflection) taking the
// 5 landmarks of [f] to the FFHQ-512 template, as cv2.estimateAffinePartial2D does without
// outlier rejection.
Affine face_alignment(const Face& f);

// Bilinear warp: out(x, y) = src(inverse(m)(x, y)), reflect-101 at the borders.
Rgb8 warp_affine(const Rgb8& src, const Affine& m, int w, int h);

// Runs the face model on an aligned 512x512 face (GFPGAN io: RGB in [-1, 1] both ways).
Rgb8 restore_face(InferenceBackend& model, const Rgb8& aligned);

// A restored face ready to paste: [to_face] maps SR-output coordinates to the 512 face.
struct RestoredFace {
  Affine to_face;
  Rgb8 face;
  float strength = 0.5f;               // faceStrength x per-face weight (ADR-0022: 0.5 by default)
  int y0 = 0, y1 = 0, x0 = 0, x1 = 0;  // bounding rows/cols in the SR output
};

// [align] maps input-image coordinates to the face; [scale]: SR output / input.
RestoredFace prepare_paste(const Affine& align, Rgb8 restored, int scale, float strength, int out_w,
                           int out_h);

// Blends the faces into rows [y, y + rows) of an RGB8 SR band of width [w].
void paste_faces(uint8_t* band, int w, int y, int rows, const std::vector<RestoredFace>& faces);

}  // namespace enh
