#!/usr/bin/env bash
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
script="$root/.github/scripts/licenses.py"
nproj=0
proj() { # fresh project dir with a pyproject; cd into it. $1 = extra toml
  nproj=$((nproj + 1)); mkdir -p "$tmp/p$nproj/site"; cd "$tmp/p$nproj" || exit 1
  printf '[project]\nname = "Self_Pkg"\n%s\n' "${1:-}" > pyproject.toml
}
dist() { # $1 name, $2 version, rest = METADATA header lines
  local d="site/$1-$2.dist-info"; mkdir -p "$d"
  { printf 'Metadata-Version: 2.4\nName: %s\nVersion: %s\n' "$1" "$2"; shift 2; printf '%s\n' "$@"; } > "$d/METADATA"
}
# -S: no site-packages, so only the fake dists on PYTHONPATH are seen.
run() { out=$(PYTHONPATH=site python3 -S "$script" 2>&1); rc=$?; }
passes() { run; [ "$rc" -eq 0 ] || { printf '%s\n' "$out"; return 1; }; }
fails_on() {
  run
  if [ "$rc" -ne 0 ] && printf '%s\n' "$out" | grep -qF -- "$1"; then return 0; fi
  printf 'rc=%s\n%s\n' "$rc" "$out"; return 1
}

proj; dist a 1 'License-Expression: MIT'
check "plain allowed id" passes
proj; dist a 1 'License-Expression: MIT-CMU AND CNRI-Python'
check "notice-only MIT-CMU and CNRI-Python" passes
proj; dist a 1 'License-Expression: BSD-3-Clause AND 0BSD AND MIT AND Zlib AND CC0-1.0'
check "AND of allowed ids" passes
proj; dist a 1 'License-Expression: MIT AND GPL-3.0-only'
check "AND with a denied id fails" fails_on 'a 1: MIT AND GPL-3.0-only'
proj; dist a 1 'License-Expression: GPL-2.0-or-later OR Apache-2.0'
check "OR with one allowed side" passes
proj; dist a 1 'License-Expression: (MIT OR GPL-3.0-only) AND LGPL-3.0-only'
check "parentheses group before AND" fails_on 'a 1:'
proj; dist a 1 'License-Expression: Apache-2.0 WITH LLVM-exception'
check "WITH keeps the base license" passes
proj; dist a 1 'License-Expression: mit'
check "ids match without case" passes
proj; dist a 1 'License-Expression: LicenseRef-Proprietary'
check "LicenseRef fails" fails_on 'a 1: LicenseRef-Proprietary'
proj; dist a 1 'License-Expression: MIT AND'
check "malformed expression fails" fails_on 'a 1:'

proj; dist a 1 'Classifier: License :: OSI Approved :: MIT License'
check "classifier fallback" passes
proj; dist a 1 'Classifier: License :: OSI Approved :: MIT License' 'Classifier: License :: OSI Approved :: GNU General Public License v3 (GPLv3)'
check "every classifier must be allowed" fails_on 'GNU General Public License v3 (GPLv3)'
proj; dist a 1 'License-Expression: MIT' 'Classifier: License :: OSI Approved :: GNU General Public License v3 (GPLv3)'
check "expression wins over classifiers" passes
proj; dist a 1 'License: Apache-2.0 AND MIT'
check "License field as SPDX" passes
proj; dist a 1 'License: MIT License'
check "License field prose fails" fails_on 'a 1: MIT License'
proj; dist a 1 'License: GPL-3.0-only'
check "License field denied id fails" fails_on 'a 1: GPL-3.0-only'
proj; dist a 1 'License: Apache-2.0' 'Classifier: License :: OSI Approved :: GNU General Public License v3 (GPLv3)'
check "classifiers win over the License field" fails_on 'GNU General Public License v3 (GPLv3)'
proj; dist a 1 'Summary: no license'
check "no license metadata fails" fails_on 'a 1: no license metadata'

proj; dist self-pkg 0 'License-Expression: LicenseRef-Mine'
check "the project itself is skipped" passes

proj '[tool.licenses.exceptions]
"Odd.Pkg==2.0" = "LGPL, shipped as a separate DLL"'
dist odd_pkg 2.0 'License-Expression: LGPL-3.0-only'
check "pinned exception passes" passes
proj '[tool.licenses.exceptions]
"odd-pkg==1.0" = "old pin"'
dist odd_pkg 2.0 'License-Expression: LGPL-3.0-only'
check "exception for another version fails" fails_on 'odd_pkg 2.0: LGPL-3.0-only'
check "stale exception is named" fails_on 'unused exception: odd-pkg==1.0'
proj '[tool.licenses.exceptions]
"a==1" = "no longer needed"'
dist a 1 'License-Expression: MIT'
check "exception for an allowed package fails" fails_on 'unused exception: a==1'

proj; dist a 1 'License-Expression: GPL-3.0-only'; dist b 2 'License-Expression: AGPL-3.0-only'
run
check "every failure is listed" test "$(printf '%s\n' "$out" | grep -c ': .*GPL')" -eq 2
proj; dist a 1 'License-Expression: MIT'
run
check "pass prints the count" grep -qF '1 package' <<< "$out"

finish
