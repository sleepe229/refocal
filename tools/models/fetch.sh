#!/usr/bin/env bash
# Puts the bundled model files into app/assets/models/<id>/ and verifies them against
# models.lock. Weights never go into git.
#   tools/models/fetch.sh --from DIR   # DIR holds <id>/model.ncnn.{param,bin} or spike names
#   tools/models/fetch.sh              # downloads from the URLs in models.lock
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
FROM=""
[[ "${1:-}" == "--from" ]] && FROM=${2:?}
while read -r id file sha url; do
  [[ -z "$id" || "$id" == \#* ]] && continue
  dst="$ROOT/app/assets/models/$id/$file"
  mkdir -p "$(dirname "$dst")"
  if [[ -n "$FROM" ]]; then
    src="$FROM/$id/$file"
    [[ -f "$src" ]] || src="$FROM/sr_compact_dn050.${file#model.}"   # spikes/_shared/models layout
    cp "$src" "$dst.part"
  elif [[ "$url" != "-" ]]; then
    curl -fsSL -o "$dst.part" "$url"
  else
    echo "no source for $id/$file: pass --from DIR (no published URL yet)" >&2
    exit 1
  fi
  echo "$sha  $dst.part" | sha256sum -c --quiet - || { rm -f "$dst.part"; echo "checksum mismatch: $id/$file" >&2; exit 1; }
  mv "$dst.part" "$dst"
  echo "ok $id/$file"
done < "$HERE/models.lock"
