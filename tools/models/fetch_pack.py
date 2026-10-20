#!/usr/bin/env python3
"""Downloads one pack of tools/models/manifest.json into DIR/<id>/ (ncnn files), checking size
and SHA-256 as the app does. For CI tests that need a pack (nightly faces).

  tools/models/fetch_pack.py PACK_ID DIR
"""

import hashlib
import json
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from check_manifest import fetch  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parents[2]


def main() -> int:
    pack_id, out = sys.argv[1], pathlib.Path(sys.argv[2])
    m = json.loads((ROOT / "tools/models/manifest.json").read_text())
    pack = next(p for p in m["packs"] if p["id"] == pack_id)
    dst = out / pack_id
    dst.mkdir(parents=True, exist_ok=True)
    for f in pack["files"]:
        if f["backend"] != "ncnn":
            continue
        path = dst / f["path"]
        fetch(f["urls"][0], path)
        h = hashlib.sha256(path.read_bytes()).hexdigest()
        if path.stat().st_size != f["size"] or h != f["sha256"]:
            sys.exit(f"mismatch: {pack_id}/{f['path']}")
        print(f"ok {pack_id}/{f['path']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
