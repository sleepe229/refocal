#!/usr/bin/env bash
# Builds app/assets/licenses/native.json: licenses of everything in libenh.so, of SQLite
# (libsqlite3.so, built by package:sqlite3's hook) and of the bundled model, shown on the in-app
# Licenses screen next to Flutter's own package licenses, and of Android libraries the
# registry does not see (androidx.heifwriter).
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
    ("Monocypher", "native/third_party/monocypher/LICENCE.md"),
    ("Dart API DL", "native/third_party/dart_api_dl/LICENSE"),
    ("SQLite", "tools/licenses/upstream/SQLite.LICENSE"),
    # Android libraries outside Flutter's license registry (HEIC output, FR-EXP-002).
    ("AndroidX HeifWriter (Apache-2.0)", "LICENSE"),
    ("Real-ESRGAN (model weights: sr.general-x4v3)", "tools/licenses/upstream/Real-ESRGAN.LICENSE"),
    ("YuNet (model weights: det.yunet-2023mar)", "tools/licenses/upstream/YuNet.LICENSE"),
]
out = []
for name, path in entries:
    text = (root / path).read_text(encoding="utf-8", errors="replace")
    out.append({"package": name, "text": text})
dst = root / "app/assets/licenses/native.json"
dst.write_text(json.dumps(out, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
print(f"{dst.relative_to(root)}: {len(out)} entries")
PY
