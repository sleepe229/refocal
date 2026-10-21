#!/usr/bin/env python3
"""The real photos of the golden set (04 §7.2): ml/golden/golden.lock lists each one (one JSON
object per line: category, name, sha256, url, licence, author, page), the photos stay out of
git. This downloads and verifies them, and writes ml/golden/SOURCES.md from the lock.

  python3 tools/ml/golden_fetch.py DIR [--lock ml/golden/golden.lock]
  python3 tools/ml/golden_fetch.py --sources        # rewrite SOURCES.md
  python3 tools/ml/golden_fetch.py --check-sources  # fail if SOURCES.md is not the lock's
"""

import argparse
import hashlib
import json
import pathlib
import sys
import time
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[2]
LOCK = ROOT / "ml/golden/golden.lock"
SOURCES = ROOT / "ml/golden/SOURCES.md"
UA = {"User-Agent": "refocal-golden/1.0 (https://github.com/sleepe229/refocal)"}


def entries(lock: pathlib.Path) -> list[dict]:
    return [json.loads(line) for line in lock.read_text().splitlines() if line.strip()]


def fetch_all(lock: pathlib.Path, dst: pathlib.Path) -> list[dict]:
    """Every photo of [lock] in [dst], verified; the entries with their "path"."""
    dst.mkdir(parents=True, exist_ok=True)
    out = []
    for e in entries(lock):
        p = dst / f"{e['category']}_{e['name']}"
        if not p.exists() or hashlib.sha256(p.read_bytes()).hexdigest() != e["sha256"]:
            for i in range(4):
                try:
                    req = urllib.request.Request(e["url"], headers=UA)
                    with urllib.request.urlopen(req, timeout=120) as r:
                        p.write_bytes(r.read())
                    break
                except OSError:
                    time.sleep(3 * (i + 1))
        got = hashlib.sha256(p.read_bytes()).hexdigest() if p.exists() else "missing"
        if got != e["sha256"]:
            sys.exit(f"{e['name']}: sha256 {got}, expected {e['sha256']}")
        out.append({**e, "path": str(p)})
    return out


def sources(lock: pathlib.Path) -> str:
    rows = [
        "# Golden set: real photos",
        "",
        "Generated from `golden.lock` by `tools/ml/golden_fetch.py --sources`; the photos are",
        "downloaded and verified by SHA-256, not kept in git (04 §7.2). Wikimedia Commons, each",
        "under the licence named; every photo was looked at before it went in (no faces).",
        "",
        "| Category | Photo | Author | Licence |",
        "|---|---|---|---|",
    ]
    for e in entries(lock):
        author = e["author"].replace("|", "/").replace("\n", " ")
        rows.append(f"| {e['category']} | [{e['name']}]({e['page']}) | {author} | {e['licence']} |")
    return "\n".join(rows) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("dir", nargs="?")
    ap.add_argument("--lock", default=str(LOCK))
    ap.add_argument("--sources", action="store_true")
    ap.add_argument("--check-sources", action="store_true")
    a = ap.parse_args()
    lock = pathlib.Path(a.lock)
    if a.sources:
        SOURCES.write_text(sources(lock))
        return 0
    if a.check_sources:
        if SOURCES.read_text() != sources(lock):
            sys.exit("ml/golden/SOURCES.md is not generated from golden.lock")
        return 0
    if not a.dir:
        ap.error("DIR is required")
    for e in fetch_all(lock, pathlib.Path(a.dir)):
        print("ok", e["category"], e["name"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
