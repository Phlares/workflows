#!/usr/bin/env bash
# Generates every tier and language set from the copier template and checks
# the files and their checks. Needs uv, git and actionlint on PATH (or
# ACTIONLINT); hook and package downloads need the network.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
copier=(uvx -q copier@9.19.1)

# The template from a clone of this checkout with uncommitted template files
# on top, so the generating commit (C2) exists and dirty edits are tested.
tpl="$tmp/tpl"
git clone -q --no-local "$root" "$tpl"
cp -r "$root/template" "$root/copier.yml" "$tpl/" 2>/dev/null
git -C "$tpl" add -A && git -C "$tpl" -c user.name=t -c user.email=t@t commit -qm wip --allow-empty
sha=$(git -C "$tpl" rev-parse HEAD)

gen() { # $1 dir name, $2 tier, $3 languages ("python", "node" or "python, node"), rest = copier args
  local d="$tmp/$1" tier=$2 langs=$3; shift 3
  "${copier[@]}" copy --quiet --defaults --vcs-ref HEAD -d tier="$tier" -d "languages=[$langs]" "$@" "$tpl" "$d" 2> "$d.log"
}
files() { (cd "$tmp/$1" && find . -type f -not -path './.git/*' | sed 's#^\./##' | sort | tr '\n' ' ' | sed 's/ $//'); }

common=".copier-answers.yml .github/dependabot.yml .github/workflows/ci.yml .gitignore .pre-commit-config.yaml pyproject.toml"
expect() { # $1 tier, $2 languages -> sorted file list
  local f=$common
  case $2 in *python*) f="$f ruff.toml" ;; esac
  case "$1 $2" in product*python*) f="$f pyrightconfig.json" ;; esac
  printf '%s\n' $f | sort | tr '\n' ' ' | sed 's/ $//'
}

combos=("prototype:python" "prototype:node" "prototype:python, node" "product:python" "product:node" "product:python, node")
dir() { local s=${1//, /-}; echo "${s/:/-}"; }

yq() { uv run -q --no-project --with pyyaml==6.0.3 python "$root/tests/yamlq.py" "$@" | tr -d '\r'; }
has() { grep -qF -- "$2" "$tmp/$1"; } # $1 path under $tmp, $2 fixed text
# Expected jobs: lint always; product adds pytest + typecheck (python), test (node).
expect_jobs() {
  local j=lint
  case "$1 $2" in product*python*) j="$j test-py typecheck" ;; esac
  case "$1 $2" in product*node*) j="$j test-js" ;; esac
  printf '%s\n' $j | sort | tr '\n' ' ' | sed 's/ $//'
}
groups3() { echo "$1:minor,patch $1-major:major $1-security:security-updates"; }

for c in "${combos[@]}"; do
  tier=${c%%:*} langs=${c#*:} d=$(dir "$c")
  check "$d generates" gen "$d" "$tier" "$langs"
  check "$d file set" test "$(files "$d")" = "$(expect "$tier" "$langs")"

  ci="$tmp/$d/.github/workflows/ci.yml" dep="$tmp/$d/.github/dependabot.yml"
  check "$d ci pins the generating commit" test "$(grep -c "check.yml@$sha" "$ci")" -ge 1
  check "$d ci jobs" test "$(yq "$ci" jobs)" = "$(expect_jobs "$tier" "$langs")"
  check "$d ci actionlint" "${ACTIONLINT:-actionlint}" -shellcheck= "$ci"
  check "$d ci lint install" test "$(yq "$ci" job lint install)" = "uv sync --locked --only-group lint"
  check "$d dependabot schema" uvx -q check-jsonschema@0.38.2 --builtin-schema vendor.dependabot "$dep"
  eco="github-actions pre-commit uv"
  case $langs in *node*) eco="github-actions npm pre-commit uv" ;; esac
  check "$d dependabot ecosystems" test "$(yq "$dep" ecosystems)" = "$eco"
  check "$d actions groups" test "$(yq "$dep" groups github-actions | head -1)" = "$(groups3 actions)"
  check "$d uv groups" test "$(yq "$dep" groups uv | paste -sd ' ')" = "$(groups3 python) lockfile-only"
  check "$d hooks group" test "$(yq "$dep" groups pre-commit | head -1)" = "hooks:all"
  case $langs in *node*) check "$d npm groups" test "$(yq "$dep" groups npm | head -1)" = "$(groups3 npm)" ;; esac
done

# Review Focus 3 and 5: both test jobs have distinct names; Windows target
# moves the test jobs only.
check "both langs: distinct check names" test "$(yq "$tmp/product-python-node/.github/workflows/ci.yml" job test-py name)" != \
  "$(yq "$tmp/product-python-node/.github/workflows/ci.yml" job test-js name)"
gen win product "python, node" -d target_os=windows-latest
wci="$tmp/win/.github/workflows/ci.yml"
check "windows: pytest on windows" test "$(yq "$wci" job test-py runs-on)" = windows-latest
check "windows: node test on windows" test "$(yq "$wci" job test-js runs-on)" = windows-latest
check "windows: typecheck on ubuntu" test "$(yq "$wci" job typecheck runs-on)" = ubuntu-latest
check "windows: lint on ubuntu" test "$(yq "$wci" job lint runs-on)" = ubuntu-latest

finish
