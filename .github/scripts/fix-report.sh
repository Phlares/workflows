#!/usr/bin/env bash
# Posts the outcome of a claude-fix run on its issue or PR, and the turn
# count and time to the job summary. Inputs come from env; see claude-fix.yml.
set -euo pipefail
GH=${GH:-gh}
published=$(cat "$FIX_DIR/published" 2>/dev/null || true)
summary=$(jq -r '.summary // empty' <<<"${RESULT:-}" 2>/dev/null || true)
if [ "${EMPTY:-}" = true ]; then
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
body=$head
[ -z "$summary" ] || body+=$'\n\n'"$summary"
body+=$'\n\n'"[Run log]($RUN_URL)"
"$GH" api "repos/$REPO/issues/$NUMBER/comments" -f body="$body" --silent
if [ -s "${EXEC_FILE:-}" ]; then
  jq -r '[.[] | select(.type == "result")][-1] | "claude-fix: \(.num_turns) turns, \(.duration_ms / 1000 | floor) s"' \
    "$EXEC_FILE" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
fi
