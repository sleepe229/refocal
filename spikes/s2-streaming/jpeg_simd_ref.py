"""Reference: JPEG q92 encode speed of a 192 MP image with a SIMD libjpeg-turbo (OpenCV's bundled
one), to compare with the spike's non-SIMD static libjpeg-turbo. Holds the whole image in RAM —
desktop reference only, not part of the pipeline."""

import sys
import time

import cv2

cv2.setNumThreads(1)
img = cv2.imread(sys.argv[1])
big = cv2.resize(img, (img.shape[1] * 4, img.shape[0] * 4), interpolation=cv2.INTER_CUBIC)
print("libjpeg:", [line for line in cv2.getBuildInformation().splitlines() if "JPEG" in line][:2])
for _ in range(2):
    t = time.time()
    ok, buf = cv2.imencode(".jpg", big, [cv2.IMWRITE_JPEG_QUALITY, 92])
    dt = time.time() - t
    print(f"{big.shape[1]}x{big.shape[0]} JPEG q92: {dt:.2f} s, {len(buf) / 1e6:.1f} MB")
