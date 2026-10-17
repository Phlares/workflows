#!/usr/bin/env bash
# The one way a claude-fix run publishes: commit, push, and for an issue a
# draft PR. Claude calls it; the target comes from ../publish.env, which the
# workflow writes, never from Claude.
# Usage: fix-publish.sh "<commit subject>"
set -euo pipefail
GH=${GH:-gh}
dir=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=/dev/null
. "$dir/publish.env"
die() { echo "fix-publish: $1" >&2; exit 1; }
# Claude can write files under .git/: never run its hooks or fsmonitor.
git() { command git -c core.hooksPath=/dev/null -c core.fsmonitor=false "$@"; }
[ -n "${1:-}" ] || die 'usage: fix-publish.sh "<commit subject>"'
[ ! -e "$dir/published" ] || die "already published: $(cat "$dir/published")"
cd "$FIX_REPO"
# A URL rewrite would send the push, and the token, to another host.
! git config --get-regexp '^url\.' >/dev/null || die "refused: .git/config rewrites URLs"
git add -A
git diff --cached --quiet || git commit -q -m "$1"
! git diff --quiet "$FIX_START" HEAD || die "no changes to publish"
git diff --quiet "$FIX_START" HEAD -- .github || die "refused: the change touches .github/"
git push -q origin "HEAD:refs/heads/$FIX_BRANCH"
if [ "$FIX_KIND" = issue ]; then
  "$GH" pr create --draft --base "$FIX_BASE" --head "$FIX_BRANCH" --title "$1" --body "Fixes #$FIX_NUMBER" > "$dir/published"
else
  echo "$(git rev-parse --short HEAD) on $FIX_BRANCH" > "$dir/published"
fi
cat "$dir/published"
