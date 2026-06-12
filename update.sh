#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/entries"

echo "Fetching releases.hashicorp.com/index.json ..."
curl -sf https://releases.hashicorp.com/index.json -o "$tmpdir/index.json"

echo "Resolving versions ..."
jq -r '
  to_entries[] | select(.value.versions) |
  .key as $p | .value.versions | to_entries[] |
  select(.key | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) |
  .key as $v | (.value.builds // []) |
  if any(
    (.filename | endswith(".zip")) and
    ((.os == "linux" or .os == "darwin") and (.arch == "amd64" or .arch == "arm64"))
  )
  then "\($p)\t\($v)"
  else empty end
' "$tmpdir/index.json" | sort -t$'\t' -k1,1 -k2,2V > "$tmpdir/all.tsv"

total=$(wc -l < "$tmpdir/all.tsv")

# Incremental: skip versions already present in versions.json
if [[ -f versions.json ]] && jq -e . versions.json &>/dev/null; then
  jq -r '
    to_entries[] | .key as $p |
    (.value.versions // {}) | keys[] | "\($p)\t\(.)"
  ' versions.json | sort -t$'\t' -k1,1 -k2,2V > "$tmpdir/existing.tsv"
  comm -23 "$tmpdir/all.tsv" "$tmpdir/existing.tsv" > "$tmpdir/new.tsv"
  cp versions.json "$tmpdir/base.json"
else
  cp "$tmpdir/all.tsv" "$tmpdir/new.tsv"
  echo '{}' > "$tmpdir/base.json"
fi

new_count=$(wc -l < "$tmpdir/new.tsv")
echo "Total: $total versions, $new_count new"

if [[ "$new_count" -eq 0 ]]; then
  echo "--- up to date ---"
  exit 0
fi

# Worker script for parallel SHA256SUMS fetching
cat > "$tmpdir/fetch.sh" << 'FETCH'
set -euo pipefail
product=$1 version=$2 outdir=$3
shasums=$(curl -sf \
  "https://releases.hashicorp.com/${product}/${version}/${product}_${version}_SHA256SUMS" 2>/dev/null) || exit 0
shas='{}'
for p in linux_amd64 linux_arm64 darwin_amd64 darwin_arm64; do
  hex=$(echo "$shasums" | grep "${product}_${version}_${p}.zip" | awk '{print $1}' | tr -d '\r\n') || true
  [[ -n "$hex" ]] && \
    shas=$(echo "$shas" | jq --arg k "$p" \
      --arg v "sha256-$(echo -n "$hex" | xxd -r -p | base64 -w0)" \
      '. + {($k): $v}')
done
[[ "$shas" != '{}' ]] && \
  jq -nc --arg p "$product" --arg v "$version" --argjson s "$shas" \
    '{p:$p,v:$v,s:$s}' > "${outdir}/${product}___${version}.json"
FETCH

echo "Fetching checksums ($new_count, 16 parallel) ..."
awk -F'\t' -v d="$tmpdir/entries" '{print $1; print $2; print d}' "$tmpdir/new.tsv" \
  | xargs -P 16 -n 3 bash "$tmpdir/fetch.sh"

fetched=$(find "$tmpdir/entries" -name '*.json' 2>/dev/null | wc -l)
echo "Fetched: $fetched"

echo "Merging ..."
{
  cat "$tmpdir/base.json"
  cat "$tmpdir"/entries/*.json 2>/dev/null || true
} | jq -S -s '
  .[0] as $base |
  reduce .[1:][] as $e ($base;
    .[$e.p].versions[$e.v] = $e.s
  ) |
  with_entries(
    (.value.versions // {}) as $vs |
    .value.latest = (
      [$vs | keys[] | split(".") | map(tonumber)] | sort | last |
      map(tostring) | join(".")
    )
  )
' > versions.json

products=$(jq 'length' versions.json)
total_ver=$(jq '[.[] | .versions | length] | add // 0' versions.json)
echo "--- done: $products products, $total_ver versions ---"
