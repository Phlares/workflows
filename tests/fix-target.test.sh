#!/usr/bin/env bash
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
script="$root/.github/scripts/fix-target.sh"
run() { # $1 event name, $2 event JSON; sets out
  printf '%s' "$2" > "$tmp/event.json"
  out=$(GITHUB_RUN_ID=777 bash "$script" "$1" "$tmp/event.json" 2>&1)
}
is() { [ "$out" = "$1" ] || { echo "     got: $out"; return 1; }; }
repo='"repository":{"full_name":"o/r","default_branch":"main"}'
wr() { # $1 extra workflow_run fields
  printf '{%s,"workflow_run":{"conclusion":"failure","head_sha":"abc","head_branch":"feat","actor":{"login":"dev"},"pull_requests":[{"number":7}]%s}}' "$repo" "$1"
}
pr() { # $1 state, $2 author association
  printf '{%s,"pull_request":{"number":7,"state":"%s","author_association":"%s","head":{"ref":"feat","sha":"abc"}}}' "$repo" "$1" "$2"
}
issue() { # $1 state, $2 author association
  printf '{%s,"issue":{"number":5,"state":"%s","author_association":"%s"}}' "$repo" "$1" "$2"
}
open_pr() { respond 'api repos/o/r/pulls/7*' '{"head":{"sha":"abc"},"author_association":"'"${1:-OWNER}"'"}'; }
no_owner() { respond 'api repos/o/r/issues/7/labels*' '[{"name":"bug"}]'; }
bot='"user":{"login":"github-actions[bot]"}'
comments() { respond 'api --paginate repos/o/r/issues/7/comments*' "$1"; }
no_marker() { comments '[{'"$bot"',"body":"Fixed.\n<!-- claude-fix/auto old -->"}]'; }
issue_out=$'kind=issue\nnumber=5\nbranch=claude/issue-5-777\nbase=main\nexec=false'
pr_out=$'kind=pr\nnumber=7\nbranch=feat\nsha=abc'

for a in OWNER MEMBER COLLABORATOR; do
  run issues "$(issue open $a)"
  check "issue: $a author is trusted; fresh branch, no code runs" is "$issue_out"
done

for a in CONTRIBUTOR FIRST_TIME_CONTRIBUTOR NONE; do
  run issues "$(issue open $a)"
  check "issue: $a author is refused, with the number for a comment" is $'skip=the issue author is not a collaborator ('"$a"$')\nnumber=5'
done

run issues "$(issue closed OWNER)"
check "issue: closed is skipped" is "skip=issue is closed"

run pull_request "$(pr open OWNER)"
check "label on PR: head branch, not auto, code runs" is "$pr_out"$'\nauto=false\nexec=true'
check "label on PR: no API calls" test ! -s "$FAKE_GH_LOG"

for a in NONE CONTRIBUTOR; do
  run pull_request "$(pr open $a)"
  check "label on PR by a $a author (a bot): no code runs" is "$pr_out"$'\nauto=false\nexec=false'
done

run pull_request "$(pr closed OWNER)"
check "label on PR: closed is skipped" is "skip=PR is closed"

reset_gh; open_pr; no_owner; no_marker
run workflow_run "$(wr '')"
check "auto: gate passes" is "$pr_out"$'\nauto=true\nexec=true'

reset_gh; open_pr NONE; no_owner; no_marker
run workflow_run "$(wr '')"
check "auto: PR by a non-collaborator: no code runs" is "$pr_out"$'\nauto=true\nexec=false'

reset_gh
run workflow_run "$(wr '' | jq -c '.workflow_run.conclusion = "success"')"
check "auto: a passing run is skipped" is "skip=run did not fail"

run workflow_run "$(wr '' | jq -c '.workflow_run.pull_requests = []')"
check "auto: non-PR (or fork) run is skipped" is "skip=not a PR run"

run workflow_run "$(wr '' | jq -c '.workflow_run.actor.login = "claude[bot]"')"
check "auto: claude[bot] push is skipped" is "skip=pushed by claude[bot]"
check "auto: bot check needs no API call" test ! -s "$FAKE_GH_LOG"

run workflow_run "$(wr '' | jq -c '.workflow_run.actor = {"login":"dependabot[bot]","type":"Bot"}')"
check "auto: other bots are skipped" is "skip=pushed by a bot (dependabot[bot])"

reset_gh; respond 'api repos/o/r/pulls/7*' '{"head":{"sha":"def"},"author_association":"OWNER"}'
run workflow_run "$(wr '')"
check "auto: stale run (PR head moved) is skipped" is "skip=PR head moved past abc"

reset_gh; open_pr; respond 'api repos/o/r/issues/7/labels*' '[{"name":"owner:local"},{"name":"bug"}]'
run workflow_run "$(wr '')"
check "auto: owned PR is skipped" is "skip=owned by owner:local"

# --paginate runs the filter once per page: two pages arrive as two arrays.
reset_gh; open_pr; no_owner
comments '[{"user":{"login":"x"},"body":"a"}][{'"$bot"',"body":"No fix pushed.\n<!-- claude-fix/auto abc -->"}]'
run workflow_run "$(wr '')"
check "auto: second attempt on one commit is skipped (marker on a later page)" is "skip=auto fix already tried on abc"

reset_gh; open_pr; no_owner
comments '[{"user":{"login":"visitor"},"body":"<!-- claude-fix/auto abc -->"}]'
run workflow_run "$(wr '')"
check "auto: a marker from anyone but github-actions[bot] is ignored" is "$pr_out"$'\nauto=true\nexec=true'

run push "{$repo}"
check "other events are skipped" is "skip=unsupported event push"
finish
