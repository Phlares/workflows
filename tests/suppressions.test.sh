#!/usr/bin/env bash
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
script="$root/.github/scripts/suppressions.py"
# This file is scanned by its own hook (shell row), so that marker is built.
sc="shell""check"
ga="gitleaks"":allow"
nrepo=0
repo() { # fresh git repo; cd into it
  nrepo=$((nrepo + 1)); mkdir -p "$tmp/r$nrepo"; cd "$tmp/r$nrepo" || exit 1
  git init -q . && git config core.autocrlf false
}
put() { # $1 path, $2 line
  mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; git add -- "$1"
}
hook() { out=$(python3 "$script" "$@" 2>&1); rc=$?; }
hits() { printf '%s\n' "$out" | sed 's/^ *//' | grep -E '^[^ ]+:[0-9]+: ' || true; }
nhits() { hits | grep -c . || true; }

# One sample per marker: file, kind (c = count, f = always fails), name, line.
samples=$(cat <<EOF
a.py	c	type: ignore	x = 1  # type: ignore[assignment]
a.py	f	bare type: ignore	x = 1  # type: ignore
a.py	c	pyright: ignore	x = 1  # pyright: ignore[reportFoo]
a.py	f	bare pyright: ignore	x = 1  # pyright: ignore
a.py	c	noqa	import os  # noqa: F401
a.py	f	blanket noqa	import os  # NOQA
a.py	c	ruff: noqa	# ruff: noqa: E501
a.py	f	blanket ruff: noqa	# flake8: noqa
a.py	c	pragma: no cover	if x:  # pragma: no cover
a.py	c	fmt: off	# fmt: off
a.py	c	fmt: skip	x = [1,2]  # fmt: skip
t.py	c	pytest.mark.skip	@pytest.mark.skipif(sys.platform == "win32", reason="x")
t.py	c	pytest.mark.xfail	@pytest.mark.xfail
t.py	c	pytest.skip	    pytest.skip("no build")
t.py	c	pytest.importorskip	torch = pytest.importorskip("torch")
a.js	c	eslint-disable	// eslint-disable-next-line no-console
a.js	f	bare eslint-disable	/* eslint-disable */
a.ts	c	oxlint-disable	// oxlint-disable-next-line no-control-regex
a.ts	f	bare oxlint-disable	// oxlint-disable
a.ts	c	biome-ignore	// biome-ignore lint/style/useConst: why
a.ts	c	@ts-ignore	// @ts-ignore
a.ts	c	@ts-expect-error	// @ts-expect-error wrong type on purpose
a.ts	c	@ts-nocheck	// @ts-nocheck
a.js	c	istanbul ignore	/* istanbul ignore next */
a.js	c	c8 ignore	/* c8 ignore next */
a.js	c	v8 ignore	/* v8 ignore next */
a.test.js	c	.skip	it.skip("x", () => {});
a.test.js	c	.skipIf	describe.skipIf(!ok)("x", () => {});
a.test.js	c	.todo	it.todo("x");
a.test.js	f	.only	it.only("x", () => {});
a.css	c	stylelint-disable	/* stylelint-disable-next-line color-no-hex */
a.css	f	bare stylelint-disable	/* stylelint-disable */
a.sh	c	shellcheck disable	# $sc disable=SC2034
.github/actionlint.yaml	c	actionlint ignore	    ignore:
.env.example	c	gitleaks allow	TOKEN=abc  # $ga
.gitleaksignore	f	.gitleaksignore entry	abc123:a.py:generic-api-key:1
.gitleaks.toml	f	.gitleaks.toml entry	[extend]
EOF
)

repo; hook --markers
check "--markers lists exactly the sampled names" \
  test "$(printf '%s\n' "$out" | sort)" = "$(printf '%s\n' "$samples" | cut -f3 | sort)"
while IFS=$'\t' read -r f kind name line; do
  repo; put "$f" "$line"; hook
  want="$f:1: $name"; [ "$kind" = f ] && want="$want always fails"
  check "sample: $name" test "$rc" -eq 1 -a "$(hits)" = "$want" || echo "     $out"
done <<<"$samples"

repo; put a.py 'import os  # noqa: E501'; put b.py 'x = 1  # type: ignore[x]'
put a.js '// eslint-disable-next-line no-console'; hook
check "scoped forms are counted, not forbidden" test "$(nhits)" -eq 3 -a "${out/always fails/}" = "$out"

repo; put a.js '// eslint-disable-next-line -- why'; put b.js '/* eslint-disable */'; hook
check "a reason tail with no rule is bare" test "$(hits | grep -c 'bare eslint-disable always fails')" -eq 2

repo; put a.py '// eslint-disable-next-line no-x'; put a.js '# noqa: E1'; hook
check "markers are scoped to their language" test "$rc" -eq 0 -a "$(nhits)" -eq 0

repo; put a.py 'x = "type: ignore[x]"'; hook
check "a marker with no comment opener is not counted" test "$rc" -eq 0

repo; put notes.md '# noqa: E1'; printf '%s\n' '# noqa: E1' > b.py; hook
check "markdown has no noqa row; untracked files are not scanned" test "$rc" -eq 0 -a "$(nhits)" -eq 0

repo; printf '%s
' '# why' '' > .gitleaksignore; printf '%s
' '# note' > .gitleaks.toml; git add -A; hook
check "comment and blank lines in gitleaks files pass" test "$rc" -eq 0 -a "$(nhits)" -eq 0

repo; printf '\0%s\n' "$ga" > a.bin; git add a.bin; hook
check "binary files skip the all-files row" test "$rc" -eq 0 -a "$(nhits)" -eq 0
repo; printf '\0\nabc:a.py:generic-api-key:1\n' > .gitleaksignore; printf '\0\nx = 1  # NOQA\n' > a.py; git add -A; hook
check "a NUL does not hide language or gitleaks rows" test "$(nhits)" -eq 3 || echo "     $out"

repo; put notes.md "see $ga here"; hook
check "gitleaks allow counts in markdown" test "$(hits)" = "notes.md:1: gitleaks allow"

repo; put a.py 'x = 1  # noqa: E1  # type: ignore[y]'; hook
check "two markers on one line count twice" test "$(nhits)" -eq 2

repo; printf 'x = 1  # noqa: E1\r\n' > a.py; git add a.py; hook
check "a CRLF line counts the same" test "$(hits)" = "a.py:1: noqa"

repo; printf '\xff\n# noqa: E1\n' > a.py; git add a.py
blob=$(printf 'a.py' | git hash-object -w --stdin)
git update-index --add --cacheinfo "120000,$blob,link.py"
mkdir dir.py; git update-index --add --cacheinfo "160000,$blob,dir.py"
hook
check "bad bytes, symlinks and submodules do not crash the scan" test "$(hits)" = "a.py:2: noqa" || echo "     $out"

# Baseline file.
T=$'\t'
base() { printf '%s\n' "$@" > .suppressions; }
has_out() { [[ $out == *"$1"* ]]; }

repo; put a.env "K=v  # $ga"; base "a.env${T}gitleaks allow${T}1${T}why"; git add .suppressions; hook
check "baseline lines do not count as gitleaks allow" test "$rc" -eq 0 || echo "     $out"

repo; hook
check "no file and no markers passes" test "$rc" -eq 0

repo; put a.py 'import os  # noqa: E1'; hook
check "no file means a baseline of 0" has_out "a.py: noqa: 1 > baseline 0"

repo; put a.py 'import os  # noqa: E1'; base "a.py${T}noqa${T}1${T}why"; hook
check "at baseline passes and leaves the file" test "$rc" -eq 0 -a "$(cat .suppressions)" = "a.py${T}noqa${T}1${T}why"

repo; printf '%s\n' 'a  # noqa: E1' 'b  # noqa: E2' > a.py; git add a.py; base "a.py${T}noqa${T}1${T}why"; hook
check "above baseline fails, file unchanged" test "$rc" -eq 1 -a "$(cat .suppressions)" = "a.py${T}noqa${T}1${T}why"
check "above baseline lists every hit" test "$(nhits)" -eq 2
hook --update
check "--update never raises a count" test "$rc" -eq 1 -a "$(cat .suppressions)" = "a.py${T}noqa${T}1${T}why"

repo; put a.py 'import os  # noqa: E1'; base "a.py${T}noqa${T}3${T}why"; hook
check "below baseline fails and says so" test "$rc" -eq 1 && check "  with the drop" has_out "a.py: noqa: 3 -> 1"
check "below baseline rewrites the count" test "$(cat .suppressions)" = "a.py${T}noqa${T}1${T}why"

repo; put a.py 'import os  # noqa: E1'; base "a.py${T}noqa${T}3${T}why"; hook --update
check "--update on a drop exits 0" test "$rc" -eq 0 -a "$(cat .suppressions)" = "a.py${T}noqa${T}1${T}why"

repo; put a.py 'x = 1'; base "a.py${T}noqa${T}1${T}why"; hook
check "a drop to 0 removes the empty file" test "$rc" -eq 1 -a ! -e .suppressions

repo; put a.py 'import os  # noqa: E1'
base "gone.py${T}noqa${T}2${T}old" "a.py${T}noqa${T}1${T}why"; hook
check "a deleted file's line is dropped" test "$(cat .suppressions)" = "a.py${T}noqa${T}1${T}why"

repo; put a.py 'import os  # noqa: E1'; put b.py 'import os  # noqa: E1'
base "b.py${T}noqa${T}2${T}y" "a.py${T}noqa${T}1${T}x"; hook
check "the rewrite is sorted" test "$(cat .suppressions)" = "a.py${T}noqa${T}1${T}x"$'\n'"b.py${T}noqa${T}1${T}y"

repo; put a.py 'import os  # noqa: E1'; base "a.py${T}noqa${T}1${T} "; hook
check "an empty reason fails" test "$rc" -eq 1 && check "  and names it" has_out "reason"
while IFS='|' read -r line want; do
  base "${line//,/$T}"; hook; check "bad line fails: $want" has_out ".suppressions:1: $want"
done <<'EOF'
a.py,noqa,1|want path
a.py,noqa,0,x|count must be
a.py,noqa,x,x|count must be
a.py,nope,1,x|'nope' is not a counted marker
EOF
base "a.py${T}noqa${T}1${T}x" "a.py${T}noqa${T}1${T}x"; hook
check "a duplicate line fails" has_out ".suppressions:2: duplicate line"
base "a.py${T}noqa${T}3${T}x" "b.py${T}noqa${T}1${T}"; hook
check "a file with a bad line is not rewritten" test "$rc" -eq 1 -a "$(cat .suppressions)" = "a.py${T}noqa${T}3${T}x"$'\n'"b.py${T}noqa${T}1${T}"

repo; put a.py 'x = 1  # type: ignore'; base "a.py${T}bare type: ignore${T}1${T}x"; hook
check "an always-fail form ignores the baseline" test "$rc" -eq 1 && check "  and says so" has_out "always fails"

repo; put a.py 'import os  # noqa: E1'; printf 'a.py\tnoqa\t1\twhy\r\n\r\n' > .suppressions; hook
check "a CRLF baseline with a blank line parses" test "$rc" -eq 0 || echo "     $out"

repo; put a.py 'import os  # noqa: E1'; base "a.py${T}noqa${T}2${T}a${T}b"; hook
check "a tab inside the reason survives the rewrite" test "$(cat .suppressions)" = "a.py${T}noqa${T}1${T}a${T}b"

repo; put b.py 'import os  # noqa: E1'; base "a.py${T}noqa${T}1${T}keep me"; hook
check "a rename keeps the old line while counts fail" test "$rc" -eq 1 -a "$(cat .suppressions)" = "a.py${T}noqa${T}1${T}keep me"

repo; put a.py 'import os  # noqa: E1'; printf '\xef\xbb\xbfa.py\tnoqa\t1\twhy\n' > .suppressions; hook
check "a BOM baseline parses" test "$rc" -eq 0 || echo "     $out"

wide=$(printf '\xe6\x97\xa5.py')
repo; put "$wide" 'import os  # noqa: E1'; hook
check "a non-ASCII path prints" has_out "$wide: noqa: 1 > baseline 0" || echo "     $out"

repo; put src/a.py 'import os  # noqa: E1'; base "src/a.py${T}noqa${T}1${T}why"; cd src || exit 1; hook
check "a run from a subfolder uses the repo root" test "$rc" -eq 0 || echo "     $out"
finish
