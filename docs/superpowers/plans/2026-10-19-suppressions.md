# Shared Suppression Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One prek hook, published from this repo, that counts suppression markers per file and per marker and fails when a count rises above the caller's `.suppressions` baseline.

**Architecture:** One stdlib-only Python script, `.github/scripts/suppressions.py`. It holds one marker table (name, file globs, regex, kind) as data. It lists tracked files with `git ls-files`, counts regex hits per (path, marker), and compares them with `.suppressions`. A count that drops makes it rewrite the baseline and exit 1, like a formatter. A bash test file drives the script against throwaway git repos.

**Tech Stack:** Python ≥ 3.10 (stdlib only), prek `language: python` (setuptools console script), bash tests with `tests/lib.sh`, shellcheck, ruff.

**Spec:** Phlares/workflows#28 (body) and its design-decision comment (issuecomment-6272648381).

## Global Constraints

- One script, one marker table. The table is data. No per-language or per-caller branches, and no flags that change which markers count.
- `.suppressions` line: `path<TAB>marker<TAB>count<TAB>reason`. No header, no comment lines. An absent file means a baseline of 0.
- Test skips count by default. No opt-in flag.
- These always fail, whatever the baseline: bare `type: ignore`, `pyright: ignore` without `[rule]`, blanket `noqa`, `ruff: noqa` / `flake8: noqa` without codes, `eslint-disable` / `oxlint-disable` / `stylelint-disable` without a rule, and `.only`.
- Never raise a count automatically.
- `*.md` and files with no extension are not scanned.
- Tests live in `tests/suppressions.test.sh`, run by the `fix-unit` job loop. The shell files stay shellcheck-clean.
- The script source and the test file must not contain a literal marker that their own table row would count (this repo runs the hook on itself). Build such strings from parts, e.g. `sc="shell""check"`.
- No other repo gets the hook in this PR (wave 2).

## Windows gate (done before this plan)

Probe on this machine, 2026-10-19, prek 0.5.5:
- `language: script` with a `#!/usr/bin/env bash` entry: `git commit` ran Git Bash (MINGW64, pass). `prek run --all-files` from PowerShell ran `C:\WINDOWS\system32\bash.exe` (WSL) and failed with exit 127. PowerShell's PATH lists only the System32 and WindowsApps `bash.exe`.
- `language: python` with a setuptools console script from `.github/scripts/`: `prek run` and `git commit` both passed (Python 3.13.15).

The design decision says to switch to Python if prek resolves WSL bash, so the hook is Python. Task 4 re-runs the probe against the real hook.

## Review Focus

- Run from a subfolder (someone runs `python .../suppressions.py` by hand inside `src/`): paths and the `.suppressions` lookup stay repo-root relative. Pinned in Task 2.
- A baselined file is deleted or renamed: its line counts as 0 and the rewrite drops it. Pinned in Task 2.
- A `.suppressions` with CRLF endings (Windows `autocrlf` checkout) or a trailing blank line parses the same. The rewrite writes LF. Pinned in Task 2.
- A tracked file that is not valid UTF-8, or a tracked symlink or submodule entry, does not crash the scan. Pinned in Task 1.
- A reason that holds a tab stays whole (split at most 3 times). Pinned in Task 2.

---

### Task 1: Marker table and counting

**Files:**
- Create: `.github/scripts/suppressions.py`
- Create: `tests/suppressions.test.sh`

**Interfaces:**
- Produces: `MARKERS: list[tuple[str, tuple[str, ...], str, str]]` = (name, globs, regex, kind), where kind is `"count"` or `"forbid"`.
- Produces: `scan(paths: list[str]) -> tuple[dict[tuple[str, str], list[int]], list[tuple[str, int, str]]]`. The first value maps (path, marker name) to the hit line numbers. The second lists forbidden hits as (path, line, name).
- Produces: CLI `suppressions.py --markers`, which prints one marker name per line, in table order.
- Produces: `main(argv: list[str] | None = None) -> int`. In this task, without a baseline, it prints `path:line: name` for each hit and returns 1 if any hit exists.

Glob matching uses `fnmatch` on the POSIX path (`*` crosses `/`). Each regex runs per line with `re.finditer`, so two hits on one line count 2. Read files as bytes, decode UTF-8 with `errors="replace"`, and skip paths that are not regular files (`os.path.isfile`, which is False for a submodule folder; symlinks: skip with `os.path.islink`).

The marker table. `C` = `(?://+|/\*+)\s*`, the JS/CSS comment opener. Python rows use `#\s*`.

| name | globs | regex | kind |
|---|---|---|---|
| `type: ignore` | `*.py *.pyi` | `#\s*type:\s*ignore\[` | count |
| `bare type: ignore` | py | `#\s*type:\s*ignore(?!\[)` | forbid |
| `pyright: ignore` | py | `#\s*pyright:\s*ignore\[` | count |
| `bare pyright: ignore` | py | `#\s*pyright:\s*ignore(?!\[)` | forbid |
| `noqa` | py | `(?i)#\s*noqa:` | count |
| `blanket noqa` | py | `(?i)#\s*noqa(?!:)` | forbid |
| `ruff: noqa` | py | `#\s*(?:ruff\|flake8):\s*noqa:` | count |
| `blanket ruff: noqa` | py | `#\s*(?:ruff\|flake8):\s*noqa(?!:)` | forbid |
| `pragma: no cover` | py | `#\s*pragma:\s*no\s+cover` | count |
| `fmt: off` | py | `#\s*fmt:\s*off` | count |
| `fmt: skip` | py | `#\s*fmt:\s*skip` | count |
| `pytest.mark.skip` | py | `\bpytest\.mark\.skip(?:if)?\b` | count |
| `pytest.mark.xfail` | py | `\bpytest\.mark\.xfail\b` | count |
| `pytest.skip` | py | `\bpytest\.(?:skip\|xfail)\(` | count |
| `pytest.importorskip` | py | `\bpytest\.importorskip\(` | count |
| `eslint-disable` | JS | `C eslint-disable(?:-next-line\|-line)?[ \t]+[\w@]` | count |
| `bare eslint-disable` | JS | `C eslint-disable(?:-next-line\|-line)?(?![ \t]+[\w@])` | forbid |
| `oxlint-disable` / `bare oxlint-disable` | JS | as eslint | count / forbid |
| `biome-ignore` | JS, CSS | `C biome-ignore` | count |
| `@ts-ignore`, `@ts-expect-error`, `@ts-nocheck` | JS | `C @ts-ignore` etc. | count |
| `istanbul ignore`, `c8 ignore`, `v8 ignore` | JS | `C istanbul ignore` etc. | count |
| `.skip` | JS | `\b(?:it\|test\|describe\|suite)\.skip\b` | count |
| `.skipIf` | JS | `\b(?:it\|test\|describe\|suite)\.(?:skipIf\|runIf)\b` | count |
| `.todo` | JS | `\b(?:it\|test\|describe\|suite)\.todo\b` | count |
| `.only` | JS | `\b(?:it\|test\|describe\|suite)\.only\b` | forbid |
| `stylelint-disable` / `bare stylelint-disable` | CSS | as eslint | count / forbid |
| `shellcheck disable` | `*.sh *.bash` | `#\s*shellcheck\s+disable=` | count |
| `actionlint ignore` | `.github/actionlint.yaml .github/actionlint.yml` | `^\s*ignore:` | count |

JS globs: `*.js *.mjs *.cjs *.jsx *.ts *.mts *.cts *.tsx *.vue *.svelte`. CSS globs: `*.css *.scss *.less`. Write the `C` opener and each glob group once as module constants. `.skip` must not match `.skipIf`: `\b` after `skip` fails before `I`.

- [ ] **Step 1: Write the failing tests**

`tests/suppressions.test.sh` sources `tests/lib.sh`. Helper `repo` makes a fresh `git init` folder under `$tmp` and `cd`s into it. Helper `put <path> <line>` writes the file and runs `git add`. Helper `hook [args]` runs `python3 "$root/.github/scripts/suppressions.py" "$@"` and captures stdout+stderr in `$out` and the exit code in `$rc`.

Cases:
- `markers_all_sampled`: a bash table of `file<TAB>line<TAB>name` samples, one per marker name. The test asserts that `hook --markers` equals the sorted name set of the samples. For each sample, a fresh repo with only that line must print exactly one hit, `path:1: name`.
- `scoped_forms_not_forbidden`: `# noqa: E501`, `# type: ignore[x]`, `// eslint-disable-next-line no-console` each give a count hit and no `forbid` name.
- `reason_tail_is_bare`: `// eslint-disable-next-line -- why` and `/* eslint-disable */` give `bare eslint-disable`.
- `language_scoped`: `// eslint-disable` in `a.py` and `# noqa` in `a.js` give no hits.
- `string_without_opener`: `x = "type: ignore[x]"` gives no hit.
- `md_and_untracked_skipped`: `# noqa: E1` in `notes.md` and in an untracked `b.py` give no hits. `hook` exits 0.
- `two_on_one_line`: `x  # noqa: E1  # type: ignore[y]` gives 2 hits.
- `crlf_source`: a CRLF `a.py` line gives the same hit as LF.
- `bad_bytes_and_links`: a tracked `a.py` with the byte `\xff` plus `# noqa: E1`, and a tracked symlink (`git update-index --add --cacheinfo 120000,...`). `hook` gives 1 hit and does not crash.

Construct marker text from parts wherever the test file's own `shellcheck disable` row would count it (e.g. `sc="shell""check"`).

- [ ] **Step 2: Run, expect FAIL** — `bash tests/suppressions.test.sh`. Expected: every case FAIL (no script).

- [ ] **Step 3: Implement `MARKERS`, `scan`, `--markers`, and the no-baseline report in `.github/scripts/suppressions.py`**

- [ ] **Step 4: Run, expect PASS** — `bash tests/suppressions.test.sh` ends with `all passed`. `shellcheck -x -P SCRIPTDIR tests/suppressions.test.sh` is clean.

- [ ] **Step 5: Mutation check** — one at a time: drop a row from `MARKERS`; remove `(?!\[)` from `bare type: ignore`; change `.skip`'s `\b` to nothing. Each must turn a case red. Revert.

- [ ] **Step 6: Commit** — `feat(suppressions): marker table and per-file counts`

### Task 2: Baseline, ratchet, and `--update`

**Files:**
- Modify: `.github/scripts/suppressions.py`
- Modify: `tests/suppressions.test.sh`

**Interfaces:**
- Consumes: `scan` and `MARKERS` from Task 1.
- Produces: `load(text: str) -> tuple[dict[tuple[str, str], tuple[int, str]], list[str]]`, which returns the baseline and its error messages.
- Produces: `main` exit codes: 0 when nothing to report; 1 on any error or a stale count. With `--update`, a stale-only result returns 0.

Behaviour:
- `main` first changes to `git rev-parse --show-toplevel`.
- `load` skips empty lines and strips `\r`. It splits each line with `split("\t", 3)`. Errors: not 4 fields; count not an integer ≥ 1; empty reason (after strip); unknown marker name; a `forbid` marker name (`always fails`); a duplicate (path, marker). Each error message names the line number.
- Over: count > baseline (absent = 0) → `path: marker: N > baseline B`, then one `  path:line: marker` line per hit (Task 1 cases keep passing).
- Forbid hit → `path:line: name always fails`.
- Stale: count < baseline → set the baseline to the count, dropping lines at 0. Print `path: marker: B -> N`.
- On any stale entry, the script rewrites `.suppressions` sorted by (path, marker), LF, reasons kept verbatim. If no line is left, it removes the file. Over entries are never raised; the rewrite keeps their old baseline.
- `--update` does exactly what the check does. Only the stale-only exit code differs.

- [ ] **Step 1: Write the failing tests**

- `absent_zero`: no `.suppressions`, no markers → rc 0.
- `absent_one`: one `# noqa: E1` in `a.py`, no file → rc 1, output has `a.py: noqa: 1 > baseline 0`.
- `at_baseline`: `a.py<TAB>noqa<TAB>1<TAB>why` → rc 0, file unchanged.
- `above_baseline`: two hits, baseline 1 → rc 1, the file still says 1.
- `above_with_update`: same plus `--update` → rc 1, the file still says 1 (never raised).
- `below_rewrites`: one hit, baseline 3 → rc 1, output `a.py: noqa: 3 -> 1`, the file is `a.py<TAB>noqa<TAB>1<TAB>why`.
- `below_update_exit0`: same with `--update` → rc 0, the same file.
- `to_zero_removes_file`: baseline 1, no hit → rc 1, `.suppressions` is gone.
- `deleted_path_dropped`: baseline lines for `gone.py` and `a.py` (1 hit) → the rewrite keeps only `a.py`.
- `sorted_rewrite`: baseline lines in reverse order, one stale → the rewrite comes out sorted.
- `missing_reason`: `a.py<TAB>noqa<TAB>1<TAB>` → rc 1, `reason`. Also a 3-field line → rc 1.
- `bad_count_and_unknown`: count `0`, count `x`, marker `nope`, a duplicate line → each rc 1.
- `forbid_ignores_baseline`: a bare `# type: ignore` with the baseline line `a.py<TAB>bare type: ignore<TAB>1<TAB>x` → rc 1, `always fails`.
- `crlf_baseline`: a CRLF `.suppressions` with a trailing blank line, at baseline → rc 0.
- `tab_in_reason`: reason `a<TAB>b`, stale → the rewrite keeps `a<TAB>b`.
- `from_subdir`: run `hook` from `src/` with the baseline at root → rc 0, at baseline.

- [ ] **Step 2: Run, expect FAIL** — the new cases FAIL.
- [ ] **Step 3: Implement `load`, the compare, and the rewrite in `main`.**
- [ ] **Step 4: Run, expect PASS** — `all passed`, shellcheck clean.
- [ ] **Step 5: Mutation check** — one at a time: make stale return 0 without `--update`; let the rewrite raise an over count; skip the reason check; skip the chdir to the top level. Each must turn a case red. Revert.
- [ ] **Step 6: Commit** — `feat(suppressions): baseline file, ratchet rewrite, --update`

### Task 3: Part 3 cleanup and this repo's baseline

**Files:**
- Modify: `.github/workflows/self-test.yml:174` (the `fix-collect` assertion)
- Modify: `tests/fake-gh:14-15`, `tests/fix-args.test.sh:25-26`
- Create: `.suppressions`

**Interfaces:**
- Consumes: the script from Task 2 (run on this repo).

- [ ] **Step 1: Baseline red** — `python3 .github/scripts/suppressions.py` in the worktree. Expected rc 1, listing 3 `shellcheck disable` hits and 1 `actionlint ignore` hit.
- [ ] **Step 2: Replace the two SC2053 sites with `case`.** In `fake-gh`: `case $args in $glob) ;; *) continue ;; esac`. In `covers()`: `case $2 in $pat) return 0 ;; esac`. Delete both disable comments. Run `for t in tests/*.test.sh; do bash "$t" || exit 1; done` (all pass) and `shellcheck -x -P SCRIPTDIR .github/scripts/*.sh tests/*.sh tests/fake-gh` (clean).
- [ ] **Step 3: self-test.yml:174** — replace `test -z "$(grep -lx '# fail / fail (1)' log-*.txt || true)"` with `! grep -qx '# fail / fail (1)' log-*.txt`.
- [ ] **Step 4: Write `.suppressions`** with these 2 lines:
  - `.github/scripts/fix-paths.sh` / `shellcheck disable` / 1 / `SC2034: shellcheck checks the sourced file alone and cannot see the scripts that use CONFIG_PATHS; bash arrays cannot be exported`
  - `.github/actionlint.yaml` / `actionlint ignore` / 1 / `actionlint does not know job.workflow_sha; last checked against actionlint 1.7.12, retest on each bump`
  Run the script: rc 0.
- [ ] **Step 5: Commit** — `fix: case for glob matches, plain grep assertion, repo baseline`

### Task 4: Hook packaging, CI, README

**Files:**
- Create: `.pre-commit-hooks.yaml`, `pyproject.toml`
- Modify: `.github/workflows/self-test.yml` (`lint` job), `README.md`

**Interfaces:**
- Produces: hook id `suppressions`, console script `suppressions = "suppressions:main"`.

- [ ] **Step 1: `pyproject.toml`** — setuptools ≥ 61 build backend; `name = "phlares-suppressions"`, `version = "1.5.0"`, `requires-python = ">=3.10"`, no dependencies; `[tool.setuptools] py-modules = ["suppressions"]`, `package-dir = { "" = ".github/scripts" }`. `main` must accept no argv and read `sys.argv[1:]`, and the console script exits with its return code.
- [ ] **Step 2: `.pre-commit-hooks.yaml`** — `id: suppressions`, `name: suppression baseline`, `entry: suppressions`, `language: python`, `pass_filenames: false`, `always_run: true`, `require_serial: true`, plus a one-line description.
- [ ] **Step 3: Windows re-probe (gate)** — a consumer repo in the scratchpad with `repo: <worktree path>`, `rev: <HEAD>`. From PowerShell: `prek run --all-files` with one `# noqa: E1` in `a.py` → Failed with `a.py: noqa: 1 > baseline 0`. Then `prek install` and `git commit` → blocked. Remove the marker → both pass. Record the output in the PR body.
- [ ] **Step 4: `lint` job** — add `python3 .github/scripts/suppressions.py` (dogfood), and `pipx run ruff==0.17.1 check .github/scripts` plus `format --check`. Note beside the pin that Dependabot does not move it. Run both locally: clean.
- [ ] **Step 5: README** — a "Suppression guard" section: what it counts (point to the table in the script), the `.suppressions` line format, the ratchet rewrite, `--update`, the always-fail forms, the not-scanned files, and the caller snippet (`repo: https://github.com/Phlares/workflows`, `rev: <full sha>  # frozen: v1.5.0`, `hooks: - id: suppressions`).
- [ ] **Step 6: Commit** — `feat(suppressions): prek hook packaging, self-test lint, README`

### Task 5: Review, PR, release

- [ ] `/simplify` (one combined pass), then `/code-review high`, inline. Fix the findings, run the full test loop and shellcheck again.
- [ ] Open the PR. First line: the change. Body: `Closes` is wrong here (#28 stays open for wave 2), so write `Part of #28`. Add the gate output and the test count.
- [ ] Self-test green → merge (owner).
- [ ] Tag: `git tag -a v1.5.0 -m "v1.5.0: suppression guard prek hook (.suppressions baseline, ratchet rewrite); Part 3 shell fixes"` on the merge commit, then push it.
- [ ] Comment on #28 with the tag, the hook `rev` (full sha), and the caller snippet.
