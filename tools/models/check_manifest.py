#!/usr/bin/env python3
"""Checks tools/models/manifest.json before it is signed (ADR-0011): the schema
(docs/spec/appendix/manifest.schema.json), a serial above the published one, and every file of
every pack downloaded from every mirror with its size and SHA-256, the license texts too.

  tools/models/check_manifest.py [--published PATH]   # PATH: the manifest now in release `models`

GitHub release URLs of this (private) repository are fetched with `gh release download`.
"""
import argparse, hashlib, json, pathlib, re, subprocess, sys, tempfile, time, urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
GH = re.compile(r"^https://github\.com/([^/]+/[^/]+)/releases/download/([^/]+)/(.+)$")


def fetch(url: str, dst: pathlib.Path, attempts: int = 3) -> None:
    for i in range(attempts):
        try:
            m = GH.match(url)
            if m:
                subprocess.run(["gh", "release", "download", m[2], "--repo", m[1], "--pattern",
                                m[3], "--output", str(dst), "--clobber"], check=True,
                               capture_output=True)
            else:
                with urllib.request.urlopen(url, timeout=60) as r, open(dst, "wb") as f:
                    while chunk := r.read(1 << 16):
                        f.write(chunk)
            return
        except (subprocess.CalledProcessError, OSError) as e:
            if i + 1 == attempts:
                raise SystemExit(f"cannot download {url}: {e}")
            time.sleep(2 * (i + 1))


def sha256(p: pathlib.Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        while chunk := f.read(1 << 20):
            h.update(chunk)
    return h.hexdigest()


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
        if m["serial"] <= old["serial"] and m != old:
            sys.exit(f"serial {m['serial']} must be above the published {old['serial']}")
    errors = []
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
