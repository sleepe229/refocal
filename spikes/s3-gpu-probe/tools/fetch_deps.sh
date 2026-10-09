#!/usr/bin/env bash
# Fetch header-only nlohmann/json v3.11.3 (MIT) into third_party/ (gitignored), verify SHA-256.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p third_party/nlohmann
url=https://github.com/nlohmann/json/releases/download/v3.11.3/json.hpp
sha=9bea4c8066ef4a1c206b2be5a36302f8926f7fdc6087af5d20b417d0cf103ea6
[[ -f third_party/nlohmann/json.hpp ]] || curl -fsSL -o third_party/nlohmann/json.hpp "$url"
echo "$sha  third_party/nlohmann/json.hpp" | sha256sum -c -
