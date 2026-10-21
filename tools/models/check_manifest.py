#!/usr/bin/env python3
"""Checks tools/models/manifest.json before it is signed (ADR-0011): the schema
(docs/spec/appendix/manifest.schema.json, schema 2), a serial above the published one (the
schema 1 projection, manifest_v1.py), and every file of every pack downloaded from every mirror
with its size and SHA-256, the license texts too; a MODELS.md row for every pack and every
bundled model (ML-REG-001, TEST-COMP-004), naming the author of a credited pack (ADR-0026).

  tools/models/check_manifest.py [--published PATH]   # PATH: the manifest now in release `models`

GitHub release URLs of this (private) repository are fetched with `gh release download`.
"""

import argparse
import hashlib
import json
import pathlib
import re
import subprocess
import sys
import tempfile
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/models"))
from manifest_v1 import project  # noqa: E402

GH = re.compile(r"^https://github\.com/([^/]+/[^/]+)/releases/download/([^/]+)/(.+)$")


def fetch(url: str, dst: pathlib.Path, attempts: int = 3) -> None:
    for i in range(attempts):
        try:
            m = GH.match(url)
            if m:
                subprocess.run(
                    [
                        "gh",
                        "release",
                        "download",
                        m[2],
                        "--repo",
                        m[1],
                        "--pattern",
                        m[3],
                        "--output",
                        str(dst),
                        "--clobber",
                    ],
                    check=True,
                    capture_output=True,
                )
            else:
                with urllib.request.urlopen(url, timeout=60) as r, open(dst, "wb") as f:
                    while chunk := r.read(1 << 16):
                        f.write(chunk)
            return
        except (subprocess.CalledProcessError, OSError) as e:
            if i + 1 == attempts:
                raise SystemExit(f"cannot download {url}: {e}") from e
            time.sleep(2 * (i + 1))


def sha256(p: pathlib.Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        while chunk := f.read(1 << 20):
            h.update(chunk)
    return h.hexdigest()


def unregistered(m: dict) -> list[str]:
    """Pack and bundled model ids without a `| `id` |` row in MODELS.md."""
    rows = set(re.findall(r"^\| `([^`]+)` \|", (ROOT / "MODELS.md").read_text(), re.M))
    lock = (ROOT / "tools/models/models.lock").read_text().splitlines()
    ids = [p["id"] for p in m["packs"]] + [
        line.split()[0] for line in lock if line.strip() and line[0] != "#"
    ]
    return sorted({i for i in ids if i not in rows})


def uncredited(m: dict) -> list[str]:
    """Credited (CC-BY, CC-BY-SA) packs whose MODELS.md row does not name their author."""
    rows = {
        r[0]: r[1]
        for r in re.findall(r"^\| `([^`]+)` \|(.*)$", (ROOT / "MODELS.md").read_text(), re.M)
    }
    return [
        p["id"]
        for p in m["packs"]
        if p["license"]["class"] in ("attribution", "sharealike")
        and p["license"]["attribution"]["author"] not in rows.get(p["id"], "")
    ]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--published")
    a = ap.parse_args()
    import jsonschema

    schema = json.loads((ROOT / "docs/spec/appendix/manifest.schema.json").read_text())
    m = json.loads((ROOT / "tools/models/manifest.json").read_text())
    jsonschema.validate(m, schema)
    if a.published and pathlib.Path(a.published).exists():
        old = json.loads(pathlib.Path(a.published).read_text())
        if m["serial"] <= old["serial"] and project(m) != old:
            sys.exit(f"serial {m['serial']} must be above the published {old['serial']}")
    errors = [f"{i}: no row in MODELS.md" for i in unregistered(m)]
    errors += [f"{i}: MODELS.md row does not credit the author" for i in uncredited(m)]
    with tempfile.TemporaryDirectory() as tmp:
        dst = pathlib.Path(tmp) / "f"
        for p in m["packs"]:
            fetch(p["license"]["url"], dst)
            if sha256(dst) != p["license"]["text_sha256"]:
                errors.append(f"{p['id']}: license text hash")
            for f in p["files"]:
                for url in f["urls"]:
                    fetch(url, dst)
                    if dst.stat().st_size != f["size"] or sha256(dst) != f["sha256"]:
                        errors.append(f"{p['id']}/{f['path']}: {url}")
                    else:
                        print(f"ok {p['id']}/{f['path']} {url}")
    for e in errors:
        print("MISMATCH", e, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
