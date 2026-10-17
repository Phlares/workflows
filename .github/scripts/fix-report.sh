#!/usr/bin/env bash
# Posts the outcome of a claude-fix run on its issue or PR, and the turn
# count and time to the job summary. Inputs come from env; see claude-fix.yml.
# An auto run hides a marker in the comment: fix-target.sh reads it to allow
# one auto try per commit.
set -euo pipefail
GH=${GH:-gh}
published=$(cat "$FIX_DIR/published" 2>/dev/null || true)
summary=$(jq -r '.summary // empty' <<<"${RESULT:-}" 2>/dev/null || true)
# The summary is model output; a hidden marker in it would block an auto try.
summary=${summary//"<!--"/}
if [ -n "${SKIP:-}" ]; then
  head="Not run: $SKIP."
elif [ "${EMPTY:-}" = true ]; then
  head="No failed CI runs found on $SHA. Add the label again after CI fails."
elif [ -n "$published" ]; then
  head="Fix pushed: $published"
elif [ "$OUTCOME" = success ] && [ ! -s "${EXEC_FILE:-}" ]; then
  head="Claude did not run. See the run log."
elif [ "$OUTCOME" = success ]; then
  head="No fix pushed."
else
  head="The fix run ended without a fix ($OUTCOME)."
fi
stats=""
if [ -s "${EXEC_FILE:-}" ]; then
  stats=$(jq -r '[.[] | select(.type == "result")][-1]
    | (.permission_denials // [] | map(.tool_name) | unique | join(", ")) as $tools
    | "claude-fix: \(.num_turns) turns, \(.duration_ms / 1000 | floor) s, \(.permission_denials // [] | length) denied tool calls"
      + (if $tools == "" then "" else " (\($tools))" end)' "$EXEC_FILE")
  echo "$stats" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
fi
body=$head
[ -z "$summary" ] || body+=$'\n\n'"$summary"
body+=$'\n\n'"[Run log]($RUN_URL)${stats:+ · $stats}"
[ "${AUTO:-}" != true ] || body+=$'\n'"<!-- claude-fix/auto $SHA -->"
"$GH" api "repos/$REPO/issues/$NUMBER/comments" -f body="$body" --silent
