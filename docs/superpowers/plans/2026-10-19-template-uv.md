# Copier template and uv.lock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `check.yml` v1.6.0 with a `uv-version` input, move VoxGarbler to `uv.lock`, then ship a copier template (v1.7.0) for prototype and product tiers and regenerate claude-fix-sandbox from it.

**Architecture:** One reusable `check.yml` gains a toolchain input. The template lives in `template/` with `copier.yml` at the repo root; its tier is one ordered answer that gates files and values. `tests/template.test.sh` generates every tier and language set into a temp dir and runs the generated checks.

**Tech Stack:** GitHub Actions, copier 9.19.1, uv 0.13.1, prek, ruff, oxlint, pyright, bash tests (`tests/lib.sh`).

**Spec:** `docs/specs/2026-10-19-template-uv-design.md`

## Global Constraints

- Pins (hash + `# frozen:` or `# vX` comment):
  - `astral-sh/setup-uv@1c37ad07a6a961277cf70c0d37d6f313000f5884 # v10.3.0`
  - uv `0.13.1`
  - copier `9.19.1` (`_min_copier_version: "9.19"`)
  - `pre-commit/pre-commit-hooks` rev `3e8a8703264a2f4a69428a0aa4dcb512790b2c8c  # frozen: v6.0.0`
  - `astral-sh/ruff-pre-commit` rev `38bfb07c0c64c304f47eb52090f8288150c77730  # frozen: v0.17.1`
  - `oxc-project/mirrors-oxlint` rev `5b56cf853a2b0e1e276773824e00111e6312cb09  # frozen: v1.88.0`
- Self-pins in generated files: `{{ _copier_conf.vcs_ref_hash }}` with comment `{{ _copier_conf.vcs_ref }}` (C2), for both `check.yml@` and the suppression hook `rev`.
- ruff:
  - prototype: `extend-select = ["RUF100", "PGH004"]`
  - product: `select = ["E", "F", "W", "I", "B", "UP", "RUF100", "PGH004"]`, `ignore = ["E501"]`
- pyright (product, python): standard mode, `enableTypeIgnoreComments = false`, `reportUnnecessaryTypeIgnoreComment = "error"`, `pythonVersion` = `python_version`, `pythonPlatform` = `Linux` or `Windows` from `target_os`.
- oxlint args:
  - prototype: `[--report-unused-disable-directives-severity=error]`
  - product: `[--deny-warnings, --report-unused-disable-directives-severity=error]`
- Install lines (U2):
  - lint: `uv sync --locked --only-group lint`
  - test and typecheck: `uv sync --locked --group <job>`
  - run: `uv run --no-sync <tool>`
- Workflow name `CI`. `permissions: contents: read`. Concurrency cancel. No path filter.
- Dependabot groups per ecosystem: `<eco>` (minor, patch), `<eco>-major` (major), `<eco>-security` (`applies-to: security-updates`). The pre-commit ecosystem keeps one `hooks` group. The uv ecosystem uses `versioning-strategy: lockfile-only`.
- Public text carries no AI attribution. Tracked-file removals happen only where the spec names them (VoxGarbler requirements files).
- Windows worktrees check out CRLF. Shell tests that shellcheck reads need LF copies locally. Pass `encoding="utf-8"` to Python `open()`.

## Review Focus

1. **The tier answer is changed during `copier update`.** Prototype → product must add the product files and values, not leave the prototype ones. Test in Task 7.
2. **A new repo already has a `pyproject.toml`.** Copier must keep it unchanged, and the post-copy message must list the groups to add. Test in Task 6.
3. **Python + Node together.** Both the ruff and oxlint hooks run, and both test jobs exist with distinct `name:` inputs (artifact names must not collide). Test in Task 5.
4. **A stale `uv.lock` in a generated repo.** The CI install step fails. Task 1 checks this report shape through `fail-uv-drift`.
5. **A Windows `target_os`.** `pythonPlatform` must be `Windows` and the test job must run on `windows-latest`. The lint and typecheck jobs stay on Ubuntu. Test in Task 5.

---

## Part A: check.yml v1.6.0 (branch `feat/uv`, this repo)

### Task 1: `uv-version` input

**Files:**
- Modify: `.github/actions/setup/action.yml`, `.github/workflows/check.yml` (inputs and setup call), `.github/workflows/self-test.yml`, `README.md` (inputs table and a uv example)
- Create: `fixtures/py-uv/pyproject.toml`, `fixtures/py-uv/uv.lock`, `fixtures/py-uv/test_uv.py`, `fixtures/fail-uv-drift/pyproject.toml`, `fixtures/fail-uv-drift/uv.lock`

**Interfaces:**
- Produces: the `check.yml` input `uv-version: { type: string, default: "" }`, passed to setup as `uv-version`. Setup step: `if: inputs.uv-version != ''`, uses the setup-uv pin with `version`, `enable-cache: true` and `cache-dependency-glob: <working-directory>/uv.lock`.

- [ ] **Step 1: Write the failing jobs.**
  - `py-uv`: `python-version: "3.12"`, `uv-version: 0.13.1`, `working-directory: fixtures/py-uv`, `install: uv sync --locked --only-group test`, `run: uv run --no-sync pytest -q`.
  - `fail-uv-drift`: same inputs on `fixtures/fail-uv-drift`. Its `pyproject.toml` lists one more group dependency than its lock.
  - Add both to `verify`: `py-uv` must succeed, `fail-uv-drift` must fail. Report check: `check fail-uv-drift install "needs to be updated"`.
  - Fixture locks come from `uv lock` with uv 0.13.1. For drift, lock first, then add `"iniconfig"` to the group.
- [ ] **Step 2: Run actionlint locally** (download per the memory trap into the scratchpad). Expected: FAIL, because `uv-version` is not a defined input of `check.yml`.
- [ ] **Step 3: Implement the input** in `check.yml` and `action.yml`. Add the README row: `uv-version` | empty | Empty = not installed. Cache keyed on `<working-directory>/uv.lock`.
- [ ] **Step 4: Verify.** actionlint passes locally. Push the branch and open the PR. Expected: `verify` green, `py-uv` success, `fail-uv-drift` failure at step `install`.
- [ ] **Step 5: Bump** `pyproject.toml` `version = "1.6.0"`. Commit `feat(check): uv-version input`.

### Task 2: review, merge, tag v1.6.0

- [ ] Run `/code-review medium`, inline, over `main..feat/uv`, and fix the findings. Skip `/simplify` unless the diff got messy (small change).
- [ ] The owner merges. Then tag `v1.6.0` on the merge commit, push the tag, and record the hash in memory and in a comment on #32.

## Part B: VoxGarbler to uv.lock (repo VoxGarbler, branch `ci/uv-lock`, worktree `VoxCollage-wt/uv-lock`)

Starts when VoxGarbler #91 is merged and v1.6.0 is tagged.

### Task 3: groups, lock, CI lines

**Files:**
- Modify: `pyproject.toml` (add `[dependency-groups]`), `.github/workflows/lint.yml`, `.github/workflows/py-ci.yml`, `.github/dependabot.yml` (uv comment only)
- Create: `uv.lock`
- Remove (`git rm`, approved in the spec): `requirements-ci.in`, `requirements-ci.txt`, `requirements-lint.in`, `requirements-lint.txt`

**Interfaces:**
- Groups:
  - `lint = ["prek"]`
  - `ci` = the 18 entries of today's `requirements-ci.in`, caps kept verbatim
- Jobs:
  - `lint`: `install: uv sync --locked --only-group lint`; `run: uv run --no-sync prek run --all-files --show-diff-on-failure`
  - `pytest` and `typecheck`: `install: uv sync --locked --only-group ci` then `uv pip install --no-deps -e .`; `run: uv run --no-sync pytest -q` / `uv run --no-sync pyright`
  - Every job sets `uv-version: 0.13.1` and pins `check.yml` to v1.6.0.
- `py-ci` paths: replace `requirements-ci.txt` with `uv.lock`.

- [ ] **Step 1: Baseline.** Record the pytest pass/skip counts and the pyright error count from the last green `py-ci` run on master.
- [ ] **Step 2: Lock.** Edit `pyproject.toml`, run `uv lock`, then `uv sync --locked --only-group ci` and `uv pip install --no-deps -e .` into a fresh `.venv`. Run `uv run --no-sync pytest -q` and `uv run --no-sync pyright`. Expected: counts equal the baseline (CI skips the GameAssets tests; compare with the CI counts, not with local runs).
- [ ] **Step 3: Version check.** Diff the top-level versions in `uv.lock` against `requirements-ci.txt`. Expected: same versions, or newer within the caps. List any change in the PR body.
- [ ] **Step 4: Edit the workflows, remove the four files, and push.** Expected: `lint`, `pytest` and `typecheck` green.
- [ ] **Step 5: Mutation check on the branch.** Change every hash of one package in `uv.lock` and push. Expected: `pytest` red at `install` with a hash mismatch. Revert with a new commit, not a force push.
- [ ] **Step 6: Review and merge.** Run `/code-review low`, inline (config only). The owner merges. Comment on #32 with the result. Comment on #14 to say the uv half is answered. The security-update criterion waits for the next real alert; note that on #32.

## Part C: template v1.7.0 (branch `feat/template`, this repo)

### Task 4: copier questions and the file set

**Files:**
- Create: `copier.yml`, `template/{{_copier_conf.answers_file}}.jinja`, `tests/template.test.sh`
- Create (empty shells, filled in Tasks 5-6): every file in the spec's "Generated files" table, under `template/` with `.jinja` names and conditional names

**Interfaces:**
- `copier.yml`: `_subdirectory: template`, `_min_copier_version: "9.19"`, `_skip_if_exists: [pyproject.toml, .gitignore]`, `_message_after_copy` (run `uv lock`; repo settings from C13; when `pyproject.toml` existed, the groups to add).
- Questions:
  - `tier` (choices `prototype`, `product`)
  - `languages` (multiselect `python`, `node`; validator: at least one)
  - `default_branch` (`main`)
  - `target_os` (`ubuntu-latest`, `windows-latest`; `when: tier == 'product'`)
  - `python_version` (`"3.12"`)
  - `node_version` (`"24"`; `when: 'node' in languages`)
- Test helpers in `tests/template.test.sh`: `gen <dir> <tier> <langs>` runs `uvx copier@9.19.1 copy --vcs-ref HEAD --defaults -d tier=… -d languages=… "$root" <dir>`. `files <dir>` prints the sorted `git ls-files --others` list after `git init`.

- [ ] **Step 1: Write the failing test.** For each of the 6 combinations, assert `files` equals the expected list from the spec table. Example, prototype + node: `.copier-answers.yml .github/dependabot.yml .github/workflows/ci.yml .gitignore .pre-commit-config.yaml pyproject.toml`.
- [ ] **Step 2: Run it.** `bash tests/template.test.sh`. Expected: FAIL, because `copier.yml` is missing.
- [ ] **Step 3: Write `copier.yml` and the conditional file names.**
- [ ] **Step 4: Run it.** Expected: the file-set checks pass.
- [ ] **Step 5: Commit.** `feat(template): copier questions and file set`

### Task 5: `ci.yml` and `dependabot.yml`

**Files:** `template/.github/workflows/ci.yml.jinja`, `template/.github/dependabot.yml.jinja`; test additions.

**Interfaces:**
- Jobs and their `name:` inputs:
  - `lint` (name `lint`)
  - `test-py` (name `pytest`; product + python; `runs-on: target_os`)
  - `typecheck` (name `typecheck`; product + python; Ubuntu)
  - `test-js` (name `test`; product + node; `runs-on: target_os`; `install: npm ci`, `run: npm test`)
- Every job: `check.yml@{{ _copier_conf.vcs_ref_hash }} # {{ _copier_conf.vcs_ref }}`, `python-version` and `uv-version` set where uv runs, `timeout-minutes: 5`.
- `on`: `pull_request` and `push: branches: [<default_branch>]`.

- [ ] **Step 1: Write the failing tests.**
  - `ci.yml` contains `check.yml@$(git -C "$root" rev-parse HEAD)`.
  - The job set per combination matches the Interfaces list above.
  - With `target_os=windows-latest`, `test-py` runs on Windows and `typecheck` on `ubuntu-latest` (Review Focus 5).
  - Python + node gives distinct `name:` values (Review Focus 3).
  - actionlint passes on each `ci.yml`.
  - `uvx check-jsonschema@0.38.2 --builtin-schema vendor.dependabot` passes on each `dependabot.yml`.
  - Ecosystems: always `github-actions`, `pre-commit`, `uv`; `npm` only with node. Each has the three groups from the Global Constraints.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Write the two templates.**
- [ ] **Step 4: Run them.** Expected: PASS.
- [ ] **Step 5: Commit.** `feat(template): caller workflow and dependabot`

### Task 6: hooks, rule configs, pyproject

**Files:** `template/.pre-commit-config.yaml.jinja`, `template/ruff.toml.jinja`, `template/pyrightconfig.json.jinja`, `template/pyproject.toml.jinja`, `template/.gitignore`; seeds in `tests/template-seed/` (`seed.py`, `seed.js`, `tests/test_seed.py`).

**Interfaces:**
- Hook order: `check-merge-conflict`, ruff-check (`--fix`) + ruff-format (`types_or: [python, pyi, jupyter]`), oxlint, `suppressions` (repo `https://github.com/Phlares/workflows`).
- `pyproject.toml`:
  - `[project]` with `name` = destination folder name, `version = "0.0.0"`, `requires-python = ">={{ python_version }}"`
  - no `[build-system]`, so uv does not build the project (same effect as `package = false`)
  - `[dependency-groups]`: `lint = ["prek"]`; product + python adds `test = ["pytest"]` and `typecheck = ["pyright"]`

- [ ] **Step 1: Write the failing tests.** For each combination:
  - Copy the seeds that match the languages.
  - Rewrite the suppression hook `repo:` to `$root` (the local repo holds the unpushed HEAD).
  - Run `uv lock`, `uv sync --locked --only-group lint` and `uv run --no-sync prek run --all-files`. Expected: exit 0.
  - Mutations, each one alone, then revert:
    - `# noqa: E501` on a clean line of `seed.py` → prek fails.
    - `// oxlint-disable-next-line no-debugger` on a clean line of `seed.js` → prek fails.
    - Product + python: `uv sync --locked --group typecheck`, then `uv run --no-sync pyright` passes. Add `x = 1  # pyright: ignore[reportGeneralTypeIssues]` → pyright fails.
    - Product + python: `uv sync --locked --group test` and `uv run --no-sync pytest` pass.
  - Value asserts: the ruff and pyright values from the Global Constraints; the oxlint args by tier.
  - Review Focus 2: put a `pyproject.toml` in the target dir before `copy`. It is byte-identical after the copy, and copier's output contains `[dependency-groups]`.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Write the templates.**
- [ ] **Step 4: Run them.** Expected: PASS.
- [ ] **Step 5: Commit.** `feat(template): hooks, rule configs, pyproject`

### Task 7: update flow

**Files:** `tests/template.test.sh` (update section).

- [ ] **Step 1: Write the failing tests.**
  - In a temp clone of `$root`, tag the commit before Task 6 as `v0.0.1-test` and HEAD as `v0.0.2-test`.
  - Generate at `v0.0.1-test` with `--vcs-ref`. `git init` and commit it.
  - Change the oxlint `rev` line as Dependabot would, and commit.
  - Run `copier update --defaults --vcs-ref v0.0.2-test`. Expected: the hand-changed rev survives, or the file holds conflict markers and `prek run check-merge-conflict --all-files` fails. Assert one of the two. Never both clean and reverted.
  - Review Focus 1: update with `-d tier=product` from a prototype copy. Expected: the product values and files are present after the update.
- [ ] **Step 2: Run them.** Expected: FAIL until the test helper supports `--vcs-ref` from a clone.
- [ ] **Step 3: Implement the helper changes. No template changes are expected; if one is needed, it is a finding, so note it.**
- [ ] **Step 4: Run them.** Expected: PASS.
- [ ] **Step 5: Commit.** `test(template): copier update keeps pin edits`

### Task 8: self-test job, README, release v1.7.0

**Files:** `.github/workflows/self-test.yml` (job `template`), `README.md` (section "Template": `uvx copier@9.19.1 copy gh:Phlares/workflows <dir>`; tiers table; update flow C3), `pyproject.toml` version `1.7.0`.

- [ ] **Step 1: Add job `template`.**
  - Runs on Ubuntu with `timeout-minutes: 10`.
  - Installs uv through the setup-uv pin and actionlint as the `lint` job does.
  - Runs `bash tests/template.test.sh`.
  - Add `template` to the `verify` needs: it must succeed.
  - `fix-unit` runs `tests/*.test.sh`, which also matches `template.test.sh`. Exclude it there, because `fix-unit` has no uv.
- [ ] **Step 2: Push and open the PR.** Expected: `verify` green.
- [ ] **Step 3: Review.** Run `/simplify`, one combined pass, then `/code-review medium`, inline, over `main..feat/template`. Fix the findings.
- [ ] **Step 4: Release.** The owner merges. Tag `v1.7.0`. Comment on #13 with the copy command and the tag hash.

## Part D: live adopter

### Task 9: regenerate claude-fix-sandbox

- [ ] **Step 1: Generate.** Clone the sandbox to `Documents/dev/claude-fix-sandbox`. Make branch `ci/template`. Run `uvx copier@9.19.1 copy --vcs-ref v1.7.0 --overwrite -d tier=product -d languages=[node] -d target_os=ubuntu-latest gh:Phlares/workflows .`, then `uv lock`.
- [ ] **Step 2: Check the diff.**
  - `ci.yml` and `dependabot.yml` are replaced.
  - `pyproject.toml`, `uv.lock`, `.pre-commit-config.yaml`, `.copier-answers.yml` and `.gitignore` (if absent) are added.
  - `package.json`, `src/`, `test/` and `claude-fix.yml` are unchanged.
  - `claude-fix.yml` triggers on `workflows: [CI]`, which matches the generated name.
- [ ] **Step 3: Push the PR.** Expected: `lint` and `test` green. Mutation: add an `oxlint-disable-next-line` on a clean line → `lint` red. Revert with a new commit.
- [ ] **Step 4: Review and merge.** Run `/code-review low` (generated config). The owner merges. Comment on #13: the live adopter is done. The live `copier update` proof runs at the next tag; put that on #13 as an open criterion.
- [ ] **Step 5: Close out.** Tick the #29 criterion "#13 template carries the groups" and the #28 criterion "#13 template writes the Part 2 settings". Close #13 when Task 9 merges. #32 stays open for flashback and portfolio. Move the worktrees to `_ToRemove/` and list them for approval at the end.
