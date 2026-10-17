#!/usr/bin/env bash
# Prints the issue as the fix task: title and body, with HTML comments
# removed. Comments do not render on GitHub, so a reader who checked the
# issue never saw them; an unclosed one hides the rest of the body.
# Usage: fix-issue.sh <event json file>
set -euo pipefail
jq -r '"# " + .issue.title + "\n\n" + ((.issue.body // "") | gsub("<!--[\\s\\S]*?(-->|\\z)"; ""))' "$1"
