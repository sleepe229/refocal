#!/usr/bin/env python3
"""Writes app-update.json (ADR-0027) for a published release.

The feed keeps the latest stable release and, if it is newer, the latest pre-release. The
previous feed (already verified by the caller) gives the other channel's entry.

  tools/release/make_app_update.py --previous OLD|- --tag vX --apk FILE --url URL \\
      --version-code N --min-sdk N --notes-en FILE --notes-ru FILE [--prerelease] OUT
"""

import argparse
import hashlib
import json
import pathlib
import sys


def entry(args: argparse.Namespace) -> dict:
    apk = pathlib.Path(args.apk)
    notes = {"en": pathlib.Path(args.notes_en).read_text().strip()}
    ru = pathlib.Path(args.notes_ru)
    if ru.exists():
        notes["ru"] = ru.read_text().strip()
    return {
        "version_code": args.version_code,
        "version_name": args.tag.removeprefix("v"),
        "urls": [args.url],
        "size": apk.stat().st_size,
        "sha256": hashlib.sha256(apk.read_bytes()).hexdigest(),
        "min_sdk": args.min_sdk,
        "notes": notes,
    }


def merge(previous: dict | None, new: dict, prerelease: bool) -> dict:
    stable = (previous or {}).get("stable")
    beta = (previous or {}).get("beta")
    if prerelease:
        beta = new
    else:
        stable = new
    if beta and stable and beta["version_code"] <= stable["version_code"]:
        beta = None  # the stable release is newer: beta users get it too
    return {"schema": 1, "stable": stable, "beta": beta}


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--previous", required=True)
    p.add_argument("--tag", required=True)
    p.add_argument("--apk", required=True)
    p.add_argument("--url", required=True)
    p.add_argument("--version-code", type=int, required=True)
    p.add_argument("--min-sdk", type=int, required=True)
    p.add_argument("--notes-en", required=True)
    p.add_argument("--notes-ru", required=True)
    p.add_argument("--prerelease", action="store_true")
    p.add_argument("out")
    args = p.parse_args()
    if not args.url.startswith("https://"):
        sys.exit("url must be https")
    previous = None if args.previous == "-" else json.loads(pathlib.Path(args.previous).read_text())
    if previous and previous.get("schema") != 1:
        sys.exit("previous feed: unknown schema")
    for old in (previous or {}).get("stable"), (previous or {}).get("beta"):
        if old and old["version_code"] >= args.version_code and not args.prerelease:
            sys.exit(f"versionCode {args.version_code} is not newer than {old['version_code']}")
    feed = merge(previous, entry(args), args.prerelease)
    pathlib.Path(args.out).write_text(json.dumps(feed, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(feed, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
