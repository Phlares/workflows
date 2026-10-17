#!/usr/bin/env bash
# Prints the claude_args for claude-code-action: model, turn cap, tool rules,
# output schema. File tools are scoped, never bare: a bare Write reaches the
# runner's own files ($GITHUB_ENV, ~/.gitconfig) and later steps run them.
# Reads need no rule inside the workspace and --add-dir; outside them -p
# mode refuses (the process environment holds tokens). The workspace sits
# under the home folder, so the home deny covers only dotfiles.
# Env: KIND (issue|pr), MODEL, MAX_TURNS, TEST_COMMAND, GITHUB_WORKSPACE,
# RUNNER_TEMP, FIX_DIR.
set -euo pipefail
q() { local r="'\\''"; printf "'%s'" "${1//\'/$r}"; }
tools="Edit(/$GITHUB_WORKSPACE/**),Write(/$GITHUB_WORKSPACE/**),Bash(bash $FIX_DIR/bin/fix-publish.sh:*)"
if [ "$KIND" = pr ]; then
  tools+=",Bash"
  [ -z "$TEST_COMMAND" ] || tools+=",Bash($TEST_COMMAND:*)"
fi
deny="WebFetch,WebSearch"
for tool in Edit Write; do deny+=",$tool(/$RUNNER_TEMP/**),$tool(~/.*),$tool(~/.*/**)"; done
schema='{"type":"object","properties":{"fixed":{"type":"boolean"},"summary":{"type":"string"}},"required":["fixed","summary"]}'
echo "--model $(q "$MODEL") --max-turns $MAX_TURNS --add-dir $(q "$FIX_DIR/task") --allowedTools $(q "$tools") --disallowedTools $(q "$deny") --json-schema $(q "$schema")"
