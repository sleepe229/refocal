#!/usr/bin/env python3
"""Builds the offline pack (.rfpack, ADR-0011, FR-MODEL-006) of one pack of a manifest:

  manifest.json          the manifest with only this pack (same schema, serial and dates)
  manifest.json.minisig  its minisign signature (key A in CI)
  license.txt            the license text (its SHA-256 is license.text_sha256)
  <file path>...         the pack's ncnn files, each checked against size and SHA-256

Entries are flat names, as the core requires (SEC-INP-005). The app verifies the signature
before it reads the manifest, then every file as for a download.

  tools/models/make_rfpack.py MANIFEST PACK_ID OUT_DIR SECRET_KEY
"""

import json
import pathlib
import subprocess
import sys
import tempfile
import zipfile

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from check_manifest import fetch, sha256  # noqa: E402


def main() -> int:
    manifest, pack_id, out, key = sys.argv[1:5]
    m = json.loads(pathlib.Path(manifest).read_text())
    pack = next(p for p in m["packs"] if p["id"] == pack_id)
    files = [f for f in pack["files"] if f["backend"] == "ncnn"]
    with tempfile.TemporaryDirectory() as tmp:
        t = pathlib.Path(tmp)
        sub = t / "manifest.json"
        sub.write_text(json.dumps({**m, "packs": [{**pack, "files": files}]}, indent=2) + "\n")
        comment = f"refocal rfpack {pack_id}@{pack['version']} serial:{m['serial']}"
        subprocess.run(
            ["minisign", "-S", "-s", key, "-m", str(sub), "-t", comment],
            check=True,
            stdin=subprocess.DEVNULL,
        )
        fetch(pack["license"]["url"], t / "license.txt")
        if sha256(t / "license.txt") != pack["license"]["text_sha256"]:
            sys.exit(f"license mismatch: {pack_id}")
        for f in files:
            path = t / f["path"]
            fetch(f["urls"][0], path)
            if path.stat().st_size != f["size"] or sha256(path) != f["sha256"]:
                sys.exit(f"mismatch: {pack_id}/{f['path']}")
        dst = pathlib.Path(out) / f"{pack_id}-{pack['version']}.rfpack"
        dst.parent.mkdir(parents=True, exist_ok=True)
        names = ["manifest.json", "manifest.json.minisig", "license.txt"] + [
            f["path"] for f in files
        ]
        with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
            for n in names:
                z.write(t / n, n)
    print(f"{dst} ({dst.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
