#!/usr/bin/env bash
# Failure report of a check.yml job: job summary, one ::error annotation,
# report/report.json in $RUNNER_TEMP, and the artifact name for the upload
# step. report.json schema 1 is read by the local CI-watch hook and the
# automated fix loop; change fields only with a schema bump.
# Env: NAME PR SHA RUN_URL SHARD_INDEX SHARD_TOTAL, plus the runner's own.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
cd "$RUNNER_TEMP"
touch run.log
step=$(cat step 2>/dev/null || echo setup)
# CI=true makes JS tools print colour codes; keep them out of the report.
# awk 1 ends the last line, so the closing fence stands on its own line.
sed -E 's/\x1b\[[0-9;?]*[A-Za-z]//g; s/\r$//' run.log | tail -n 40 | awk 1 > tail.txt

# The first failure line in the tail names the cause; the last line is often
# "}" or a log path. A failure word starts a word (not pkg-fail, test_fail.py)
# or ends one (TypeError).
line=$(grep -m1 -iE '(^|[[:space:]([])(error|exception|fail|assert|panic)|[a-z](error|exception)\b' tail.txt ||
  grep -v '^[[:space:]]*$' tail.txt | tail -n 1 || true)
esc() { local s=${1//'%'/'%25'}; s=${s//$'\r'/'%0D'}; printf '%s' "${s//$'\n'/'%0A'}"; }
title=$(esc "$NAME (shard $SHARD_INDEX/$SHARD_TOTAL)")
title=${title//:/%3A}
echo "::error title=${title//,/%2C}::$(esc "${line:-step $step failed}")"

# A fence longer than any backtick run in the tail, so the tail cannot close it.
run=$(awk '{ while (match($0, /`+/)) { if (RLENGTH > n) n = RLENGTH; $0 = substr($0, RSTART + RLENGTH) } } END { print n + 0 }' tail.txt)
fence=$(printf '%*s' $((run < 3 ? 3 : run + 1)) '' | tr ' ' '`')
{
  echo "### $NAME failed (shard $SHARD_INDEX/$SHARD_TOTAL, step: $step)"
  echo "$fence"; cat tail.txt; echo "$fence"
  echo "[Run log]($RUN_URL)"
} >> "$GITHUB_STEP_SUMMARY"

mkdir -p report
jq -n --arg repo "$GITHUB_REPOSITORY" --arg pr "$PR" --arg sha "$SHA" --arg url "$RUN_URL" \
  --arg job "$NAME" --arg shard "$SHARD_INDEX" --argjson total "$SHARD_TOTAL" \
  --arg step "$step" --rawfile tail tail.txt \
  '{schema: 1, repo: $repo, pr: (if $pr == "" then null else ($pr | tonumber) end),
    sha: $sha, run_url: $url, job: $job, shard: ($shard | tonumber? // $shard), shard_total: $total,
    step: $step, tail: ($tail | split("\n") | map(select(. != "")))}' \
  > report/report.json
echo "artifact=$(bash "$here/artifact-name.sh" "$NAME" "$SHARD_INDEX")" >> "$GITHUB_OUTPUT"
