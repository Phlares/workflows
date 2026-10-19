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

for c in "${combos[@]}"; do
  tier=${c%%:*} langs=${c#*:} d=$(dir "$c")
  check "$d generates" gen "$d" "$tier" "$langs"
  check "$d file set" test "$(files "$d")" = "$(expect "$tier" "$langs")"
done

finish
