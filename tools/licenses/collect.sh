#!/usr/bin/env bash
# Builds app/assets/licenses/native.json: licenses of everything in libenh.so and the bundled
# model, shown on the in-app Licenses screen next to Flutter's own package licenses.
# Rerun after updating a native submodule or a bundled model.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
python3 - "$ROOT" <<'PY'
import json, sys, pathlib
root = pathlib.Path(sys.argv[1])
entries = [
    ("ncnn", "native/third_party/ncnn/LICENSE.txt"),
    ("glslang (via ncnn)", "native/third_party/ncnn/glslang/LICENSE.txt"),
    ("libjpeg-turbo", "native/third_party/libjpeg-turbo/LICENSE.md"),
    ("libjpeg-turbo (IJG)", "native/third_party/libjpeg-turbo/README.ijg"),
    ("libpng", "native/third_party/libpng/LICENSE"),
    ("libwebp", "native/third_party/libwebp/COPYING"),
    ("libwebp (patent grant)", "native/third_party/libwebp/PATENTS"),
    ("nlohmann/json", "native/third_party/json/LICENSE.MIT"),
    ("Dart API DL", "native/third_party/dart_api_dl/LICENSE"),
    ("Real-ESRGAN (model weights: sr.general-x4v3)", "tools/licenses/upstream/Real-ESRGAN.LICENSE"),
]
out = []
for name, path in entries:
    text = (root / path).read_text(encoding="utf-8", errors="replace")
    out.append({"package": name, "text": text})
dst = root / "app/assets/licenses/native.json"
dst.write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
print(f"{dst.relative_to(root)}: {len(out)} entries")
PY
