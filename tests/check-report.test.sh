#!/usr/bin/env bash
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
script="$root/.github/scripts/check-report.sh"
export GITHUB_REPOSITORY=o/r SHA=0123456789012345678901234567890123456789 RUN_URL=https://github.com/o/r/actions/runs/1
report() { # $1 run.log text, $2 step (empty = no step file), rest = env assignments
  export RUNNER_TEMP="$tmp/rt" GITHUB_STEP_SUMMARY="$tmp/summary" GITHUB_OUTPUT="$tmp/output"
  rm -rf "$RUNNER_TEMP"; mkdir -p "$RUNNER_TEMP"; : > "$GITHUB_STEP_SUMMARY"; : > "$GITHUB_OUTPUT"
  [ -z "$1" ] || printf '%b' "$1" > "$RUNNER_TEMP/run.log"
  [ -z "$2" ] || echo "$2" > "$RUNNER_TEMP/step"
  shift 2
  env NAME=unit PR=7 SHARD_INDEX=2 SHARD_TOTAL=3 "$@" bash "$script" > "$tmp/stdout" 2>&1
}
json() { jq -e "$1" "$RUNNER_TEMP/report/report.json" > /dev/null; }
annotation() { grep -qxF "$1" "$tmp/stdout" || { echo "     stdout: $(cat "$tmp/stdout")"; return 1; }; }

{ for i in $(seq 1 50); do echo "line $i"; done; printf '> pkg-fail@1.0.0 test\nsee tests/test_fail.py, src/error.js\n\033[31mError: boom\033[0m\n```\n  at x\n1 test failed\n}\n'; } > "$tmp/log"
report "$(cat "$tmp/log")" run
check "report: schema 1 fields" json '.schema == 1 and .repo == "o/r" and .pr == 7 and .sha == env.SHA and .run_url == env.RUN_URL and .job == "unit" and .step == "run"'
check "report: numeric shard stays a number" json '.shard == 2 and .shard_total == 3'
check "report: last 40 lines, colour removed" json '(.tail | length) == 40 and .tail[-1] == "}" and (.tail | index("Error: boom")) != null'
check "annotation: the failure line, not the last line" annotation "::error title=unit (shard 2/3)::Error: boom"
check "artifact name to the upload step" grep -qx "artifact=ci-failure-unit-2" "$GITHUB_OUTPUT"
fence=$(grep -m1 -E '^`{3,}$' "$GITHUB_STEP_SUMMARY")
check "summary: fence longer than a fence in the tail" test "$fence" = '````'
check "summary: fence closes" test "$(grep -cxF "$fence" "$GITHUB_STEP_SUMMARY")" -eq 2
check "summary: heading and run link" grep -qxF "### unit failed (shard 2/3, step: run)" "$GITHUB_STEP_SUMMARY"
check "summary: run link" grep -qxF "[Run log]($RUN_URL)" "$GITHUB_STEP_SUMMARY"

report 'ok\n\nlast words\n\n' install PR=
check "no failure word: last non-blank line" annotation "::error title=unit (shard 2/3)::last words"
check "push run: pr is null" json '.pr == null and .step == "install"'
check "summary: plain fence without backticks in the tail" test "$(grep -cx '```' "$GITHUB_STEP_SUMMARY")" -eq 2

report 'built app-error-pages\nTypeError: x is undefined\n' run
check "annotation: a word ending in Error" annotation "::error title=unit (shard 2/3)::TypeError: x is undefined"

report '' ''
check "no log, no step file: setup failure" json '.step == "setup" and .tail == []'
check "no log: annotation names the step" annotation "::error title=unit (shard 2/3)::step setup failed"

report 'FAIL at 100%\n' run NAME='odd/name: a, b' SHARD_INDEX=a SHARD_TOTAL=1
check "non-numeric shard: report written" json '.shard == "a" and .shard_total == 1 and .job == "odd/name: a, b"'
check "annotation: % : , escaped" annotation "::error title=odd/name%3A a%2C b (shard a/1)::FAIL at 100%25"
check "artifact name: unsafe characters replaced" grep -qx "artifact=ci-failure-odd-name--a--b-a" "$GITHUB_OUTPUT"
finish
