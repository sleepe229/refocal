#!/usr/bin/env bash
# Known vulnerabilities in third-party code (SEC-INP-006): Dart packages from pubspec.lock via
# osv-scanner, and every pinned git submodule by its commit via the OSV API (C/C++ libraries have
# no package ecosystem; OSV maps their fix commits from OSS-Fuzz, NVD and GHSA). Findings listed in
# tools/osv/ignore.txt with a reason are reported but do not fail. Vendored SQLite
# (native/third_party/sqlite) is not covered by OSV: follow sqlite.org/cves.html on updates.
#
# Usage: tools/osv/check.sh [osv-scanner binary]
set -euo pipefail
cd "$(dirname "$0")/../.."
OSV=${1:-osv-scanner}
IGNORE=tools/osv/ignore.txt
fail=0

ignored() { grep -qE "^$1[[:space:]]" "$IGNORE"; }

echo "== pubspec.lock"
ids=$({ "$OSV" scan source --format json -L pubspec.lock 2>/dev/null || true; } | python3 -c '
import json, sys
d = json.load(sys.stdin)
for r in d.get("results") or []:
    for p in r.get("packages", []):
        for v in p.get("vulnerabilities", []):
            print(v["id"], p["package"]["name"], p["package"]["version"])
')
while read -r id rest; do
  [ -z "$id" ] && continue
  if ignored "$id"; then echo "ignored $id $rest"; else echo "FOUND $id $rest"; fail=1; fi
done <<< "$ids"

echo "== submodules"
while read -r _ type sha path; do
  [ "$type" = commit ] || continue
  ids=$(curl -sf -X POST https://api.osv.dev/v1/query -d "{\"commit\":\"$sha\"}" |
    python3 -c 'import json, sys; [print(v["id"]) for v in json.load(sys.stdin).get("vulns", [])]')
  for id in $ids; do
    if ignored "$id"; then echo "ignored $id $path"; else echo "FOUND $id $path@$sha"; fail=1; fi
  done
done < <(git ls-tree HEAD flutter native/third_party/)

[ "$fail" = 0 ] && echo "no unhandled vulnerabilities"
exit "$fail"
