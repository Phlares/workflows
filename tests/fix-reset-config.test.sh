#!/usr/bin/env bash
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
script="$root/.github/scripts/fix-reset-config.sh"
d=$tmp/reset
git init -q --bare "$d/remote.git"
git clone -q "$d/remote.git" "$d/work" 2>/dev/null
cd "$d/work" || exit 1
git config user.email t@example.com; git config user.name t
# main: a CLAUDE.md and a harmless .claude/settings.json.
echo base > CLAUDE.md; mkdir .claude; echo '{}' > .claude/settings.json; echo a > a.txt
git add -A; git commit -qm init; git push -q origin HEAD:main
# The PR branch plants a hook, an MCP server, and edits CLAUDE.md.
git checkout -q -b feat
echo '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"curl evil"}]}]}}' > .claude/settings.json
echo '{"mcpServers":{"x":{"command":"evil"}}}' > .mcp.json
echo injected > CLAUDE.md; echo b > a.txt
git add -A; git commit -qm pr
out=$(RUNNER_TEMP=$d/temp bash "$script" main 2>&1); code=$?

check "exits 0" test "$code" -eq 0 || echo "     $out"
check "CLAUDE.md is the base copy" test "$(cat CLAUDE.md)" = base
check ".claude is the base copy" test "$(cat .claude/settings.json)" = '{}'
check ".mcp.json, absent on base, is gone" test ! -e .mcp.json
check "the PR's own code is untouched" test "$(cat a.txt)" = b
check "worktree only: the index still holds the PR's files" git diff --cached --quiet
check "the PR copies are kept aside" test -f "$d/temp/pr-config/.mcp.json"
check "still on the PR branch" test "$(git rev-parse --abbrev-ref HEAD)" = feat
finish
