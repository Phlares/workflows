#!/usr/bin/env bash
# Picks what a claude-fix run works on, from the event that started it.
# Prints KEY=VALUE lines for $GITHUB_OUTPUT, or skip=<reason>. For
# workflow_run (auto fix) it applies the gate: PR runs only, not pushed by
# a bot, PR head unchanged, no owner:* label, one try per commit.
# exec=true lets the run install and run tests. Only PRs written by a
# collaborator get it: an issue run could write code and then run it, and a
# bot's PR (a dependency bump) brings install scripts no collaborator wrote.
# Usage: fix-target.sh <event name> <event json file>
set -euo pipefail
GH=${GH:-gh}
ev=$2
get() { jq -r "$1 // empty" "$ev"; }
skip() { echo "skip=$1"; exit 0; }
trusted() { case $1 in OWNER | MEMBER | COLLABORATOR) echo true ;; *) echo false ;; esac; }
# exec for PR $2 by an author with association $1. An App with write access
# (Renovate, an autofix bot) can push to a collaborator's PR, so every commit
# must come from a person or from this repo's own bots (claude-fix pushes).
may_exec() {
  local bots
  [ "$(trusted "$1")" = true ] || { echo false; return; }
  bots=$("$GH" api --paginate "repos/$repo/pulls/$2/commits" --jq '.[] | (.author, .committer)
    | select(.type == "Bot" and .login != "github-actions[bot]" and .login != "claude[bot]") | .login') ||
    { echo false; return; }
  if [ -z "$bots" ]; then echo true; else echo false; fi
}
repo=$(get .repository.full_name)

case $1 in
  issues)
    [ "$(get .issue.state)" = open ] || skip "issue is closed"
    n=$(get .issue.number)
    # Issue text is the task, so only collaborators' issues run. A refusal
    # keeps the number so the workflow can say why on the issue.
    a=$(get .issue.author_association)
    if [ "$(trusted "$a")" = false ]; then
      printf 'skip=the issue author is not a collaborator (%s)\nnumber=%s\n' "$a" "$n"; exit 0
    fi
    printf 'kind=issue\nnumber=%s\nbranch=claude/issue-%s-%s\nbase=%s\nexec=false\n' \
      "$n" "$n" "$GITHUB_RUN_ID" "$(get .repository.default_branch)" ;;
  pull_request)
    [ "$(get .pull_request.state)" = open ] || skip "PR is closed"
    n=$(get .pull_request.number)
    printf 'kind=pr\nnumber=%s\nbranch=%s\nsha=%s\nauto=false\nexec=%s\n' \
      "$n" "$(get .pull_request.head.ref)" "$(get .pull_request.head.sha)" \
      "$(may_exec "$(get .pull_request.author_association)" "$n")" ;;
  workflow_run)
    sha=$(get .workflow_run.head_sha)
    # The sha goes into a jq program below.
    [[ $sha =~ ^[0-9a-f]{40}$ ]] || skip "bad head sha"
    [ "$(get .workflow_run.conclusion)" = failure ] || skip "run did not fail"
    n=$(get '.workflow_run.pull_requests[0].number')
    [ -n "$n" ] || skip "not a PR run"
    actor=$(get .workflow_run.actor.login)
    [ "$actor" != "claude[bot]" ] || skip "pushed by claude[bot]"
    # claude-code-action refuses non-human actors; a run would only burn the one try.
    [ "$(get .workflow_run.actor.type)" != Bot ] || skip "pushed by a bot ($actor)"
    read -r head author < <("$GH" api "repos/$repo/pulls/$n" --jq '"\(.head.sha) \(.author_association)"')
    [ "$head" = "$sha" ] || skip "PR head moved past $sha"
    owners=$("$GH" api "repos/$repo/issues/$n/labels" --jq '[.[].name | select(startswith("owner:"))] | join(",")')
    [ -z "$owners" ] || skip "owned by $owners"
    # fix-report.sh writes the marker into its comment. Only workflows in
    # this repo post as github-actions[bot], so visitors cannot forge it.
    tried=$("$GH" api --paginate "repos/$repo/issues/$n/comments" \
      --jq ".[] | select(.user.login == \"github-actions[bot]\" and (.body | contains(\"<!-- claude-fix/auto $sha -->\"))) | .id")
    [ -z "$tried" ] || skip "auto fix already tried on $sha"
    printf 'kind=pr\nnumber=%s\nbranch=%s\nsha=%s\nauto=true\nexec=%s\n' \
      "$n" "$(get .workflow_run.head_branch)" "$sha" "$(may_exec "$author" "$n")" ;;
  *) skip "unsupported event $1" ;;
esac
