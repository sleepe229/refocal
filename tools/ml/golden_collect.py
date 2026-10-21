#!/usr/bin/env python3
"""Proposes real photos for the golden set (04 §7.2) from Wikimedia Commons: files of a few
categories under CC0, CC BY or public domain (no ShareAlike, no NC), at most MAX_MP, picked in a
stable order (SHA-1 of the title), with their licence, author and page. The output is a draft
of ml/golden/golden.lock: a person looks at every photo before it goes in (no faces, the
category is right, 04 §7.2).

  python3 tools/ml/golden_collect.py [--per 12] > draft.lock
"""

import argparse
import hashlib
import json
import re
import sys
import time
import urllib.parse
import urllib.request

API = "https://commons.wikimedia.org/w/api.php"
# Golden category -> Commons categories (real photos, no reference).
SOURCES = {
    "compact": ["Taken with Canon PowerShot A520", "Taken with Kodak EasyShare C340"],
    "phone": ["Taken with Nokia N95"],
    "noise": ["Image noise"],
    "blur": ["Motion blur"],
    "jpeg": ["Compression artifacts", "JPEG artifacts"],
    "lowlight": ["Low light photography"],
}
LICENCES = re.compile(r"^(CC0|CC BY \d\.\d|CC BY \d\.\d [a-z-]+|Public domain|PD)$", re.I)
MAX_MP = 3.2
MIN_SIDE = 320
UA = {"User-Agent": "refocal-golden/1.0 (https://github.com/sleepe229/refocal)"}


def get(params: dict) -> dict:
    url = API + "?" + urllib.parse.urlencode({**params, "format": "json"})
    for i in range(4):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
                return json.load(r)
        except OSError:
            time.sleep(2 * (i + 1))
    raise SystemExit(f"Commons API failed: {url}")


def members(cat: str) -> list[str]:
    out, cont = [], {}
    while True:
        d = get(
            {
                "action": "query",
                "list": "categorymembers",
                "cmtitle": f"Category:{cat}",
                "cmtype": "file",
                "cmlimit": 500,
                **cont,
            }
        )
        out += [m["title"] for m in d["query"]["categorymembers"]]
        if "continue" not in d or len(out) >= 2000:
            return out
        cont = d["continue"]


def info(titles: list[str]) -> list[dict]:
    d = get(
        {
            "action": "query",
            "titles": "|".join(titles),
            "prop": "imageinfo",
            "iiprop": "url|size|mime|extmetadata",
            "iiurlwidth": 250,
        }
    )
    out = []
    for p in d["query"]["pages"].values():
        ii = (p.get("imageinfo") or [None])[0]
        if not ii or ii.get("mime") != "image/jpeg":
            continue
        meta = ii.get("extmetadata", {})
        lic = meta.get("LicenseShortName", {}).get("value", "")
        artist = re.sub(r"<[^>]+>", "", meta.get("Artist", {}).get("value", "")).strip()
        if not LICENCES.match(lic) or "SA" in lic.upper().split():
            continue
        if ii["width"] * ii["height"] > MAX_MP * 1e6 or min(ii["width"], ii["height"]) < MIN_SIDE:
            continue
        out.append(
            {
                "title": p["title"],
                "url": ii["url"].split("?")[0],
                "thumb": ii.get("thumburl", "").split("?")[0],
                "page": ii["descriptionurl"].split("?")[0],
                "licence": lic,
                "author": artist or "unknown",
                "w": ii["width"],
                "h": ii["height"],
            }
        )
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--per", type=int, default=12)
    a = ap.parse_args()
    for cat, sources in SOURCES.items():
        titles = sorted(
            {t for s in sources for t in members(s)},
            key=lambda t: hashlib.sha1(t.encode()).hexdigest(),
        )
        picked = []
        for i in range(0, len(titles), 50):
            picked += info(titles[i : i + 50])
            if len(picked) >= a.per * 3:
                break
        for p in picked[: a.per * 3]:
            name = re.sub(r"[^A-Za-z0-9._-]+", "_", p["title"].removeprefix("File:"))[:80]
            print(json.dumps({"category": cat, "name": name, **p}, ensure_ascii=False))
        print(f"{cat}: {len(picked)} candidates from {len(titles)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
