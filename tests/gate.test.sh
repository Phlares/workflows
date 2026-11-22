#!/usr/bin/env bash
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
script="$root/.github/scripts/gate.py"
nrepo=0
repo() { # fresh git repo with one commit; cd into it
  nrepo=$((nrepo + 1)); mkdir -p "$tmp/r$nrepo"; cd "$tmp/r$nrepo" || exit 1
  git init -q . && git config core.autocrlf false
  git config user.name t && git config user.email t@example.invalid
  echo x > README && git add README && git commit -qm init
}
list() { cat > gate.toml && git add gate.toml && git commit -qm list; } # gate.toml from stdin
one() { printf '[[check]]\nname = "a"\nrun = %s\n' "$1" | list; } # $1 = TOML string
gate() { out=$(python3 "$script" "$@" 2>&1); rc=$?; }
line() { printf '%s\n' "$out" | tail -n 1; }
gdir() { git rev-parse --absolute-git-dir; }
sj() { jq -e "$@" "$(gdir)/gate/summary.json" > /dev/null; }
sha() { git rev-parse HEAD | cut -c1-12; }
eq() { [ "$1" = "$2" ] || { printf '     got:  %s\n     want: %s\n' "$1" "$2"; return 1; }; }
ends() { eq "$rc" "$1" && eq "$(line)" "$2"; } # $1 exit code, $2 result line

repo; list <<'EOF'
[[check]]
name = "a"
run = "echo one"

[[check]]
name = "b"
run = "echo two"
EOF
gate
check "a passing list exits 0 with the result line" \
  ends 0 "gate: PASS 2/2 checks at $(sha) clean: a ok, b ok"
check "the summary records the commit, the tree and each check" \
  sj --arg c "$(git rev-parse HEAD)" --arg l "$(line)" '
    .schema == 1 and .commit == $c and .clean == true and .status == "pass" and .line == $l and
    .skipped == [] and (.checks | map(.name)) == ["a", "b"] and
    (.checks[0] | .source == "gate.toml" and .status == "pass" and .exit == 0 and
      .count == null and .log == "a.log" and (.seconds | type) == "number")'
check "a run leaves the tree clean" test -z "$(git status --porcelain)"

repo; list <<'EOF'
[[check]]
name = "a"
run = "exit 3"

[[check]]
name = "b"
run = "echo two"
EOF
gate
check "a failing check exits 1" ends 1 "gate: FAIL 2/2 checks at $(sha) clean: a FAIL exit 3, b ok"
check "checks after a failure still run" eq "$(cat "$(gdir)/gate/b.log")" two
check "the summary records the failure" \
  sj '.status == "fail" and (.checks | map(.status)) == ["fail", "pass"] and .checks[0].exit == 3'

repo; one '"false | true"'; gate
check "run is bash with pipefail" eq "$rc" 1

repo; one '"echo a; echo b >&2; echo c"'; gate
check "output and errors share one ordered log" eq "$(cat "$(gdir)/gate/a.log")" $'a\nb\nc'

repo; one '"true"'; echo y >> README; gate
check "a changed tracked file is recorded as dirty" \
  ends 0 "gate: PASS 1/1 checks at $(sha) dirty: a ok"
check "the summary records the dirty tree" sj '.clean == false'

repo; one '"true"'; echo y > new.txt; gate
check "an untracked file is recorded as dirty" sj '.clean == false'

repo; one '"test -f gate.toml"'; mkdir sub; cd sub || exit 1; gate
check "a run from a subfolder uses the repo root" eq "$rc" 0

repo; one '"true"'; main=$PWD
git worktree add -q "$tmp/w$nrepo" -b "w$nrepo"; cd "$tmp/w$nrepo" || exit 1; gate
check "a linked worktree keeps its own summary" test -f "$(gdir)/gate/summary.json" -a ! -e "$main/.git/gate"

repo; one '"cat"'; out=$(echo leak | python3 "$script" 2>&1); rc=$?
check "a check reading stdin gets end of file" test "$rc" -eq 0 -a ! -s "$(gdir)/gate/a.log"

finish
