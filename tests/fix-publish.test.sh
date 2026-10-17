#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"
script="$root/.github/scripts/fix-publish.sh"
ncase=0
setup() { # $1 kind, $2 push branch → fresh remote, work tree, FIX_DIR; cd into the work tree
  ncase=$((ncase + 1)); d="$tmp/case$ncase"
  git init -q --bare "$d/remote.git"
  git clone -q "$d/remote.git" "$d/work" 2>/dev/null
  cd "$d/work" || exit 1
  git config user.email t@example.com; git config user.name t
  echo a > a.txt; git add a.txt; git commit -qm init; git push -q origin HEAD:main HEAD:feat
  mkdir -p "$d/fix/bin"; cp "$script" "$d/fix/bin/"
  printf 'FIX_REPO=%q\nFIX_KIND=%q\nFIX_NUMBER=5\nFIX_BRANCH=%q\nFIX_BASE=main\nFIX_START=%q\n' \
    "$d/work" "$1" "$2" "$(git rev-parse HEAD)" > "$d/fix/publish.env"
  reset_gh
}
pub() { out=$(bash "$d/fix/bin/fix-publish.sh" "$@" 2>&1); code=$?; }
remote_subject() { git --git-dir="$d/remote.git" log -1 --format=%s "$1" 2>/dev/null; }

setup pr feat; echo b > a.txt
pub "fix: thing"
check "PR: exits 0" test "$code" -eq 0
check "PR: one commit pushed to the PR branch" test "$(remote_subject feat)" = "fix: thing"
check "PR: published names the commit" grep -q ' on feat$' "$d/fix/published"
check "PR: no gh call" test ! -s "$FAKE_GH_LOG"

setup issue claude/issue-5-1; echo b > a.txt
respond 'pr create*' 'https://github.com/o/r/pull/9'
pub "fix: thing"
check "issue: branch pushed" test "$(remote_subject claude/issue-5-1)" = "fix: thing"
check "issue: draft PR that fixes the issue" grep -qF 'pr create --draft --base main --head claude/issue-5-1 --title fix: thing --body Fixes #5' "$FAKE_GH_LOG"
check "issue: published is the PR URL" test "$(cat "$d/fix/published")" = "https://github.com/o/r/pull/9"

setup pr feat; mkdir -p .github/workflows; echo x > .github/workflows/x.yml
pub "fix: thing"
check ".github: refused" test "$code" -ne 0
check ".github: says why" grep -q '.github/' <<<"$out"
check ".github: nothing pushed" test "$(remote_subject feat)" = "init"

setup pr feat
pub "fix: thing"
check "no change: refused" test "$code" -ne 0 -a ! -e "$d/fix/published"

setup pr feat; echo b > a.txt; pub "fix: one"; echo c > a.txt
pub "fix: two"
check "second publish: refused" test "$code" -ne 0 -a "$(remote_subject feat)" = "fix: one"

setup pr feat; echo b > a.txt; git commit -qam "own commit"
pub "fix: thing"
check "a commit Claude made itself is pushed" test "$code" -eq 0 -a "$(remote_subject feat)" = "own commit"

setup pr feat; echo b > a.txt
( cd "$tmp" && git clone -q "$d/remote.git" other && cd other && git checkout -q feat && \
  git -c user.email=o@example.com -c user.name=o commit -q --allow-empty -m "dev push" && git push -q origin feat )
pub "fix: thing"
check "branch moved: push rejected" test "$code" -ne 0 -a "$(remote_subject feat)" = "dev push"
check "branch moved: not marked published" test ! -e "$d/fix/published"

setup pr feat; echo b > a.txt; cd "$tmp" || exit 1
pub "fix: thing"
check "works from any folder" test "$code" -eq 0

setup pr feat
pub ""
check "empty subject: usage error" grep -q usage <<<"$out"
finish
