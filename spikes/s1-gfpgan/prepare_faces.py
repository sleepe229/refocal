"""Detect faces with YuNet, align them to the FFHQ-512 template, save 512x512 crops.

Two variants per face:
  * "<name>_fNN.png"      — aligned crop from the original (real old-photo degradation);
  * "<name>_fNN_lq.png"   — synthetic low quality: face downscaled to ~96 px + JPEG q35, then
    aligned.
"""

from pathlib import Path

import cv2
import numpy as np

HERE = Path(__file__).resolve().parent
RAW = HERE / "data" / "raw"
OUT = HERE / "data" / "faces"
YUNET = HERE / "weights" / "face_detection_yunet_2023mar.onnx"

# FFHQ 512 five-point template (facexlib face_restoration_helper.py).
FFHQ_512 = np.array(
    [
        [192.98138, 239.94708],
        [318.90277, 240.19366],
        [256.63416, 314.01935],
        [201.26117, 371.41043],
        [313.08905, 371.15118],
    ],
    dtype=np.float32,
)

MAX_FACES_PER_IMAGE = 4


def detect(img: np.ndarray, analyze_side: int = 640) -> np.ndarray:
    """Detect on a copy downscaled to `analyze_side` (as in the spec's Analyze stage), return
    full-res coords."""
    h, w = img.shape[:2]
    s = min(1.0, analyze_side / max(h, w))
    small = cv2.resize(img, None, fx=s, fy=s, interpolation=cv2.INTER_AREA) if s < 1 else img
    sh, sw = small.shape[:2]
    det = cv2.FaceDetectorYN.create(
        str(YUNET), "", (sw, sh), score_threshold=0.7, nms_threshold=0.3
    )
    _, faces = det.detect(small)
    if faces is None:
        return np.zeros((0, 15), np.float32)
    faces = faces.copy()
    faces[:, :14] /= s
    return faces[faces[:, 2].argsort()[::-1]]  # largest first


def landmarks(face: np.ndarray) -> np.ndarray:
    # YuNet row: x, y, w, h, (re_x, re_y), (le_x, le_y), (nose), (rm), (lm), score.
    # Order for the template: left eye (image left), right eye, nose, mouth left, mouth right.
    return face[4:14].reshape(5, 2).astype(np.float32)


def align(img: np.ndarray, lm: np.ndarray) -> np.ndarray:
    m, _ = cv2.estimateAffinePartial2D(lm, FFHQ_512, method=cv2.LMEDS)
    return cv2.warpAffine(
        img, m, (512, 512), flags=cv2.INTER_CUBIC, borderMode=cv2.BORDER_REFLECT_101
    )


def degrade(img: np.ndarray, face_w: float, target_face_w: float = 96.0) -> np.ndarray:
    s = min(1.0, target_face_w / max(face_w, 1.0))
    small = cv2.resize(img, None, fx=s, fy=s, interpolation=cv2.INTER_AREA)
    ok, buf = cv2.imencode(".jpg", small, [cv2.IMWRITE_JPEG_QUALITY, 35])
    return cv2.imdecode(buf, cv2.IMREAD_COLOR), s


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    total = 0
    for path in sorted(RAW.glob("*.jpg")):
        img = cv2.imread(str(path), cv2.IMREAD_COLOR)
        faces = detect(img)
        stem = path.stem.split("_(")[0][:24]
        print(f"{path.name}: {len(faces)} faces")
        for i, f in enumerate(faces[:MAX_FACES_PER_IMAGE]):
            lm = landmarks(f)
            cv2.imwrite(str(OUT / f"{stem}_f{i:02d}.png"), align(img, lm))
            lq, s = degrade(img, float(f[2]))
            cv2.imwrite(str(OUT / f"{stem}_f{i:02d}_lq.png"), align(lq, lm * s))
            total += 2
    print(f"saved {total} aligned crops to {OUT}")


if __name__ == "__main__":
    main()
