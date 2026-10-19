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
# Move the committed template aside so files deleted in the working tree go too.
mv "$tpl/template" "$tmp/template.committed"
cp -r "$root/template" "$root/copier.yml" "$tpl/"
git -C "$tpl" add -A && git -C "$tpl" -c user.name=t -c user.email=t@t commit -qm wip --allow-empty
sha=$(git -C "$tpl" rev-parse HEAD)

gen() { # $1 dir name, $2 tier, $3 languages ("python", "node" or "python, node"), rest = copier args
  local d="$tmp/$1" tier=$2 langs=$3; shift 3
  "${copier[@]}" copy --quiet --defaults --vcs-ref HEAD -d tier="$tier" -d "languages=[$langs]" "$@" "$tpl" "$d" 2> "$d.log"
}
sorted() { printf '%s\n' "$@" | sort | paste -sd ' '; }
files() { (cd "$tmp/$1" && find . -type f -not -path './.git/*' | sed 's#^\./##' | sort | paste -sd ' '); }

expect() { # $1 tier, $2 languages -> sorted file list
  local f=(.copier-answers.yml .github/dependabot.yml .github/workflows/ci.yml .gitignore .pre-commit-config.yaml pyproject.toml)
  case $2 in *python*) f+=(ruff.toml) ;; esac
  case "$1 $2" in product*python*) f+=(pyrightconfig.json) ;; esac
  sorted "${f[@]}"
}

combos=("prototype:python" "prototype:node" "prototype:python, node" "product:python" "product:node" "product:python, node")
dir() { local s=${1//, /-}; echo "${s/:/-}"; }

yq() { uv run -q --no-project --with pyyaml==6.0.3 python "$root/tests/yamlq.py" "$@" | tr -d '\r'; }
# Expected jobs: lint always; product adds pytest + typecheck (python), test (node).
expect_jobs() {
  local j=(lint)
  case "$1 $2" in product*python*) j+=(test-py typecheck) ;; esac
  case "$1 $2" in product*node*) j+=(test-js) ;; esac
  sorted "${j[@]}"
}
groups3() { echo "$1:minor,patch $1-major:major $1-security:security-updates"; }

for c in "${combos[@]}"; do
  tier=${c%%:*} langs=${c#*:} d=$(dir "$c")
  check "$d generates" gen "$d" "$tier" "$langs"
  check "$d file set" test "$(files "$d")" = "$(expect "$tier" "$langs")"

  ci="$tmp/$d/.github/workflows/ci.yml" dep="$tmp/$d/.github/dependabot.yml"
  check "$d ci pins the generating commit" grep -qF "check.yml@$sha" "$ci"
  check "$d guard pins the generating commit" grep -qF "rev: $sha" "$tmp/$d/.pre-commit-config.yaml"
  for j in test-py typecheck; do
    yq "$ci" jobs | grep -qw "$j" && check "$d $j installs from the lock" test "$(yq "$ci" job "$j" install)" = "uv sync --locked --group ${j%-py}"
  done
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

# Generated checks run on seed files. The guard hook's commit exists only in
# the template clone, so the hook repo points there.
tpl_url=$(cygpath -m "$tpl" 2>/dev/null || echo "$tpl")
seed() { # $1 dir, $2 languages
  local d="$tmp/$1"
  case $2 in *python*) cp -r "$root/tests/template-seed/seed.py" "$root/tests/template-seed/tests" "$d/" ;; esac
  case $2 in *node*) cp "$root/tests/template-seed/seed.js" "$d/" ;; esac
  sed -i "s#https://github.com/Phlares/workflows#$tpl_url#" "$d/.pre-commit-config.yaml"
  (cd "$d" && git init -q . && git config core.autocrlf false && uv lock -q && git add -A)
}
in_dir() { local d="$tmp/$1"; shift; (cd "$d" && "$@") > "$tmp/out.log" 2>&1; }
lint() { # $1 dir, $2 hook id (empty = all hooks)
  in_dir "$1" sh -c "uv sync -q --locked --only-group lint && git add -A && uv run --no-sync prek run ${2:-} --all-files"
}
fails() { ! "$@"; }
mutate() { # $1 dir, $2 hook id, $3 file, $4 line to prepend; succeeds when that hook then fails; restores the file
  local d="$tmp/$1" hook=$2 file=$3 rc=0
  cp "$d/$file" "$tmp/keep"
  printf '%s\n' "$4" | cat - "$tmp/keep" > "$d/$file"
  lint "$1" "$hook" || rc=1
  cp "$tmp/keep" "$d/$file"
  return $((1 - rc))
}
val() { grep -qxF -- "$2" "$tmp/$1"; } # exact line present

for c in "${combos[@]}"; do
  tier=${c%%:*} langs=${c#*:} d=$(dir "$c")
  seed "$d" "$langs"
  check "$d lint passes on seeds" lint "$d"
  check "$d hook order" test "$(grep -oE 'id: [a-z-]+' "$tmp/$d/.pre-commit-config.yaml" | tr '\n' ' ')" = \
    "$(case $langs in
        python) echo "id: check-merge-conflict id: ruff-check id: ruff-format id: suppressions " ;;
        node) echo "id: check-merge-conflict id: oxlint id: suppressions " ;;
        *) echo "id: check-merge-conflict id: ruff-check id: ruff-format id: oxlint id: suppressions " ;;
      esac)"
  check "$d pyproject lint group" val "$d/pyproject.toml" 'lint = ["prek"]'
  check "$d pyproject python floor" val "$d/pyproject.toml" 'requires-python = ">=3.12"'
  case $langs in *python*)
    check "$d unused noqa fails ruff (RUF100)" mutate "$d" ruff-check seed.py "# noqa: E501"
    if [ "$tier" = product ]; then
      check "$d ruff product select" val "$d/ruff.toml" 'select = ["E", "F", "W", "I", "B", "UP", "RUF100", "PGH004"]'
      check "$d ruff product ignore" val "$d/ruff.toml" 'ignore = ["E501"]'
    else
      check "$d ruff prototype extend-select" val "$d/ruff.toml" 'extend-select = ["RUF100", "PGH004"]'
    fi ;;
  esac
  case $langs in *node*)
    check "$d unused oxlint directive fails oxlint" mutate "$d" oxlint seed.js "// oxlint-disable-next-line no-debugger"
    check "$d oxlint unused directives are errors" val "$d/.pre-commit-config.yaml" "          - --report-unused-disable-directives-severity=error"
    if [ "$tier" = product ]; then
      check "$d oxlint deny warnings" val "$d/.pre-commit-config.yaml" "          - --deny-warnings"
    else
      check "$d prototype allows warnings" fails grep -qF -- "--deny-warnings" "$tmp/$d/.pre-commit-config.yaml"
    fi ;;
  esac
  case "$tier $langs" in product*python*)
    pc="$d/pyrightconfig.json"
    check "$d pyright standard" val "$pc" '  "typeCheckingMode": "standard",'
    check "$d pyright ignores off" val "$pc" '  "enableTypeIgnoreComments": false,'
    check "$d pyright stale ignore is an error" val "$pc" '  "reportUnnecessaryTypeIgnoreComment": "error",'
    check "$d pyright version" val "$pc" '  "pythonVersion": "3.12",'
    check "$d pyright platform" val "$pc" '  "pythonPlatform": "Linux",'
    ci="$tmp/$d/.github/workflows/ci.yml"
    for j in test-py typecheck; do
      check "$d $j job passes" in_dir "$d" sh -c "$(yq "$ci" job $j install) && $(yq "$ci" job $j run)"
    done
    printf 'VALUE = 1  # pyright: ignore[reportGeneralTypeIssues]\n' > "$tmp/$d/stale.py"
    check "$d stale pyright ignore fails" fails in_dir "$d" uv run --no-sync pyright
    rm "$tmp/$d/stale.py" ;;
  esac
done

# Review Focus 2: an existing pyproject.toml stays as it was, and the message
# names the groups to add.
mkdir -p "$tmp/has-pyproject" && printf '[project]\nname = "mine"\n' > "$tmp/has-pyproject/pyproject.toml"
cp "$tmp/has-pyproject/pyproject.toml" "$tmp/mine.toml"
copy_msg() { "${copier[@]}" copy --defaults --vcs-ref HEAD -d tier=product -d "languages=[python]" "$tpl" "$tmp/has-pyproject" > "$tmp/msg.log" 2>&1; }
check "copy over an existing pyproject" copy_msg
check "existing pyproject kept" cmp -s "$tmp/mine.toml" "$tmp/has-pyproject/pyproject.toml"
check "message names the groups" grep -qF 'typecheck = ["pyright"]' "$tmp/msg.log"
check "message installs prek before using it" grep -qF 'uv sync --only-group lint && uv run --no-sync prek install' "$tmp/msg.log"

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
check "windows: pyright platform" val win/pyrightconfig.json '  "pythonPlatform": "Windows",'

# Update flow (C3): two tagged template versions in their own clone.
tpl2="$tmp/tpl2"
git clone -q --no-local "$tpl" "$tpl2"
gitc() { git -C "$1" -c user.name=t -c user.email=t@t "${@:2}"; }
# Only the two test tags: the clone also holds this repo's tags, which predate the template.
for t in $(git -C "$tpl2" tag); do git -C "$tpl2" tag -d "$t" > /dev/null; done
gitc "$tpl2" tag v0.0.1
printf '%s\n' "# probe: template v2" | cat - "$tpl2/template/.pre-commit-config.yaml.jinja" > "$tmp/v2" &&
  mv "$tmp/v2" "$tpl2/template/.pre-commit-config.yaml.jinja"
gitc "$tpl2" commit -qam v2 && gitc "$tpl2" tag v0.0.2
genv1() { # $1 dir, $2 tier: generate at v0.0.1 and commit
  "${copier[@]}" copy --quiet --defaults --vcs-ref v0.0.1 -d tier="$2" -d "languages=[python]" "$tpl2" "$tmp/$1" &&
    gitc "$tmp/$1" init -q && gitc "$tmp/$1" add -A && gitc "$tmp/$1" commit -qm v1
}
update() { local d=$1; shift; (cd "$tmp/$d" && "${copier[@]}" update --defaults --vcs-ref v0.0.2 "$@") > "$tmp/$d.update.log" 2>&1; }

old_rev="38bfb07c0c64c304f47eb52090f8288150c77730  # frozen: v0.17.1"
new_rev="1111111111111111111111111111111111111111  # frozen: v0.99.0"
genv1 upd prototype
sed -i "s/$old_rev/$new_rev/" "$tmp/upd/.pre-commit-config.yaml"
gitc "$tmp/upd" commit -qam "bump ruff (as Dependabot)"
check "update runs" update upd
cfg="$tmp/upd/.pre-commit-config.yaml"
check "update brings the template change" grep -qxF "# probe: template v2" "$cfg"
kept_or_conflict() { # the pin edit survives, or the conflict is loud
  if grep -q '^<<<<<<<' "$cfg"; then
    fails sh -c "cd '$tmp/upd' && uv run -q --no-project --with pre-commit-hooks==6.0.0 check-merge-conflict --assume-in-merge .pre-commit-config.yaml"
  else
    grep -qF "$new_rev" "$cfg" && fails grep -qF "$old_rev" "$cfg"
  fi
}
check "update keeps the Dependabot pin or marks a conflict" kept_or_conflict

# Review Focus 1: prototype -> product on update adds the product files and values.
genv1 tier prototype
check "tier change runs" update tier -d tier=product
check "tier change: pyrightconfig.json" test -f "$tmp/tier/pyrightconfig.json"
check "tier change: product ruff rules" val tier/ruff.toml 'select = ["E", "F", "W", "I", "B", "UP", "RUF100", "PGH004"]'
check "tier change: typecheck job" test "$(yq "$tmp/tier/.github/workflows/ci.yml" jobs)" = "lint test-py typecheck"
check "tier change: message points at the groups" grep -qF "[dependency-groups]" "$tmp/tier.update.log"

# A copy with no --vcs-ref takes the newest tag; the pin comments name it.
check "copy from the newest tag" "${copier[@]}" copy --quiet --defaults -d tier=prototype -d "languages=[python]" "$tpl2" "$tmp/notag"
check "ci pin comment names the tag" grep -qE "check.yml@[0-9a-f]{40} # v0.0.2$" "$tmp/notag/.github/workflows/ci.yml"
check "guard rev comment names the tag" grep -qE "rev: [0-9a-f]{40}  # frozen: v0.0.2$" "$tmp/notag/.pre-commit-config.yaml"

finish
