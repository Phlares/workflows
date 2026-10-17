#!/usr/bin/env bash
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
script="$root/.github/scripts/fix-report.sh"
export REPO=o/r NUMBER=7 SHA=abc RUN_URL=https://github.com/o/r/actions/runs/1 FIX_DIR="$tmp/fix" GITHUB_STEP_SUMMARY="$tmp/summary"
mkdir -p "$FIX_DIR"
printf '[{"type":"system"},{"type":"result","num_turns":12,"duration_ms":61500,"is_error":false}]' > "$tmp/exec.json"
report() { # env assignments for this case as arguments
  reset_gh; respond 'api repos/o/r/issues/7/comments*' '{}'; : > "$GITHUB_STEP_SUMMARY"
  env AUTO= EMPTY= OUTCOME=success RESULT= EXEC_FILE="$tmp/exec.json" "$@" bash "$script" >/dev/null 2>&1
}
said() { grep -qF "$1" "$FAKE_GH_LOG" || { echo "     log: $(cat "$FAKE_GH_LOG")"; return 1; }; }

report SKIP='the issue author is not a collaborator (NONE)' OUTCOME= EXEC_FILE=
check "refused run: says why" said "Not run: the issue author is not a collaborator (NONE)."

report EMPTY=true EXEC_FILE=
check "no failures: says so" said "No failed CI runs found on abc"

echo "https://github.com/o/r/pull/9" > "$FIX_DIR/published"
report RESULT='{"fixed":true,"summary":"Restored the clamp."}'
check "published: names the fix" said "Fix pushed: https://github.com/o/r/pull/9"
check "published: carries the summary" said "Restored the clamp."
check "published: links the run" said "[Run log](https://github.com/o/r/actions/runs/1)"
check "turns in the job summary" grep -qx "claude-fix: 12 turns, 61 s, 0 denied tool calls" "$GITHUB_STEP_SUMMARY"

printf '[{"type":"result","num_turns":3,"duration_ms":2000,"permission_denials":[{"tool_name":"Write"},{"tool_name":"Read"},{"tool_name":"Write"}]}]' > "$tmp/denied.json"
report EXEC_FILE="$tmp/denied.json"
check "denied tool calls in the job summary" grep -qx "claude-fix: 3 turns, 2 s, 3 denied tool calls (Read, Write)" "$GITHUB_STEP_SUMMARY"
check "the comment carries the same line" said "· claude-fix: 3 turns, 2 s, 3 denied tool calls (Read, Write)"
mv "$FIX_DIR/published" "$tmp/published.old"

report RESULT='{"fixed":false,"summary":"Flaky network test; no code fault."}'
check "no fix: says so with findings" said "No fix pushed."

report EXEC_FILE=
check "action skipped quietly: says Claude did not run" said "Claude did not run"

report OUTCOME=failure; cp "$FAKE_GH_LOG" "$tmp/label.log"
check "step failed or timed out: says so" said "ended without a fix (failure)"

report AUTO=true OUTCOME=failure
check "auto run: marks the commit as tried" said "<!-- claude-fix/auto abc -->"
check "label run: no marker" sh -c '! grep -q "claude-fix/auto" "$1"' _ "$tmp/label.log"

report RESULT='not json'
check "bad structured output: still comments" said "No fix pushed."
finish
