#!/usr/bin/env bash
# Saves what failed in the given workflow runs, for the fix prompt. A failed
# check.yml job leaves ci-failure-<name>-<shard>/report.json; any other
# failed job gets the last 200 lines of its log as log-<job id>.txt.
# Usage: fix-collect.sh <owner/repo> <out dir> <run id>...
set -euo pipefail
GH=${GH:-gh}
repo=$1 out=$2
shift 2
mkdir -p "$out"
for run in "$@"; do
  arts=$("$GH" api "repos/$repo/actions/runs/$run/artifacts?per_page=100" --jq '.artifacts[] | "\(.name)\t\(.id)"')
  jobs=$("$GH" api "repos/$repo/actions/runs/$run/jobs?per_page=100" --jq '.jobs[] | select(.conclusion == "failure") | "\(.id)\t\(.name)"')
  while IFS=$'\t' read -r id name; do
    [ -n "$id" ] || continue
    leaf=${name##* / } # check.yml jobs show as "<caller job> / <name> (<shard>)"
    art=""
    if [[ $leaf =~ ^(.+)\ \(([0-9]+)\)$ ]]; then art="ci-failure-${BASH_REMATCH[1]}-${BASH_REMATCH[2]}"; fi
    art_id=$(awk -F'\t' -v n="$art" 'n != "" && $1 == n { print $2 }' <<<"$arts")
    if [ -n "$art_id" ]; then
      zip=$(mktemp)
      "$GH" api "repos/$repo/actions/artifacts/$art_id/zip" > "$zip"
      unzip -o -q "$zip" -d "$out/$art"
    else
      { echo "# $name"; "$GH" api "repos/$repo/actions/jobs/$id/logs" | sed -E 's/\x1b\[[0-9;?]*[A-Za-z]//g' | tail -n 200; } > "$out/log-$id.txt"
    fi
  done <<<"$jobs"
done
