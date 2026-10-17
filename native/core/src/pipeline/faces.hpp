// Faces (ADR-0012: DetectFaces -> RestoreFaces -> FacePaste in SRBanded; ADR-0022/0023):
// YuNet detection on a <= 640 px copy, 5-point similarity alignment to the FFHQ-512 template,
// restoration of each aligned face by the face model (GFPGAN: 512x512, values in [-1, 1]),
// and pasting the restored faces into the SR output band by band with a feathered mask,
// weighted by faceStrength.
// SPDX-License-Identifier: Apache-2.0
#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "backend/backend.hpp"
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

// Which detected faces are restored (the job) and listed (enh_analyze, FR-FACE-007): at least
// kMinFacePx on the short side, at most the kMaxFaces largest. detect_faces sorts largest first.
inline constexpr float kMinFacePx = 16;
inline constexpr size_t kMaxFaces = 32;
void keep_restorable(std::vector<Face>& faces);

// A face box the user turned off (FR-FACE-007), in the same coordinates as Face.
struct FaceBox {
  float x = 0, y = 0, w = 0, h = 0;
};
// Intersection over union of a detection and a box: >= kSameFaceIou is the same face.
float iou(const Face& f, const FaceBox& b);
inline constexpr float kSameFaceIou = 0.5f;

// YuNet 2023mar (input BGR 0..255, 640x640; 12 outputs: cls/obj/bbox/kps at strides 8/16/32,
// as OpenCV FaceDetectorYN decodes them). The image is scaled to fit 640 and padded. Largest
// face first.
std::vector<Face> detect_faces(InferenceBackend& yunet, const Rgb8& img, float min_score = 0.7f,
                               float nms_iou = 0.3f);

// #44: group photos where every face is under kMinFacePx. In a photo of at most kSmallPhotoPx,
// YuNet also looks at a kSmallFaceUpscale x bilinear upscale, in 640 px tiles (YuNet finds
// faces from about 10 px; 10 px becomes 30 px), with a stricter score. The faces, at least
// kMinSmallFacePx, come back in the photo's coordinates and are restored from its crops like
// the others.
inline constexpr double kSmallPhotoPx = 1.5e6;
inline constexpr int kSmallFaceUpscale = 3;
inline constexpr float kMinSmallFacePx = 8;
std::vector<Face> detect_small_faces(InferenceBackend& yunet, const Rgb8& img,
                                     float min_score = 0.8f);

// The faces a job restores and enh_analyze lists: detect_faces + keep_restorable, and
// detect_small_faces when that finds none in a small photo. Largest first.
std::vector<Face> find_faces(InferenceBackend& yunet, const Rgb8& img);

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

// A face pack (ADR-0011, ADR-0024): one graph (GFPGAN: model.ncnn.*), or CodeFormer split in
// two around its codebook lookup (encoder.ncnn.*, codebook.f32, generator.ncnn.*; model.json
// {"split": "codeformer"}), which takes the fidelity w (FR-FACE-005).
struct FaceModel {
  std::string id;
  bool split = false;
  ModelInfo main, encoder, generator;  // main: the one graph; encoder/generator: split
  std::vector<float> codebook;         // split: kCodebookSize x kCodeDim
};
inline constexpr int kCodebookSize = 1024, kCodeDim = 256, kCodeGrid = 16;
inline constexpr double kDefaultFidelity = 0.7;  // FR-FACE-005

// Throws ENH_E_MODEL when files are missing or do not match.
FaceModel resolve_face_model(const std::string& models_dir, const std::string& id);

// The face model loaded on one backend rung: one or two networks.
class FaceRestorer {
 public:
  FaceRestorer(const FaceModel& model, const BackendConfig& cfg);
  // [fidelity] 0..1: CodeFormer's w (0 = most detail from the codebook, 1 = closest to the
  // input); ignored by single-graph models.
  Rgb8 restore(const Rgb8& aligned, double fidelity);

 private:
  const FaceModel& model_;
  std::unique_ptr<InferenceBackend> a_, b_;
};

// CodeFormer's lookup (ADR-0024): per 16x16 token, the code with the largest logit (what
// torch.topk(softmax(logits), 1) picks), gathered into a [kCodeDim, 16, 16] feature.
// [logits]: kCodeGrid^2 rows of kCodebookSize.
ncnn::Mat codebook_lookup(const ncnn::Mat& logits, const std::vector<float>& codebook);

// FR-FACE-008: shifts the restored face so its mean CIELAB colour under the paste mask equals
// the original crop's (face models drift in colour, e.g. warm a sepia print). Returns the mean
// colour difference (CIE76 dE) before the shift.
double match_face_color(Rgb8& restored, const Rgb8& aligned);

// Mean CIELAB colour (D65) of [img] weighted by the paste mask; for tests.
void masked_mean_lab(const Rgb8& img, double lab[3]);

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
