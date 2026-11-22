#!/usr/bin/env bash
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
script="$root/.github/scripts/gate.py"
# One git config for every repo here, and none of the machine's own.
export GIT_CONFIG_GLOBAL="$tmp/gitconfig"
printf '[user]\n\tname = t\n\temail = t@example.invalid\n[core]\n\tautocrlf = false\n[init]\n\tdefaultBranch = main\n' \
  > "$GIT_CONFIG_GLOBAL"
nrepo=0
repo() { # fresh git repo with one commit; cd into it; g = where gate writes; $1 = folder name
  nrepo=$((nrepo + 1)); mkdir -p "$tmp/${1:-r$nrepo}"; cd "$tmp/${1:-r$nrepo}" || exit 1
  git init -q . && echo x > README && git add README && git commit -qm init
  g=$PWD/.git/gate
}
list() { cat > gate.toml && git add gate.toml && git commit -qm list; } # gate.toml from stdin
one() { # one check "a"; $1 run, $2 count: TOML values
  printf '[[check]]\nname = "a"\nrun = %s\n%s\n' "$1" "${2:+count = $2}" | list
}
gate() { out=$(python3 "$script" "$@" 2>&1); rc=$?; }
line() { printf '%s\n' "$out" | tail -n 1; }
sj() { jq -e "$@" "$g/summary.json" > /dev/null; }
sha() { git rev-parse HEAD | cut -c1-12; }
eq() { [ "$1" = "$2" ] || { printf '     got:  %s\n     want: %s\n' "$1" "$2"; return 1; }; }
ends() { eq "$rc" "$1" && eq "$(line)" "$2"; } # $1 exit code, $2 result line
refused() { # $1 text the message must hold; exit 2 and nothing ran
  [ "$rc" -eq 2 ] && [ ! -e "$g" ] && grep -qF -- "$1" <<<"$out" && return 0
  printf '     rc=%s\n     %s\n' "$rc" "$out"; return 1
}

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
check "the summary records the commit and the result line" \
  eq "$(jq -r '.commit, .line' "$g/summary.json" | tr -d '\r')" "$(git rev-parse HEAD; line)"
check "the summary records the tree and each check" \
  sj '.schema == 1 and .clean == true and .status == "pass" and
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
check "checks after a failure still run" eq "$(cat "$g/b.log")" two
check "the summary records the failure" \
  sj '.status == "fail" and (.checks | map(.status)) == ["fail", "pass"] and .checks[0].exit == 3'

repo; one '"false | true"'; gate
check "run is bash with pipefail" eq "$rc" 1

repo; one '"echo a; echo b >&2; echo c"'; gate
check "output and errors share one ordered log" eq "$(cat "$g/a.log")" $'a\nb\nc'

repo; one '"printf x"'; gate
check "output with no final newline keeps the result line whole" \
  ends 0 "gate: PASS 1/1 checks at $(sha) clean: a ok"
check "the log gains no newline" eq "$(od -An -c "$g/a.log" | tr -d ' ')" x

repo; one '"true"'; echo y >> README; gate
check "a changed tracked file is recorded as dirty" \
  ends 0 "gate: PASS 1/1 checks at $(sha) dirty: a ok"
check "the summary records the dirty tree" sj '.clean == false'

repo; one '"true"'; echo y > new.txt; gate
check "an untracked file is recorded as dirty" sj '.clean == false'

repo; one '"test -f gate.toml"'; mkdir sub; cd sub || exit 1; gate
check "a run from a subfolder uses the repo root" eq "$rc" 0

repo; one '"true"'
git worktree add -q "$tmp/w$nrepo" -b "w$nrepo"; cd "$tmp/w$nrepo" || exit 1; gate
check "a linked worktree keeps its own summary" \
  test -f "$(git rev-parse --absolute-git-dir)/gate/summary.json" -a ! -e "$g"

repo; one '"cat"'; gate <<<leak
check "a check reading stdin gets end of file" test "$rc" -eq 0 -a ! -s "$g/a.log"

repo; list < "$root/fixtures/gate/gate.toml"; gate f4
check "99 target lines and 85 result lines fail the pair" \
  ends 1 "gate: FAIL 1/2 checks at $(sha) clean: f4 FAIL 99!=85"
check "the summary records both counts" \
  sj '.skipped == ["pass"] and (.checks[0] | .count == [99, 85] and .exit == 0 and .status == "fail")'

repo; one '"echo x; echo y; echo x; echo y; echo x; echo y"' '["^x$", "^y$"]'; gate
check "equal counts pass" ends 0 "gate: PASS 1/1 checks at $(sha) clean: a ok 3=3"

repo; one '"echo z"' '["^x$", "^y$"]'; gate
check "a pair that matches nothing fails" ends 1 "gate: FAIL 1/1 checks at $(sha) clean: a FAIL 0=0"

repo; one '"echo x; echo y; exit 1"' '["^x$", "^y$"]'; gate
check "a non-zero exit fails with equal counts" \
  ends 1 "gate: FAIL 1/1 checks at $(sha) clean: a FAIL exit 1 1=1"

repo; list <<'EOF'
[[check]]
name = "a"
run = '''printf '\033[32m     Running x\033[0m\r\ndone\r\n' '''
count = ['^\s+Running x$', '^done$']
EOF
gate
check "colour codes and CRLF do not hide a match" \
  ends 0 "gate: PASS 1/1 checks at $(sha) clean: a ok 1=1"

repo; list <<'EOF'
[[check]]
name = "a"
run = '''printf '\377\nx\ny\n' '''
count = ['^x$', '^y$']
EOF
gate
check "bytes that are not UTF-8 do not stop the run" eq "$rc" 0
check "the log keeps the raw bytes" eq "$(od -An -tx1 -N1 "$g/a.log" | tr -d ' ')" ff

repo; list <<'EOF'
[[check]]
name = "a"
run = "true"

[[check]]
name = "b"
run = "true"

[[check]]
name = "c"
run = "true"
EOF
gate c a
check "named checks run alone, in list order" \
  ends 0 "gate: PASS 2/3 checks at $(sha) clean: a ok, c ok"
check "the summary names the checks that ran and the rest" \
  sj '(.checks | map(.name)) == ["a", "c"] and .skipped == ["b"]'
check "a skipped check writes no log" test ! -e "$g/b.log"

repo; one '"true"'; gate a nope
check "an unknown name is refused before anything runs" refused nope

local_list() { printf '[[check]]\nname = "%s"\nrun = "true"\n' "$1" > gate.local.toml; }
ignoring() { echo gate.local.toml > .gitignore; git add .gitignore; }

repo; ignoring; one '"true"'; local_list z; gate
check "the local list is added after the shared list" \
  ends 0 "gate: PASS 2/2 checks at $(sha) clean: a ok, z ok"
check "the summary names the list of each check" \
  sj '.clean and (.checks | map(.source)) == ["gate.toml", "gate.local.toml"]'

repo; ignoring; one '"true"'; local_list a; gate
check "a local check cannot replace a shared check" refused '"a"'

repo; one '"true"'; local_list z; gate
check "a local list that git does not ignore is refused" refused gate.local.toml

repo; one '"true"'; local_list z; git add gate.local.toml; git commit -qm local; ignoring; gate
check "a tracked local list is refused" refused gate.local.toml

# gate refuses a bad list before it writes, so one repo serves every case.
repo
bad() { cat > gate.toml; gate; refused "$1"; } # $1 text the message must hold; stdin = gate.toml
ok='[[check]]
name = "a"
run = "true"'
check "bad list: not TOML" bad 'gate.toml: ' <<<'[[check'
check "bad list: no checks" bad 'gate.toml: no checks' <<<''
check "bad list: unknown top-level key" bad 'gate.toml: unknown key "checks"' <<<"$ok
[[checks]]
name = \"b\""
check "bad list: unknown check key" bad 'check "a": unknown key "cout"' <<<"$ok
cout = ['x', 'y']"
check "bad list: check is not a table" bad 'gate.toml: no checks' <<<'check = "a"'
check "bad list: no name" bad 'gate.toml: name ' <<<'[[check]]
run = "true"'
check "bad list: a name that is a path" bad 'gate.toml: name ' <<<'[[check]]
name = "../x"
run = "true"'
check "bad list: no run" bad 'check "a": run ' <<<'[[check]]
name = "a"'
check "bad list: run is not a string" bad 'check "a": run ' <<<'[[check]]
name = "a"
run = 1'
check "bad list: two checks with one name" bad 'two checks are named "a"' <<<"$ok
$ok"
check "bad list: names that differ only by case" bad 'two checks are named "Test"' <<<'[[check]]
name = "Test"
run = "true"
[[check]]
name = "test"
run = "true"'
check "bad list: count with one pattern" bad 'check "a": count ' <<<"$ok
count = ['x']"
check "bad list: count that is not patterns" bad 'check "a": count ' <<<"$ok
count = [1, 2]"
check "bad list: count with a bad pattern" bad 'check "a": count ' <<<"$ok
count = ['(', 'y']"

repo; gate
check "no gate.toml is refused" refused 'gate.toml'

mkdir "$tmp/plain"; cd "$tmp/plain" || exit 1; g=$PWD/.git/gate
GIT_CEILING_DIRECTORIES="$tmp" gate
check "a folder outside git is refused" refused 'gate: git rev-parse'

mkdir "$tmp/unborn"; cd "$tmp/unborn" || exit 1; g=$PWD/.git/gate
git init -q .; printf '%s\n' "$ok" > gate.toml; gate
check "a repo with no commit is refused" refused 'gate: git rev-parse'

repo; one '"true"'
out=$(PYTHONPATH="$root/.github/scripts" python3 -c '
import shutil, gate
shutil.which = lambda name: None
raise SystemExit(gate.main([]))' 2>&1); rc=$?
check "a PATH with no bash is refused" refused 'bash'

out=$(PYTHONPATH="$root/.github/scripts" python3 -c '
import sys
sys.modules["tomllib"] = None
import gate' 2>&1); rc=$?
check "a Python with no tomllib is refused" refused 'Python 3.11'

repo; one '"true"'; gate; printf '[[check' > gate.toml; gate
check "a refused run leaves no earlier summary" test "$rc" -eq 2 -a ! -e "$g/summary.json"

repo répo; one '"true"'; gate
check "a repo path with a non-ASCII letter works" eq "$rc" 0

finish
