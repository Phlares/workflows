#!/usr/bin/env bash
# Picks what a claude-fix run works on, from the event that started it.
# Prints KEY=VALUE lines for $GITHUB_OUTPUT, or skip=<reason>. For
# workflow_run (auto fix) it applies the gate: PR runs only, not pushed by
# a bot, PR head unchanged, no owner:* label, one try per commit.
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
    # Issue text is the task, so only collaborators' issues run. A refusal
    # keeps the number so the workflow can say why on the issue.
    case $(get .issue.author_association) in
      OWNER | MEMBER | COLLABORATOR) ;;
      *) printf 'skip=the issue author is not a collaborator (%s)\nnumber=%s\n' "$(get .issue.author_association)" "$n"; exit 0 ;;
    esac
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
    actor=$(get .workflow_run.actor.login)
    [ "$actor" != "claude[bot]" ] || skip "pushed by claude[bot]"
    # claude-code-action refuses non-human actors; a run would only burn the one try.
    [ "$(get .workflow_run.actor.type)" != Bot ] || skip "pushed by a bot ($actor)"
    sha=$(get .workflow_run.head_sha)
    [ "$("$GH" api "repos/$repo/pulls/$n" --jq .head.sha)" = "$sha" ] || skip "PR head moved past $sha"
    owners=$("$GH" api "repos/$repo/issues/$n/labels" --jq '[.[].name | select(startswith("owner:"))] | join(",")')
    [ -z "$owners" ] || skip "owned by $owners"
    tried=$("$GH" api "repos/$repo/commits/$sha/statuses?per_page=100" --jq '[.[] | select(.context == "claude-fix/auto")] | length')
    [ "$tried" = 0 ] || skip "auto fix already tried on $sha"
    printf 'kind=pr\nnumber=%s\nbranch=%s\nsha=%s\nauto=true\n' "$n" "$(get .workflow_run.head_branch)" "$sha" ;;
  *) skip "unsupported event $1" ;;
esac
