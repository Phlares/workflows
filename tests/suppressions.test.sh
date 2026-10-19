#!/usr/bin/env bash
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
script="$root/.github/scripts/suppressions.py"
# This file is scanned by its own hook (shell row), so that marker is built.
sc="shell""check"
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
check "markdown and untracked files are not scanned" test "$rc" -eq 0 -a "$(nhits)" -eq 0

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
finish
