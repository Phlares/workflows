#!/usr/bin/env bash
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
script="$root/.github/scripts/fix-args.sh"
export HOME=/home/runner GITHUB_WORKSPACE=/home/runner/work/r/r RUNNER_TEMP=/home/runner/work/_temp \
  RUNNER_TOOL_CACHE=/opt/hostedtoolcache
export FIX_DIR=$RUNNER_TEMP/fix MODEL=opus MAX_TURNS=50
args=()
run() { # $1 kind, $2 test command; sets args (the parsed argument list)
  out=$(KIND=$1 TEST_COMMAND=$2 bash "$script")
  eval "args=($out)"
}
flag() { # value after flag $1 in args
  local i
  for ((i = 0; i < ${#args[@]}; i++)); do [ "${args[i]}" = "$1" ] && { echo "${args[i + 1]}"; return; }; done
}
# Does an Edit/Write rule in list $1 cover path $2? Claude Code rules: //x is
# the absolute path /x, ~ is the home folder, ** spans folders.
covers() {
  local rule pat rules
  IFS=, read -ra rules <<<"$1"
  for rule in "${rules[@]}"; do
    [[ $rule =~ ^(Edit|Write)\((.*)\)$ ]] || continue
    pat=${BASH_REMATCH[2]}; pat=${pat/#\/\//\/}; pat=${pat/#\~/$HOME}; pat=${pat//\*\*/*}
    # shellcheck disable=SC2053 # the rule is a glob on purpose
    [[ $2 == $pat ]] && return 0
  done
  return 1
}
uncovered() { ! covers "$@"; }
has() { [[ $1 == *"$2"* ]]; }
lacks() { [[ $1 != *"$2"* ]]; }

run issue "node --test"
allow=$(flag --allowedTools); deny=$(flag --disallowedTools)
check "issue: model and turn cap" test "$(flag --model) $(flag --max-turns)" = "opus 50"
check "issue: task folder is readable" test "$(flag --add-dir)" = "$FIX_DIR/task"
check "issue: can edit the workspace" covers "$allow" "$GITHUB_WORKSPACE/src/a.js"
for p in "$GITHUB_WORKSPACE/src/a.js" "$GITHUB_WORKSPACE/test/a.test.js"; do
  check "issue: deny leaves $p editable" uncovered "$deny" "$p"
done
for p in "$HOME/.gitconfig" "$HOME/.config/git/config" "$HOME/.bashrc" \
  "$RUNNER_TEMP/_runner_file_commands/set_env_1" "$FIX_DIR/bin/fix-publish.sh" \
  /home/runner/work/_actions/anthropics/claude-code-action/v1/src/post.ts \
  /home/runner/work/_tool/node/24/x64/bin/node "$RUNNER_TOOL_CACHE/node/24/x64/bin/node"; do
  check "issue: deny covers $p" covers "$deny" "$p"
done
check "issue: may publish" has "$allow" "Bash(bash $FIX_DIR/bin/fix-publish.sh:*)"
check "issue: no general shell" lacks ",$allow," ",Bash,"
check "issue: no tests" lacks "$allow" "node --test"
check "issue: no web tools" has "$deny" "WebFetch,WebSearch"

run pr "pytest -k 'a b'"
allow=$(flag --allowedTools)
check "pr: general shell" has ",$allow," ",Bash,"
check "pr: test command with quotes survives" has "$allow" "Bash(pytest -k 'a b':*)"
check "pr: schema is valid JSON" jq -e '.required == ["fixed","summary"]' <<<"$(flag --json-schema)"

run pr ""
check "pr without test command: no empty rule" lacks "$(flag --allowedTools)" "Bash(:*)"
finish
