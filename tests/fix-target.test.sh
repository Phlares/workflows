#!/usr/bin/env bash
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
script="$root/.github/scripts/fix-target.sh"
run() { # $1 event name, $2 event JSON; sets out
  printf '%s' "$2" > "$tmp/event.json"
  out=$(GITHUB_RUN_ID=777 bash "$script" "$1" "$tmp/event.json" 2>&1)
}
is() { [ "$out" = "$1" ] || { echo "     got: $out"; return 1; }; }
called() { grep -qF "$1" "$FAKE_GH_LOG"; }
repo='"repository":{"full_name":"o/r","default_branch":"main"}'
wr() { # $1 extra workflow_run fields
  printf '{%s,"workflow_run":{"conclusion":"failure","head_sha":"abc","head_branch":"feat","actor":{"login":"dev"},"pull_requests":[{"number":7}]%s}}' "$repo" "$1"
}
open_pr() { respond 'api repos/o/r/pulls/7*' '{"head":{"sha":"abc"}}'; }
no_owner() { respond 'api repos/o/r/issues/7/labels*' '[{"name":"bug"}]'; }
no_marker() { respond 'api repos/o/r/commits/abc/statuses*' '[{"context":"ci","state":"failure"}]'; }

run issues "{$repo,\"issue\":{\"number\":5,\"state\":\"open\",\"author_association\":\"OWNER\"}}"
check "issue: fresh branch off the default branch" is $'kind=issue\nnumber=5\nbranch=claude/issue-5-777\nbase=main'

for a in MEMBER COLLABORATOR; do
  run issues "{$repo,\"issue\":{\"number\":5,\"state\":\"open\",\"author_association\":\"$a\"}}"
  check "issue: $a author is trusted" is $'kind=issue\nnumber=5\nbranch=claude/issue-5-777\nbase=main'
done

for a in CONTRIBUTOR FIRST_TIME_CONTRIBUTOR NONE; do
  run issues "{$repo,\"issue\":{\"number\":5,\"state\":\"open\",\"author_association\":\"$a\"}}"
  check "issue: $a author is refused, with the number for a comment" is $'skip=the issue author is not a collaborator ('"$a"$')\nnumber=5'
done

run issues "{$repo,\"issue\":{\"number\":5,\"state\":\"closed\",\"author_association\":\"OWNER\"}}"
check "issue: closed is skipped" is "skip=issue is closed"

run pull_request "{$repo,\"pull_request\":{\"number\":7,\"state\":\"open\",\"head\":{\"ref\":\"feat\",\"sha\":\"abc\"}}}"
check "label on PR: head branch, not auto" is $'kind=pr\nnumber=7\nbranch=feat\nsha=abc\nauto=false'
check "label on PR: no API calls" test ! -s "$FAKE_GH_LOG"

run pull_request "{$repo,\"pull_request\":{\"number\":7,\"state\":\"closed\",\"head\":{\"ref\":\"feat\",\"sha\":\"abc\"}}}"
check "label on PR: closed is skipped" is "skip=PR is closed"

reset_gh; open_pr; no_owner; no_marker
run workflow_run "$(wr '')"
check "auto: gate passes" is $'kind=pr\nnumber=7\nbranch=feat\nsha=abc\nauto=true'

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

reset_gh; respond 'api repos/o/r/pulls/7*' '{"head":{"sha":"def"}}'
run workflow_run "$(wr '')"
check "auto: stale run (PR head moved) is skipped" is "skip=PR head moved past abc"

reset_gh; open_pr; respond 'api repos/o/r/issues/7/labels*' '[{"name":"owner:local"},{"name":"bug"}]'
run workflow_run "$(wr '')"
check "auto: owned PR is skipped" is "skip=owned by owner:local"

reset_gh; open_pr; no_owner; respond 'api repos/o/r/commits/abc/statuses*' '[{"context":"claude-fix/auto","state":"success"}]'
run workflow_run "$(wr '')"
check "auto: second attempt on one commit is skipped" is "skip=auto fix already tried on abc"
check "auto: marker read from the head commit" called "api repos/o/r/commits/abc/statuses"

run push "{$repo}"
check "other events are skipped" is "skip=unsupported event push"
finish
