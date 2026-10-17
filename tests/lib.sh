# Shared by tests/*.test.sh: source it first.
# shellcheck shell=bash
set -u
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
fails=0
nresp=0
export GH="$root/tests/fake-gh" FAKE_GH_RULES="$tmp/rules" FAKE_GH_LOG="$tmp/gh.log"
reset_gh() { : > "$FAKE_GH_RULES"; : > "$FAKE_GH_LOG"; }
rule() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$FAKE_GH_RULES"; }
respond() { # $1 glob, $2 response text; exit 0
  nresp=$((nresp + 1)); printf '%s' "$2" > "$tmp/resp$nresp"; rule "$1" 0 "$tmp/resp$nresp"
}
check() { # $1 name, rest = command that must succeed
  local name=$1; shift
  if "$@"; then echo "ok   $name"; else echo "FAIL $name"; fails=$((fails + 1)); fi
}
finish() { if [ "$fails" -eq 0 ]; then echo "all passed"; else echo "$fails failed"; exit 1; fi; }
reset_gh
