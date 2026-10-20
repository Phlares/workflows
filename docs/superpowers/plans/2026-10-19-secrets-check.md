# Secrets Check Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generated repos block hardcoded secrets on commit and in CI with gitleaks, the guard counts or forbids gitleaks suppressions, and the lint job caches the prek store.

**Architecture:** Three guard rows in `suppressions.py`. One `prek-cache` input threaded `check.yml` → `setup` action → `actions/cache`. One gitleaks hook block (commit entry + manual-stage history entry) in the template, run in CI by `--hook-stage manual`.

**Tech Stack:** bash tests (`tests/lib.sh` `check`), Python 3.12 guard, GitHub Actions composite action, copier 9.19.1, prek 0.5.5, gitleaks v8.30.1.

**Spec:** `docs/specs/2026-10-19-secrets-check-design.md`

## Global Constraints

- gitleaks pin: `rev: 83d9cd684c87d95d656c1458ef04895a7f1cbd8e  # frozen: v8.30.1`.
- actions/cache pin: `actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6.1.0`.
- Cache key: `prek-v1-<runner.os>-<runner.arch>-<python-version>-<hashFiles(<wd>/.pre-commit-config.yaml, <wd>/uv.lock)>`. No `restore-keys`.
- Store path: `${{ runner.temp }}/prek`, set as `PREK_HOME` (refines the spec's `~/.cache/prek`: an expression path needs no shell and is the same form on Linux and Windows; Task 4 updates S7).
- No literal secret in any file of this repo. Seeded keys are built at test run time.
- Text in this repo that names the allow marker builds it from parts (code) or gets a `.suppressions` line with reason `names the marker in docs` (docs).
- Commit messages: plain, no attribution trailers. Never commit to `main`; work on `feat/secrets-check`.

## Review Focus

1. A seed repo with zero commits: `gitleaks git` in the history entry must not error. Task 3 commits the seeds, and Task 3 step 1 asserts the lint job command passes on them.
2. `.suppressions` lines name the `gitleaks allow` marker; they must not count as hits. Task 1 test "baseline lines do not count as gitleaks allow".
3. A `.gitleaksignore` holding only comments and blank lines passes. Task 1 test.
4. The guard source and its test hold the marker only as joined parts. Task 1 step 5 runs the guard on this repo.
5. A job without `prek-cache` gets no `PREK_HOME` and no cache step. Task 2 asserts `PREK_HOME` is empty in an existing self-test job.

---

### Task 1: Guard rows for gitleaks

**Files:**
- Modify: `.github/scripts/suppressions.py` (`MARKERS`, module constants)
- Modify: `tests/suppressions.test.sh` (samples table, new checks)
- Modify: `.suppressions` (doc lines, step 5)

**Interfaces:**
- Produces: marker names `gitleaks allow` (COUNT), `.gitleaksignore entry` (FORBID), `.gitleaks.toml entry` (FORBID), printed by `--markers`.

- [ ] **Step 1: Write the failing tests**

In `tests/suppressions.test.sh`, next to `sc=`, add `ga="gitleaks"":allow"`. Add to `samples`:

```
.env.example	c	gitleaks allow	TOKEN=abc  # $ga
.gitleaksignore	f	.gitleaksignore entry	abc123:a.py:generic-api-key:1
.gitleaks.toml	f	.gitleaks.toml entry	[extend]
```

Add checks:

```bash
repo; printf '%s\n' '# why' '' > .gitleaksignore; printf '%s\n' '# note' > .gitleaks.toml; git add -A; hook
check "comment and blank lines in gitleaks files pass" test "$rc" -eq 0 -a "$(nhits)" -eq 0

repo; put notes.md "see $ga here"; hook
check "gitleaks allow counts in markdown" test "$(hits)" = "notes.md:1: gitleaks allow"

repo; put a.env "K=v  # $ga"; base "a.env${T}gitleaks allow${T}1${T}why"; git add .suppressions; hook
check "baseline lines do not count as gitleaks allow" test "$rc" -eq 0 || echo "     $out"
```

Rename the existing check "markdown and untracked files are not scanned" to "markdown has no noqa row; untracked files are not scanned" (its assertions stay).

- [ ] **Step 2: Run to verify failure**

Run: `bash tests/suppressions.test.sh`
Expected: FAIL on `--markers lists exactly the sampled names` and the three new sample lines.

- [ ] **Step 3: Implement the rows in `suppressions.py`**

- `ALL = ("*",)` and `GITLEAKS = "gitleaks"` with a comment like `PYTEST`'s (joined at use so the guard does not count itself).
- Rows: `("gitleaks allow", ALL, GITLEAKS + ":allow", COUNT)`, `(".gitleaksignore entry", (".gitleaksignore",), r"^[ \t]*[^\s#]", FORBID)`, `(".gitleaks.toml entry", (".gitleaks.toml",), r"^[ \t]*[^\s#]", FORBID)`.
- Comment on the allow row: gitleaks honours the marker anywhere on a line, so the row needs no opener.
- Update the module docstring only if it now says something false (it claims regexes require an opener: add "except gitleaks allow").

- [ ] **Step 4: Run to verify pass**

Run: `bash tests/suppressions.test.sh`
Expected: `all passed`.

- [ ] **Step 5: Run the guard on this repo and baseline doc mentions**

Run: `python3 .github/scripts/suppressions.py`
Expected first: failures only for docs that name the marker (spec, this plan). Add one `.suppressions` line per file with its count and reason `names the marker in docs`. Rerun; expected exit 0. Repeat after Task 4's README edit.

- [ ] **Step 6: Commit**

```bash
git add .github/scripts/suppressions.py tests/suppressions.test.sh .suppressions
git commit -m "feat(guard): count gitleaks allow, forbid .gitleaksignore and .gitleaks.toml entries (#34)"
```

### Task 2: `prek-cache` input

**Files:**
- Modify: `.github/actions/setup/action.yml`
- Modify: `.github/workflows/check.yml` (input + pass-through)
- Create: `fixtures/prek/.pre-commit-config.yaml`, `fixtures/prek/pyproject.toml`, `fixtures/prek/uv.lock`
- Modify: `.github/workflows/self-test.yml` (new job `prek-cache`, assertion in `py-uv`)

**Interfaces:**
- Produces: `check.yml` input `prek-cache: { type: boolean, default: false }`; setup input `prek-cache` (string `"true"`/`"false"`); env `PREK_HOME=${{ runner.temp }}/prek` in the job when true.

- [ ] **Step 1: Write the failing CI test**

Fixture: `pyproject.toml` with `[dependency-groups] lint = ["prek==0.5.5"]` and no `[build-system]` (as the template writes it); `uv lock` creates `uv.lock`. `.pre-commit-config.yaml` holds the gitleaks block from Task 3 (both entries).

self-test job:

```yaml
  prek-cache:
    uses: ./.github/workflows/check.yml
    with:
      name: prek-cache
      python-version: "3.12"
      uv-version: 0.13.1
      prek-cache: true
      working-directory: fixtures/prek
      install: uv sync --locked --only-group lint
      run: |
        test "$PREK_HOME" = "$RUNNER_TEMP/prek"
        uv run --no-sync prek run --all-files --hook-stage manual
        test -n "$(find "$PREK_HOME" -name gitleaks -type f)"
```

In `py-uv`'s `run`, add first: `test -z "${PREK_HOME:-}"`.

- [ ] **Step 2: Verify it fails**

Run: `actionlint .github/workflows/self-test.yml .github/workflows/check.yml`
Expected: error that `prek-cache` is not an input of `check.yml`.

- [ ] **Step 3: Implement**

- `check.yml`: add the input; pass `prek-cache: ${{ inputs.prek-cache }}` to the setup step.
- `setup/action.yml`: input `prek-cache` (description: cache the prek store; for jobs that run prek; default `"false"`). Two steps, both `if: inputs.prek-cache == 'true'`: write `PREK_HOME=${{ runner.temp }}/prek` to `$GITHUB_ENV`; then `actions/cache` (pin above) with `path: ${{ runner.temp }}/prek` and the key above, built with `hashFiles(format('{0}/.pre-commit-config.yaml', inputs.working-directory), format('{0}/uv.lock', inputs.working-directory))`.
- One comment at the cache step: why no `restore-keys` (a near match would be saved again under the new key with stale envs).

- [ ] **Step 4: Verify**

Run: `actionlint .github/workflows/*.yml` and `bash tests/check-report.test.sh` (no regressions).
Expected: clean, `all passed`. The CI half is verified on the PR (Task 5).

- [ ] **Step 5: Commit**

```bash
git add .github/actions/setup/action.yml .github/workflows/check.yml .github/workflows/self-test.yml fixtures/prek
git commit -m "feat(check): prek-cache input caches the prek store (#34)"
```

### Task 3: Template gitleaks hook and lint run

**Files:**
- Modify: `template/.pre-commit-config.yaml.jinja` (block from spec "Template changes", after `check-merge-conflict`)
- Modify: `template/.github/workflows/ci.yml.jinja` (`lint`: `prek-cache: true`, new `run`)
- Modify: `tests/template.test.sh`

**Interfaces:**
- Consumes: Task 2's `prek-cache` input name.
- Produces: lint `run` = `uv run --no-sync prek run --all-files --hook-stage manual --show-diff-on-failure`.

- [ ] **Step 1: Write the failing tests**

In `tests/template.test.sh`:

- `seed()`: after `git add -A`, commit with hooks off: `git -c core.hooksPath=/dev/null -c user.name=t -c user.email=t@t commit -qm seed`.
- `lint()` with no hook id runs the generated job: `$(yq ci job lint install) && git add -A && $(yq ci job lint run)` (ci = that dir's `ci.yml`). With a hook id it stays as now.
- `key()` prints `token = "ghp_` plus 36 characters from a fixed mixed pattern (letters and digits, built by `printf`/repetition, never a literal 36-char string in the file).
- Per combo checks:
  - Hook order strings gain `id: gitleaks id: gitleaks ` after `id: check-merge-conflict `.
  - `"$d ci lint run"`: `yq ci job lint run` equals the run line above.
  - `"$d ci lint prek-cache"`: `yq ci job lint prek-cache` equals `true` (extend `tests/yamlq.py` only if it cannot read a boolean).
  - `"$d staged key fails gitleaks"`: `mutate "$d" gitleaks .gitignore "$(key)"`.
  - `"$d committed key fails the lint job"`: write `$(key)` to `leak.txt`, commit with hooks off, assert `fails lint "$d"`, then `git reset -q --hard HEAD~1`.

- [ ] **Step 2: Verify failure**

Run: `bash tests/template.test.sh` (needs network; `timeout: 600000`)
Expected: FAIL on hook order, lint run, prek-cache, and both key checks; `lint passes on seeds` still passes.

- [ ] **Step 3: Implement the two template edits** as in the spec, with its comment text.

- [ ] **Step 4: Verify pass**

Run: `ACTIONLINT=<path> bash tests/template.test.sh`
Expected: `all passed`.

- [ ] **Step 5: Commit**

```bash
git add template tests/template.test.sh tests/yamlq.py
git commit -m "feat(template): gitleaks hook on commit and in the lint job (#34)"
```

### Task 4: Docs and version

**Files:**
- Modify: `README.md` (Inputs: `prek-cache`; Suppression guard: three rows, all-files scope replaces "Not scanned: `*.md`"; Template: gitleaks hook, manual-stage lint run)
- Modify: `docs/specs/2026-10-19-secrets-check-design.md` (S7 path → `${{ runner.temp }}/prek`)
- Modify: `pyproject.toml` (`version = "1.8.0"`)
- Modify: `.suppressions` (README line if it names the marker)

- [ ] **Step 1:** Edit the three files. Plain, laconic text.
- [ ] **Step 2:** Run `python3 .github/scripts/suppressions.py` → exit 0 (add the README line first if needed).
- [ ] **Step 3: Commit**

```bash
git add README.md docs/specs/2026-10-19-secrets-check-design.md pyproject.toml .suppressions
git commit -m "docs: gitleaks, prek-cache, v1.8.0 (#34)"
```

### Task 5: Review, PR, warm-cache check, release

- [ ] **Step 1:** Run all local tests: `for t in tests/*.test.sh; do bash "$t" || break; done`. Expected: each prints `all passed`.
- [ ] **Step 2:** `/simplify` (one combined pass) then `/code-review medium`, inline. Fix findings; rerun Step 1.
- [ ] **Step 3:** Push `feat/secrets-check`, open a PR: first line states the change; `Closes #34`; bullets; no attribution lines.
- [ ] **Step 4:** All self-test jobs green. Rerun the `prek-cache` job; its log shows `Cache restored from key: prek-v1-…` and no Go build (prek's install line for gitleaks absent). Paste both run times into the PR.
- [ ] **Step 5:** After merge: tag `v1.8.0` on the merge commit, release note lists the new `prek-cache` input and the template hook.
