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
# Exported, so git run by gh inherits it too.
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null \
  GIT_CONFIG_KEY_1=core.fsmonitor GIT_CONFIG_VALUE_1=false
[ -n "${1:-}" ] || die 'usage: fix-publish.sh "<commit subject>"'
[ ! -e "$dir/published" ] || die "already published: $(cat "$dir/published")"
cd "$FIX_REPO"
# Claude can write .git/config. Allow only the keys actions/checkout and
# claude-code-action set: credential.helper, core.sshCommand, filter.*,
# url.* and the like can run commands or send the push elsewhere.
allowed='^(core\.(repositoryformatversion|filemode|bare|logallrefupdates|ignorecase|precomposeunicode|symlinks)|remote\.origin\.(url|fetch)|branch\..+\.(remote|merge)|user\.(name|email)|gc\.auto|include\.path|includeif\..+\.path)$'
# No extensions.*: worktreeConfig would load a second file this list skips.
bad=$(git config --local --includes --name-only --list | grep -viE "$allowed" || true)
[ -z "$bad" ] || die "refused: unexpected .git/config keys: $(tr '\n' ' ' <<<"$bad")"
# origin carries the token: it must still point at this repo.
url=$(git remote get-url --push origin | sed -E 's#//[^/@]*@#//#; s#\.git$##')
[ "$url" = "$FIX_REMOTE" ] || die "refused: origin points at $url, not $FIX_REMOTE"
# claude-code-action resets these to the base branch, unstaged, on PR events.
git add -A -- . ':!.claude' ':!.mcp.json' ':!.claude.json' ':!.gitmodules' ':!.ripgreprc' \
  ':!CLAUDE.md' ':!CLAUDE.local.md' ':!.husky'
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
