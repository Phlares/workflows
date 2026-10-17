#!/usr/bin/env bash
# Prints the issue as the fix task: title and body, without text GitHub does
# not render (HTML comments, link reference lines, zero-width and tag
# characters). The person who added the label never saw that text. An
# unclosed comment hides the rest of the body.
# Usage: fix-issue.sh <event json file>
set -euo pipefail
jq -r '"# " + .issue.title + "\n\n" + ((.issue.body // "")
  | gsub("<!--[\\s\\S]*?(-->|\\z)"; "")
  | gsub("(?m)^ {0,3}\\[[^\\]\\n]+\\]:[^\\n]*\\n?"; "")
  | gsub("[\\x{200B}-\\x{200F}\\x{2060}-\\x{2064}\\x{FEFF}\\x{E0000}-\\x{E007F}]"; ""))' "$1"
