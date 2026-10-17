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
[ -n "${1:-}" ] || die 'usage: fix-publish.sh "<commit subject>"'
[ ! -e "$dir/published" ] || die "already published: $(cat "$dir/published")"
cd "$FIX_REPO"
git add -A
git diff --cached --quiet || git commit -q -m "$1"
files=$(git -c core.quotePath=false diff --name-only --no-renames "$FIX_START" HEAD)
[ -n "$files" ] || die "no changes to publish"
! grep -q '^\.github/' <<<"$files" || die "refused: the change touches .github/"
git push -q origin "HEAD:refs/heads/$FIX_BRANCH"
if [ "$FIX_KIND" = issue ]; then
  "$GH" pr create --draft --base "$FIX_BASE" --head "$FIX_BRANCH" --title "$1" --body "Fixes #$FIX_NUMBER" > "$dir/published"
else
  echo "$(git rev-parse --short HEAD) on $FIX_BRANCH" > "$dir/published"
fi
cat "$dir/published"
