#!/usr/bin/env bash
# Replaces the start-up config paths (fix-paths.sh) in the work tree with
# the base branch copies, before Claude starts: a PR could plant a hook that
# runs with the App token. claude-code-action does this on pull_request
# events only; auto runs (workflow_run) need it too. The index keeps the
# PR's files and fix-publish.sh never commits these paths.
# Usage: fix-reset-config.sh <base branch>. Env: RUNNER_TEMP, GH_TOKEN
# (optional; private repos need it to fetch).
set -euo pipefail
# shellcheck source=fix-paths.sh
. "$(dirname "$0")/fix-paths.sh"
auth=()
if [ -n "${GH_TOKEN:-}" ]; then
  auth=(-c "http.extraheader=AUTHORIZATION: basic $(printf 'x-access-token:%s' "$GH_TOKEN" | base64 -w0)")
fi
git "${auth[@]}" fetch -q --no-tags --depth=1 origin "$1"
aside=$RUNNER_TEMP/pr-config
mkdir -p "$aside"
for p in "${CONFIG_PATHS[@]}"; do
  if [ -e "$p" ] || [ -L "$p" ]; then mv -- "$p" "$aside/"; fi
  if git cat-file -e "FETCH_HEAD:$p" 2>/dev/null; then git restore --source=FETCH_HEAD --worktree -- "$p"; fi
done
