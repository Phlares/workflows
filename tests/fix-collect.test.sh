#!/usr/bin/env bash
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
script="$root/.github/scripts/fix-collect.sh"
out="$tmp/out"
respond 'api repos/o/r/actions/runs/11/artifacts*' '{"artifacts":[{"id":91,"name":"ci-failure-unit-2"},{"id":92,"name":"ci-failure-unit-1"},{"id":93,"name":"ci-failure-odd-name--x-a"}]}'
respond 'api repos/o/r/actions/runs/11/jobs*' '{"jobs":[
  {"id":1,"name":"unit / unit (1)","conclusion":"success"},
  {"id":2,"name":"unit / unit (2)","conclusion":"failure"},
  {"id":3,"name":"sim / smoke","conclusion":"failure"},
  {"id":4,"name":"odd / odd/name: x (a)","conclusion":"failure"}]}'
rule 'api repos/o/r/actions/artifacts/91/zip' 0 "$root/tests/fixtures/report.zip"
rule 'api repos/o/r/actions/artifacts/92/zip' 0 "$root/tests/fixtures/report.zip"
{ for i in $(seq 1 250); do printf 'line %s\n' "$i"; done; printf '\033[31mboom\033[0m\n'; } > "$tmp/log3"
rule 'api *repos/o/r/actions/jobs/3/logs' 0 "$tmp/log3"

bash "$script" o/r "$out" 11 > "$tmp/stdout" 2>&1; code=$?
check "exits 0" test "$code" -eq 0
check "check.yml job: report.json from its artifact" jq -e '.job == "unit" and .shard == 2' "$out/ci-failure-unit-2/report.json"
check "name with / : and a text shard: artifact found" test -f "$out/ci-failure-odd-name--x-a/report.json"
check "passing shard: nothing collected" test ! -e "$out/ci-failure-unit-1"
check "job without a report: log tail" test "$(head -n 1 "$out/log-3.txt")" = "# sim / smoke"
check "log tail: 200 lines plus the header" test "$(wc -l < "$out/log-3.txt")" -eq 201
check "log tail: ANSI codes stripped" grep -qx boom "$out/log-3.txt"
check "job with a report: its log is not fetched" bash -c "! grep -q 'jobs/2/logs' '$FAKE_GH_LOG'"

reset_gh
bash "$script" o/r "$tmp/none"; code=$?
check "no run ids: empty folder" test "$code" -eq 0 -a -d "$tmp/none" -a -z "$(ls -A "$tmp/none")"

reset_gh
bash "$script" o/r "$tmp/blank" ""; code=$?
check "an empty run id is skipped" test "$code" -eq 0 -a ! -s "$FAKE_GH_LOG"
finish
