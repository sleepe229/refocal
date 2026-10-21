#!/usr/bin/env python3
"""Prints the schema 1 projection of a schema 2 manifest (ADR-0011 amendment, ADR-0026), for the
apps before 1.1, which read only `manifest.json` in schema 1 and refuse any field they do not
know. The projection has the same serial and dates and keeps the packs those apps can use as
the licence requires: not a credited (CC-BY, CC-BY-SA) pack, whose author they cannot show, and
not a pack of a category they do not know.

  tools/models/manifest_v1.py MANIFEST > manifest.json
"""

import json
import pathlib
import sys

V1_CATEGORIES = {"sr", "face", "det", "jpeg", "old", "color", "parse"}
CREDITED = {"attribution", "sharealike"}


def project(m: dict) -> dict:
    if m["schema"] != 2:
        raise SystemExit(f"not a schema 2 manifest: schema {m['schema']}")
    packs = []
    for p in m["packs"]:
        lic = p["license"]
        if p["category"] not in V1_CATEGORIES or lic["class"] in CREDITED:
            continue
        lic = {k: v for k, v in lic.items() if k not in ("class", "attribution")}
        packs.append({**p, "license": lic})
    return {**m, "schema": 1, "packs": packs}


def main() -> int:
    m = json.loads(pathlib.Path(sys.argv[1]).read_text())
    sys.stdout.write(json.dumps(project(m), indent=2, ensure_ascii=False) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
