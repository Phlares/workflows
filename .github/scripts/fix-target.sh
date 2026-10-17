#!/usr/bin/env bash
# Picks what a claude-fix run works on, from the event that started it.
# Prints KEY=VALUE lines for $GITHUB_OUTPUT, or skip=<reason>. For
# workflow_run (auto fix) it applies the gate: PR runs only, not pushed by
# claude[bot], PR head unchanged, no owner:* label, one try per commit.
# Usage: fix-target.sh <event name> <event json file>
set -euo pipefail
GH=${GH:-gh}
ev=$2
get() { jq -r "$1 // empty" "$ev"; }
skip() { echo "skip=$1"; exit 0; }
repo=$(get .repository.full_name)

case $1 in
  issues)
    [ "$(get .issue.state)" = open ] || skip "issue is closed"
    n=$(get .issue.number)
    printf 'kind=issue\nnumber=%s\nbranch=claude/issue-%s-%s\nbase=%s\n' \
      "$n" "$n" "$GITHUB_RUN_ID" "$(get .repository.default_branch)" ;;
  pull_request)
    [ "$(get .pull_request.state)" = open ] || skip "PR is closed"
    printf 'kind=pr\nnumber=%s\nbranch=%s\nsha=%s\nauto=false\n' \
      "$(get .pull_request.number)" "$(get .pull_request.head.ref)" "$(get .pull_request.head.sha)" ;;
  workflow_run)
    [ "$(get .workflow_run.conclusion)" = failure ] || skip "run did not fail"
    n=$(get '.workflow_run.pull_requests[0].number')
    [ -n "$n" ] || skip "not a PR run"
    [ "$(get .workflow_run.actor.login)" != "claude[bot]" ] || skip "pushed by claude[bot]"
    sha=$(get .workflow_run.head_sha)
    [ "$("$GH" api "repos/$repo/pulls/$n" --jq .head.sha)" = "$sha" ] || skip "PR head moved past $sha"
    owners=$("$GH" api "repos/$repo/issues/$n/labels" --jq '[.[].name | select(startswith("owner:"))] | join(",")')
    [ -z "$owners" ] || skip "owned by $owners"
    tried=$("$GH" api "repos/$repo/commits/$sha/statuses?per_page=100" --jq '[.[] | select(.context == "claude-fix/auto")] | length')
    [ "$tried" = 0 ] || skip "auto fix already tried on $sha"
    printf 'kind=pr\nnumber=%s\nbranch=%s\nsha=%s\nauto=true\n' "$n" "$(get .workflow_run.head_branch)" "$sha" ;;
  *) skip "unsupported event $1" ;;
esac
