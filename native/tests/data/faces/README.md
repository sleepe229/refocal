Face test inputs for native/tests/test_faces.cpp, downscaled from public-domain photographs on
Wikimedia Commons (spike S1): "Solvay conference 1927" (Benjamin Couprie, 1927) and "Albert
Einstein Head" (Orren Jack Turner, 1947). `opencv_yunet.json`: OpenCV FaceDetectorYN with
YuNet 2023mar on the same images (score 0.7, NMS 0.3, longest side 640), rows
x, y, w, h, 5 landmarks in image pixels: the reference the core's detector is checked against.
