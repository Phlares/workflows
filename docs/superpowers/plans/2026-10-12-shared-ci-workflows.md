# Shared CI workflows v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `Phlares/workflows` with one reusable `check.yml`, prove it with a self-test, and move flashback-sampler, VoxGarbler and portfolio onto it with no loss of test coverage.

**Architecture:** One `workflow_call` workflow takes value inputs (toolchain versions, runner, folder, install, run, env, shards, timeout) and runs one matrix job. On failure it writes a summary, an annotation and a `report.json` artifact. Callers keep triggers, path filters and `ci-pass`; they replace only their check jobs with a `uses:` line pinned to a commit hash.

**Tech Stack:** GitHub Actions (reusable workflows), bash, jq, actionlint 1.7.12, Node 24 `node:test`, Python 3.12 + pytest, Zig 0.16.0.

**Spec:** `C:\Users\Ryon\Documents\dev\workflows\docs\specs\2026-10-12-shared-ci-workflows-design.md`

## Global Constraints

- Repo `Phlares/workflows` is **public**. Checks only: no release, publish or deploy jobs.
- One reusable workflow, `.github/workflows/check.yml`. No `tier` input, no on/off flags, no composite actions, no `secrets: inherit`.
- Every third-party action is pinned to a full commit hash with a `# vX.Y.Z` comment. Pins (resolved 2026-10-12):
  - `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1`
  - `actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v7.1.0`
  - `actions/setup-python@5fda3b95a4ea91299a34e894583c3862153e4b97 # v7.0.0`
  - `mlugg/setup-zig@d1434d08867e3ee9daa34448df10607b98908d29 # v2.2.1`
  - `actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2`
  - `actions/download-artifact@9000827ccba6bdab643e8b6fd33ac0654aef8333 # v8.0.2`
  - actionlint download script at commit `914e7df21a07ef503a81201c76d2b11c789d3fca` (v1.7.12)
- `check.yml` permissions: `contents: read` only. No concurrency group inside it.
- Callers pin `Phlares/workflows/.github/workflows/check.yml@<full sha> # v1.0.0`.
- Every CI repo gets Dependabot for `github-actions`, grouped, monthly, minor+patch group (portfolio's existing file is the model).
- Text rules (owner's global CLAUDE.md): plain short sentences; **no AI attribution anywhere** — no `Co-Authored-By: Claude`, no `Claude-Session:`, no "Generated with Claude Code", no mention of Claude/agents/reviewers in commits, PRs or issues. Git identity stays the owner's.
- Deletion policy: never `rm -r`/`rm -rf`/`git clean`; move candidates to `_ToRemove/` and ask once at the end.
- Session deny rules block `gh api */protection*`, `*/rulesets*`, `gh repo edit`, `gh pr merge --admin`. Branch protection and required-check renames are owner steps.
- The owner merges every PR. Portfolio merges via Trunk (`/trunk merge` comment).

## Review Focus

1. **Failure report on Windows** — `jq`, `$RUNNER_TEMP` (a `D:\a\_temp` path in Git Bash) and artifact upload must work on `windows-latest`; flashback's pytest job runs there. Pinned by the `fail-win` self-test case (Task 2).
2. **Failure before `run` starts** — a failed `npm ci` or toolchain setup must still produce a report with `step` = `install` or `setup`, not a crash of the report step. Pinned by the `fail-install` self-test case (Task 2).
3. **Inputs containing quotes, `$` or newlines** — `run` and `install` reach bash through `env:`, never through `${{ }}` inside the script, so a caller's `"not audio_hw and not perf"` survives intact and no expression injection is possible. Pinned by the py-zig case, whose `run` uses double quotes and `$FIXTURE_ENV` (Task 2).
4. **Portfolio test count drops silently** (wrong shard math, a skipped install) — the equivalence table is a merge blocker (Task 6).
5. **Required-check rename missed on flashback-sampler** — every PR to `dev`/`main` would block. The PR description carries the owner step at the top (Task 4).

---

## File map

`Phlares/workflows` (local clone `C:\Users\Ryon\Documents\dev\workflows`):

| File | Responsibility |
|---|---|
| `.github/workflows/check.yml` | The reusable check job and failure report |
| `.github/workflows/self-test.yml` | Calls `check.yml` on fixtures; `verify` gate; actionlint |
| `.github/dependabot.yml` | Monthly grouped action bumps for this repo |
| `fixtures/js/` | 2 `node:test` files, proves shards |
| `fixtures/js-sub/app/` | proves `working-directory` |
| `fixtures/py-zig/` | proves python + zig + `env` on Windows |
| `fixtures/fail/` | always-failing test; proves the report on Linux and Windows |
| `fixtures/fail-install/` | broken `install`; proves the report when `run` never starts |
| `README.md` | Inputs, one caller example per language, versioning |
| `docs/specs/…`, `docs/superpowers/plans/…` | Spec and this plan |

Caller files: `flashback-sampler/.github/workflows/test.yml`, `VoxCollage/.github/workflows/game-ci.yml`, `portfolio/.github/workflows/ci.yml`, plus a new `.github/dependabot.yml` in flashback-sampler and VoxGarbler.

---

### Task 1: Create the repo and push the spec

**Files:**
- Create: `C:\Users\Ryon\Documents\dev\workflows\.gitignore`
- Existing: `docs/specs/2026-10-12-shared-ci-workflows-design.md`, `docs/superpowers/plans/2026-10-12-shared-ci-workflows.md`

**Interfaces:**
- Produces: GitHub repo `Phlares/workflows` (public, default branch `main`) with the spec and plan on `main`.

- [ ] **Step 1: Ask the owner to approve creating the public repo.** Creating a public repo publishes content. Wait for a yes in chat.

- [ ] **Step 2: Init and first commit**

```bash
cd /c/Users/Ryon/Documents/dev/workflows
printf '_ToRemove/\nnode_modules/\n__pycache__/\n.pytest_cache/\nzig-out/\n.zig-cache/\n' > .gitignore
git init -b main
git add .gitignore docs
git commit -m "docs: shared CI workflows v1 spec and plan"
```

- [ ] **Step 3: Create the GitHub repo and push**

```bash
gh repo create Phlares/workflows --public --source . --push \
  --description "Reusable GitHub Actions check workflow for Phlares repos"
gh repo view Phlares/workflows --json visibility,defaultBranchRef -q '.visibility+" "+.defaultBranchRef.name'
```
Expected: `PUBLIC main`

- [ ] **Step 4: Owner step.** Ask the owner to set branch protection on `main` in the web UI after Task 2 merges (`verify` required, strict off, no force push, no deletion). Note it in the Task 2 PR body.

---

### Task 2: Fixtures and self-test (red), then `check.yml` (green)

**Files:**
- Create: `fixtures/js/package.json`, `fixtures/js/package-lock.json`, `fixtures/js/test/a.test.js`, `fixtures/js/test/b.test.js`
- Create: `fixtures/js-sub/app/package.json`, `fixtures/js-sub/app/package-lock.json`, `fixtures/js-sub/app/test/sub.test.js`
- Create: `fixtures/py-zig/requirements.txt`, `fixtures/py-zig/hello.zig`, `fixtures/py-zig/test_fixture.py`
- Create: `fixtures/fail/package.json`, `fixtures/fail/package-lock.json`, `fixtures/fail/test/fail.test.js`
- Create: `fixtures/fail-install/package.json`, `fixtures/fail-install/package-lock.json` (out of sync on purpose)
- Create: `.github/workflows/self-test.yml`, `.github/workflows/check.yml`, `.github/dependabot.yml`

**Interfaces:**
- Produces: `check.yml` inputs exactly as the spec table: `name`, `runs-on`, `node-version`, `python-version`, `zig-version`, `working-directory`, `install`, `run`, `env`, `shards`, `timeout-minutes`. Env vars `SHARD_INDEX`, `SHARD_TOTAL` in `install` and `run`. Artifact `ci-failure-<name>-<shard>` with `report.json` (schema 1). Job display name `<name> (<shard>)`.

- [ ] **Step 1: Branch**

```bash
cd /c/Users/Ryon/Documents/dev/workflows && git switch -c feat/check-v1
```

- [ ] **Step 2: JS fixtures.** Each `package.json` / `package-lock.json` pair below, with `<NAME>` replaced by the folder's name (`fixture-js`, `fixture-js-sub`, `fixture-fail`):

`package.json`:
```json
{ "name": "<NAME>", "version": "1.0.0", "private": true, "type": "module", "scripts": { "test": "node --test" } }
```
`package-lock.json`:
```json
{ "name": "<NAME>", "version": "1.0.0", "lockfileVersion": 3, "requires": true, "packages": { "": { "name": "<NAME>", "version": "1.0.0" } } }
```

`fixtures/js/test/a.test.js`:
```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
test('shard file a', () => assert.equal(1 + 1, 2));
```
`fixtures/js/test/b.test.js`:
```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
test('shard file b', () => assert.equal(2 * 2, 4));
```
`fixtures/js-sub/app/test/sub.test.js`:
```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
test('runs inside the working directory', () => assert.ok(process.cwd().replaceAll('\\', '/').endsWith('fixtures/js-sub/app')));
```
`fixtures/fail/test/fail.test.js`:
```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
test('always fails', () => assert.fail('expected failure from fixture'));
```
`fixtures/fail-install/package.json` declares a dependency its lock file lacks, so `npm ci` fails with "package.json and package-lock.json ... are in sync". A missing lock file would not work: setup-node's cache step would fail first and the report would say `setup`.
```json
{ "name": "fixture-fail-install", "version": "1.0.0", "private": true, "dependencies": { "left-pad": "1.3.0" } }
```
`fixtures/fail-install/package-lock.json`:
```json
{ "name": "fixture-fail-install", "version": "1.0.0", "lockfileVersion": 3, "requires": true, "packages": { "": { "name": "fixture-fail-install", "version": "1.0.0" } } }
```
`node --test` with no file arguments runs every `*.test.js` under the current folder.

- [ ] **Step 3: Python + Zig fixture**

`fixtures/py-zig/requirements.txt`:
```
pytest>=8
```
`fixtures/py-zig/hello.zig`:
```zig
const std = @import("std");
pub fn main() void {
    std.debug.print("hello from zig\n", .{});
}
```
`fixtures/py-zig/test_fixture.py`:
```python
import os
import pathlib

def test_env_input_reaches_tests():
    assert os.environ["FIXTURE_ENV"] == "ok"

def test_zig_step_ran_before_pytest():
    assert pathlib.Path("zig-out/hello.exe").is_file()
```

- [ ] **Step 4: `self-test.yml`**

```yaml
name: self-test

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: self-test-${{ github.ref }}
  cancel-in-progress: true

jobs:
  js:
    uses: ./.github/workflows/check.yml
    with:
      name: js
      node-version: "24"
      working-directory: fixtures/js
      install: npm ci
      run: |
        test "$SHARD_TOTAL" = 2
        node --test --test-shard="$SHARD_INDEX/$SHARD_TOTAL"
      shards: "[1,2]"

  js-sub:
    uses: ./.github/workflows/check.yml
    with:
      name: js-sub
      node-version: "24"
      working-directory: fixtures/js-sub/app
      install: npm ci
      run: npm test

  py-zig:
    uses: ./.github/workflows/check.yml
    with:
      name: py-zig
      runs-on: windows-latest
      python-version: "3.12"
      zig-version: 0.16.0
      working-directory: fixtures/py-zig
      env: FIXTURE_ENV=ok
      install: pip install -r requirements.txt
      run: |
        test "$FIXTURE_ENV" = "ok"
        mkdir -p zig-out
        zig build-exe hello.zig -femit-bin=zig-out/hello.exe
        pytest -q -m "not slow and not audio_hw"

  fail:
    uses: ./.github/workflows/check.yml
    with:
      name: fail
      node-version: "24"
      working-directory: fixtures/fail
      install: npm ci
      run: npm test

  fail-win:
    uses: ./.github/workflows/check.yml
    with:
      name: fail-win
      runs-on: windows-latest
      node-version: "24"
      working-directory: fixtures/fail
      install: npm ci
      run: npm test

  fail-install:
    uses: ./.github/workflows/check.yml
    with:
      name: fail-install
      node-version: "24"
      working-directory: fixtures/fail-install
      install: npm ci
      run: echo "never reached"

  lint:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - run: |
          bash <(curl -sSfL https://raw.githubusercontent.com/rhysd/actionlint/914e7df21a07ef503a81201c76d2b11c789d3fca/scripts/download-actionlint.bash) 1.7.12
          ./actionlint -color

  # GitHub cannot mark a reusable-workflow job "expected to fail", so this job
  # checks that the fail cases failed and that their reports are well formed.
  # It is the one required check on main.
  verify:
    if: always()
    needs: [js, js-sub, py-zig, fail, fail-win, fail-install, lint]
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - env:
          NEEDS: ${{ toJSON(needs) }}
        run: |
          jq -e '
            .js.result == "success" and ."js-sub".result == "success" and
            ."py-zig".result == "success" and .lint.result == "success" and
            .fail.result == "failure" and ."fail-win".result == "failure" and
            ."fail-install".result == "failure"' <<<"$NEEDS"
      - uses: actions/download-artifact@9000827ccba6bdab643e8b6fd33ac0654aef8333 # v8.0.2
        with:
          pattern: ci-failure-*
          path: reports
      - run: |
          check() { # $1 artifact job name, $2 expected step, $3 text expected in tail
            jq -e --arg job "$1" --arg step "$2" --arg text "$3" '
              .schema == 1 and .job == $job and .shard == 1 and .shard_total == 1 and
              .step == $step and (.run_url | startswith("https://github.com/")) and
              (.sha | length == 40) and (.tail | any(contains($text)))' "reports/ci-failure-$1-1/report.json"
          }
          check fail run "expected failure from fixture"
          check fail-win run "expected failure from fixture"
          check fail-install install "npm ci"
          test "$(ls reports | wc -l)" = 3
```

Note: the `-m "not slow and not audio_hw"` marker expression exists only to exercise Review Focus item 3 (double quotes inside `run`); pytest accepts unknown marker names in `-m`.

- [ ] **Step 5: `dependabot.yml`**

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: monthly
    groups:
      actions:
        patterns: ["*"]
        update-types: ["minor", "patch"]
```

- [ ] **Step 6: Confirm red.** Commit and open a PR without `check.yml`.

```bash
git add fixtures .github/workflows/self-test.yml .github/dependabot.yml
git commit -m "test: self-test fixtures for check.yml"
git push -u origin feat/check-v1
gh pr create --fill --base main
```
Expected: the CI-watch hook wakes the session with **FAILED** (`check.yml` not found / workflow invalid). If GitHub rejects the workflow file outright, the run shows "workflow file issue": that also counts as red.

- [ ] **Step 7: `check.yml`**

```yaml
name: check

# Reusable check job. Callers decide what runs and when; this file decides
# how: toolchains, install, shards, time limit, failure report. Inputs reach
# bash through env:, never through ${{ }} inside a script, so caller text
# with quotes or $ cannot inject expressions.
on:
  workflow_call:
    inputs:
      name: { type: string, default: check }
      runs-on: { type: string, default: ubuntu-latest }
      node-version: { type: string, default: "" }
      python-version: { type: string, default: "" }
      zig-version: { type: string, default: "" }
      working-directory: { type: string, default: "." }
      install: { type: string, default: "" }
      run: { type: string, required: true }
      env: { type: string, default: "" }
      shards: { type: string, default: "[1]" }
      timeout-minutes: { type: number, default: 15 }

permissions:
  contents: read

jobs:
  check:
    name: ${{ inputs.name }} (${{ matrix.shard }})
    runs-on: ${{ inputs.runs-on }}
    timeout-minutes: ${{ inputs.timeout-minutes }}
    strategy:
      fail-fast: false
      matrix:
        shard: ${{ fromJSON(inputs.shards) }}
    defaults:
      run:
        shell: bash
    env:
      SHARD_INDEX: ${{ matrix.shard }}
      SHARD_TOTAL: ${{ strategy.job-total }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - if: inputs.node-version != ''
        uses: actions/setup-node@949feb2413d6458794dcd2491c4babbbce0c15c1 # v7.1.0
        with:
          node-version: ${{ inputs.node-version }}
          cache: npm
          cache-dependency-path: ${{ inputs.working-directory }}/package-lock.json
      - if: inputs.python-version != ''
        uses: actions/setup-python@5fda3b95a4ea91299a34e894583c3862153e4b97 # v7.0.0
        with:
          python-version: ${{ inputs.python-version }}
          cache: pip
          cache-dependency-path: |
            ${{ inputs.working-directory }}/pyproject.toml
            ${{ inputs.working-directory }}/requirements*.txt
      - if: inputs.zig-version != ''
        uses: mlugg/setup-zig@d1434d08867e3ee9daa34448df10607b98908d29 # v2.2.1
        with:
          version: ${{ inputs.zig-version }}
      - name: env
        if: inputs.env != ''
        env:
          INPUT_ENV: ${{ inputs.env }}
        run: printf '%s\n' "$INPUT_ENV" >> "$GITHUB_ENV"
      - name: install
        if: inputs.install != ''
        working-directory: ${{ inputs.working-directory }}
        env:
          INPUT_INSTALL: ${{ inputs.install }}
        run: |
          echo install > "$RUNNER_TEMP/step"
          bash -eo pipefail -c "$INPUT_INSTALL" 2>&1 | tee -a "$RUNNER_TEMP/run.log"
      - name: run
        working-directory: ${{ inputs.working-directory }}
        env:
          INPUT_RUN: ${{ inputs.run }}
        run: |
          echo run > "$RUNNER_TEMP/step"
          bash -eo pipefail -c "$INPUT_RUN" 2>&1 | tee -a "$RUNNER_TEMP/run.log"
      # report.json schema 1 is read by the local CI-watch hook and the
      # automated fix loop; change fields only with a schema bump.
      - name: failure report
        if: failure()
        env:
          NAME: ${{ inputs.name }}
          PR: ${{ github.event.pull_request.number }}
          SHA: ${{ github.event.pull_request.head.sha || github.sha }}
          RUN_URL: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}
        run: |
          cd "$RUNNER_TEMP"
          touch run.log
          step=$(cat step 2>/dev/null || echo setup)
          tail -n 40 run.log > tail.txt
          last=$(grep -v '^[[:space:]]*$' tail.txt | tail -n 1)
          last=${last//'%'/'%25'}
          {
            echo "### $NAME failed (shard $SHARD_INDEX/$SHARD_TOTAL, step: $step)"
            echo '```'; cat tail.txt; echo '```'
            echo "[Run log]($RUN_URL)"
          } >> "$GITHUB_STEP_SUMMARY"
          echo "::error title=$NAME (shard $SHARD_INDEX/$SHARD_TOTAL)::${last:-step $step failed}"
          mkdir -p report
          jq -n --arg repo "$GITHUB_REPOSITORY" --arg pr "$PR" --arg sha "$SHA" --arg url "$RUN_URL" \
            --arg job "$NAME" --argjson shard "$SHARD_INDEX" --argjson total "$SHARD_TOTAL" \
            --arg step "$step" --rawfile tail tail.txt \
            '{schema: 1, repo: $repo, pr: (if $pr == "" then null else ($pr | tonumber) end),
              sha: $sha, run_url: $url, job: $job, shard: $shard, shard_total: $total,
              step: $step, tail: ($tail | split("\n") | map(sub("\r$"; "")) | map(select(. != "")))}' \
            > report/report.json
      - if: failure()
        uses: actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9 # v7.0.2
        with:
          name: ci-failure-${{ inputs.name }}-${{ matrix.shard }}
          path: ${{ runner.temp }}/report/report.json
          if-no-files-found: ignore
```

- [ ] **Step 8: Lint locally**

```bash
cd /c/Users/Ryon/Documents/dev/workflows
mkdir -p "$TMP/actionlint" && cd "$TMP/actionlint" && bash <(curl -sSfL https://raw.githubusercontent.com/rhysd/actionlint/914e7df21a07ef503a81201c76d2b11c789d3fca/scripts/download-actionlint.bash) 1.7.12 && cd - && "$TMP/actionlint/actionlint" -color
```
Expected: no output, exit 0. Fix anything it reports.

- [ ] **Step 9: Push and confirm green**

```bash
git add .github/workflows/check.yml
git commit -m "feat: reusable check workflow with failure report"
git push
```
Expected: the hook wakes the session with **all checks passed**. `verify` green means: 3 good cases passed, 3 fail cases failed, 3 reports well formed, actionlint clean. If `verify` fails, read its log, fix `check.yml` (not the assertions), push again.

- [ ] **Step 10: Mutation check.** Delete the `failure report` step in its own commit, push, and wait for the hook: `verify` must be red. Then undo it:

```bash
git commit -am "test: mutation, drop failure report (reverted next)" && git push
# after the hook reports FAILED on verify:
git revert --no-edit HEAD && git push
```
Expected after the revert: green again. Record "mutation: report step removed → verify red" in the PR body. The owner squash-merges, so the scratch commits do not reach `main`.

- [ ] **Step 11: Review gate before merge.** This is the highest blast-radius point: once `v1.0.0` is tagged and pinned by three repos, a bug costs a `v1.0.1` and three re-pin PRs. Run `/simplify` (one combined pass), then `/code-review high` on the branch diff, both inline with a single reviewer (owner's CLAUDE.md: never the multi-agent workflow review). Fix findings, push, wait for the hook to report green. Record the findings and their outcomes in the PR body.

- [ ] **Step 12: Owner merges; owner sets branch protection on `main` (Task 1 Step 4).**

---

### Task 3: README and tag v1.0.0

**Files:**
- Create: `README.md`

**Interfaces:**
- Produces: tag `v1.0.0` on `main`; its commit hash is `V1_SHA` for Tasks 4–6.

- [ ] **Step 1: Write `README.md`**

````markdown
# workflows

One reusable GitHub Actions job for checks: lint, typecheck, tests. Release,
publish and deploy jobs stay in each repo.

## Use

```yaml
jobs:
  test:
    uses: Phlares/workflows/.github/workflows/check.yml@<full sha> # v1.0.0
    with:
      node-version: "24"
      install: npm ci
      run: npm test
```

Pin the full commit hash with the tag as a comment. Dependabot
(`github-actions` ecosystem) opens the bump PR when a new tag ships.

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `name` | `check` | Job name; prefix of the failure artifact |
| `runs-on` | `ubuntu-latest` | Runner label |
| `node-version` | empty | Empty = not installed. npm cache keys on `<working-directory>/package-lock.json` |
| `python-version` | empty | Empty = not installed. pip cache keys on `pyproject.toml`, `requirements*.txt` |
| `zig-version` | empty | Empty = not installed |
| `working-directory` | `.` | Where `install` and `run` execute |
| `install` | empty | Commands run before `run` |
| `run` | required | Commands; stops at the first failure |
| `env` | empty | `KEY=VALUE` lines set for `install` and `run` |
| `shards` | `[1]` | JSON array; each shard gets `SHARD_INDEX` and `SHARD_TOTAL` |
| `timeout-minutes` | `15` | Per shard |

## Examples

Sharded JS:
```yaml
    with:
      node-version: "24"
      install: npm ci
      run: npm run test:ci -- --shard=$SHARD_INDEX/$SHARD_TOTAL
      shards: "[1,2,3]"
```

Python with a Zig build step on Windows:
```yaml
    with:
      runs-on: windows-latest
      python-version: "3.12"
      zig-version: 0.16.0
      env: |
        PYTHONUTF8=1
      install: pip install -e ".[dev]"
      run: |
        (cd core && zig build -Doptimize=ReleaseSafe)
        pytest tests/unit
```

Zig only:
```yaml
    with:
      zig-version: 0.16.0
      working-directory: core
      run: |
        zig fmt --check build.zig src
        zig build test
```

## On failure

The job writes a summary, one `::error` annotation, and an artifact
`ci-failure-<name>-<shard>` holding `report.json` (schema 1): repo, PR number,
commit, run URL, job, shard, failing step (`setup`, `install` or `run`) and the
last 40 log lines.

## Versioning

Semver tags. A breaking input change bumps the major version. Each release
note lists input changes.
````

- [ ] **Step 2: Commit, PR, merge, tag**

```bash
cd /c/Users/Ryon/Documents/dev/workflows && git switch main && git pull && git switch -c docs/readme
git add README.md && git commit -m "docs: README with inputs and caller examples" && git push -u origin docs/readme
gh pr create --fill --base main
```
After the owner merges:
```bash
git switch main && git pull
git tag v1.0.0 && git push origin v1.0.0
gh release create v1.0.0 --title v1.0.0 --notes "First release. Inputs: name, runs-on, node-version, python-version, zig-version, working-directory, install, run, env, shards, timeout-minutes. Failure report schema 1."
git rev-parse 'v1.0.0^{commit}'
```
Record the printed hash as `V1_SHA`.

---

> **Session split point.** Tasks 4–6 need only `V1_SHA` from Tasks 1–3. If this session is long by now, record `V1_SHA` in memory and start a fresh session at Task 4.

### Task 4: flashback-sampler caller

**Files:**
- Modify: `flashback-sampler/.github/workflows/test.yml` (both jobs)
- Create: `flashback-sampler/.github/dependabot.yml`

**Interfaces:**
- Consumes: `V1_SHA`, `check.yml` inputs.

Default branch is `dev`; PRs target `dev`. Work in a worktree so the owner's checkout is untouched.

- [ ] **Step 1: Worktree**

```bash
cd /c/Users/Ryon/Documents/dev/flashback-sampler && git fetch origin
git worktree add ../flashback-wt/ci-shared -b ci/shared-workflows origin/dev
cd ../flashback-wt/ci-shared
```

- [ ] **Step 2: Replace the `jobs:` block of `test.yml`** (keep `name`, `on`, `concurrency`; update the header comment's job description to say the jobs call `Phlares/workflows`):

```yaml
permissions:
  contents: read

jobs:
  pytest:
    uses: Phlares/workflows/.github/workflows/check.yml@V1_SHA # v1.0.0
    with:
      name: pytest
      runs-on: windows-latest
      python-version: "3.12"
      zig-version: 0.16.0
      timeout-minutes: 6
      # tests/conftest.py exits the session when the native library is
      # missing. FLASHBACK_REQUIRE_NATIVE is kept so a revert of that gate
      # does not silently lose the CI check.
      env: |
        QT_QPA_PLATFORM=offscreen
        PYTHONUTF8=1
        FLASHBACK_REQUIRE_NATIVE=1
      install: pip install -e ".[dev]"
      run: |
        (cd core && zig build -Doptimize=ReleaseSafe)
        pytest tests/unit -m "not audio_hw and not perf"

  zig:
    uses: Phlares/workflows/.github/workflows/check.yml@V1_SHA # v1.0.0
    with:
      name: zig
      zig-version: 0.16.0
      working-directory: core
      timeout-minutes: 3
      run: |
        zig fmt --check build.zig src
        zig build test
```
Replace `V1_SHA` with the hash from Task 3 (both lines).

- [ ] **Step 3: `.github/dependabot.yml`** — same content as `Phlares/workflows/.github/dependabot.yml` (Task 2 Step 5), with `target-branch: dev` added under the entry (Dependabot otherwise targets the default branch, which is `dev` already; add it anyway so a default-branch change does not redirect bumps silently).

- [ ] **Step 4: Baseline counts.** Before pushing, record the last `dev` run's pytest pass count:

```bash
run=$(gh run list -R Phlares/flashback-sampler --workflow test.yml --branch dev --status success -L 1 --json databaseId -q '.[0].databaseId')
gh run view "$run" -R Phlares/flashback-sampler --log | grep -E "passed|failed" | tail -3
```

- [ ] **Step 5: Commit, push, PR**

```bash
git add .github && git commit -m "ci: run checks through Phlares/workflows check.yml"
git push -u origin ci/shared-workflows
gh pr create --base dev --title "ci: run checks through Phlares/workflows" --body "$(cat <<'EOF'
**Owner step at merge:** branch protection on `dev` and `main` requires `pytest (windows / py3.12)` and `zig (ubuntu)`. The new check names are `pytest / pytest (1)` and `zig / zig (1)`. Rename the required checks in the web UI when this merges, or every PR blocks.

- `pytest` and `zig` jobs now call `Phlares/workflows/.github/workflows/check.yml` pinned to v1.0.0.
- Same commands, runners, toolchains, env and time limits as before.
- Adds Dependabot for GitHub Actions (monthly, grouped).
- pytest count: baseline <N passed> on dev, this PR <N passed>.
EOF
)"
```
Fill the two counts from Step 4 and from this PR's run log before the owner reviews.

- [ ] **Step 6: Verify.** The hook wakes the session. Both jobs green and the pytest pass count equals the baseline. A different count is a blocker: find why before asking for merge. Then run `/code-review low` on the diff, inline.

- [ ] **Step 7: Owner merges and renames the required checks.**

---

### Task 5: VoxGarbler caller

**Files:**
- Modify: `VoxCollage/.github/workflows/game-ci.yml` (`jobs:` block)
- Create: `VoxCollage/.github/dependabot.yml`

**Interfaces:**
- Consumes: `V1_SHA`.

The owner's checkout of `VoxCollage` sits on a feature branch; never switch it. Use a worktree from the default branch.

- [ ] **Step 1: Worktree**

```bash
cd /c/Users/Ryon/Documents/dev/VoxCollage && git fetch origin
base=$(gh repo view Phlares/VoxGarbler --json defaultBranchRef -q .defaultBranchRef.name)
git worktree add ../VoxCollage-wt/ci-shared -b ci/shared-workflows "origin/$base"
cd ../VoxCollage-wt/ci-shared
```

- [ ] **Step 2: Replace the `jobs:` block of `game-ci.yml`** (keep `name`, `on` with its path filters, `permissions`):

```yaml
jobs:
  build-test:
    uses: Phlares/workflows/.github/workflows/check.yml@V1_SHA # v1.0.0
    with:
      name: game
      # vite 8 / vitest 4 require Node 20.19+ or 22.12+.
      node-version: "22"
      working-directory: game
      install: npm ci
      run: |
        npx tsc --noEmit
        npm test
        npm run build
```
Replace `V1_SHA`.

- [ ] **Step 3: `.github/dependabot.yml`** — same content as Task 2 Step 5.

- [ ] **Step 4: Commit, push, PR** (base = the default branch from Step 1)

```bash
git add .github && git commit -m "ci: run game checks through Phlares/workflows check.yml"
git push -u origin ci/shared-workflows
gh pr create --base "$base" --title "ci: run game checks through Phlares/workflows" --body "$(cat <<'EOF'
- `game-ci` now calls `Phlares/workflows/.github/workflows/check.yml` pinned to v1.0.0.
- Same Node version, folder and commands (tsc, tests, build). Path filters unchanged.
- Adds Dependabot for GitHub Actions (monthly, grouped).
EOF
)"
```
The PR touches `.github/workflows/game-ci.yml`, which is in the path filter, so the workflow runs.

- [ ] **Step 5: Verify** green via the hook; compare the vitest `Tests` line with the last `game-ci` run on the default branch (same method as Task 4 Step 4). Equal counts required. Then run `/code-review low` on the diff, inline.

- [ ] **Step 6: Owner merges.**

---

### Task 6: portfolio caller with equivalence check

**Files:**
- Modify: `portfolio/.github/workflows/ci.yml` (`unit` job only)

**Interfaces:**
- Consumes: `V1_SHA`. `ci-pass` keeps `needs: [changes, unit, sim, deploy-smoke]`; the job id `unit` must not change.

- [ ] **Step 1: Worktree**

```bash
cd /c/Users/Ryon/Documents/dev/portfolio && git fetch origin
git worktree add ../portfolio-wt/shared-check -b ci/shared-check origin/main
cd ../portfolio-wt/shared-check
```

- [ ] **Step 2: Baseline from #634**

```bash
for id in $(gh pr view 634 -R Phlares/portfolio --json statusCheckRollup \
    -q '.statusCheckRollup[] | select(.name | startswith("unit")) | .detailsUrl' | grep -oE '[0-9]+$'); do
  echo "== job $id"
  gh api "repos/Phlares/portfolio/actions/jobs/$id/logs" | sed 's/\x1b\[[0-9;]*m//g' | grep -E "Test Files|Tests  |Duration"
done | tee "$TMP/unit-baseline.txt"
```
Expected: three blocks, each with a `Test Files` and a `Tests` line.

- [ ] **Step 3: Replace the `unit` job** (keep its comment block above it; drop the heap comment's step-level placement and move it above `env:`):

```yaml
  unit:
    needs: changes
    if: github.event_name != 'push' && needs.changes.outputs.code == 'true'
    uses: Phlares/workflows/.github/workflows/check.yml@V1_SHA # v1.0.0
    with:
      name: unit
      node-version: "24"
      timeout-minutes: 15
      shards: "[1,2,3]"
      # Heap ceiling for the test forks: the heavy jsdom plane-animation
      # files peak above 3 GB (measured locally 2026-08-29, ~3070 MB at the
      # crash), so each fork gets 4 GB. NODE_OPTIONS also applies to the
      # parent vitest process: four 4 GB ceilings on a private-repo runner
      # with about 7 GB. The ceiling stops one runaway fork; it does not
      # reserve memory, and no shard has run out so far.
      env: NODE_OPTIONS=--max-old-space-size=4096
      install: npm ci
      run: npm run test:ci -- --shard=$SHARD_INDEX/$SHARD_TOTAL
```
Replace `V1_SHA`. Portfolio's `dependabot.yml` already covers `github-actions`; no change.

- [ ] **Step 4: Lint locally** with the actionlint binary from Task 2 Step 8: `"$TMP/actionlint/actionlint" .github/workflows/ci.yml`. Expected: no output.

- [ ] **Step 5: Commit, push, PR**

```bash
git add .github/workflows/ci.yml && git commit -m "ci: run unit shards through Phlares/workflows check.yml"
git push -u origin ci/shared-check
gh pr create --base main --title "ci: run unit shards through Phlares/workflows" --body "Equivalence table follows once CI finishes."
```

- [ ] **Step 6: Candidate counts.** After the hook reports green:

```bash
for id in $(gh pr view --json statusCheckRollup \
    -q '.statusCheckRollup[] | select(.name | startswith("unit")) | .detailsUrl' | grep -oE '[0-9]+$'); do
  echo "== job $id"
  gh api "repos/Phlares/portfolio/actions/jobs/$id/logs" | sed 's/\x1b\[[0-9;]*m//g' | grep -E "Test Files|Tests  |Duration"
done | tee "$TMP/unit-candidate.txt"
```

- [ ] **Step 7: Equivalence table in the PR body.** Columns: shard, test files (baseline / candidate), tests passed, skipped, wall time. Rule: files, passed and skipped must match per shard (the size sequencer assigns files deterministically). Wall time is reported only (about ±3 min runner noise). Any count mismatch blocks the merge: investigate before asking.

```bash
gh pr edit --body "$(cat <<'EOF'
- `unit` now calls `Phlares/workflows/.github/workflows/check.yml` pinned to v1.0.0: same Node 24, 3 shards, 4 GB heap, 15 min cap, same `test:ci` command.
- `ci-pass`, `changes`, `sim`, `deploy-smoke` unchanged; branch protection still requires only `ci-pass`.

| Shard | Test files (634 / this) | Passed | Skipped | Wall time |
|---|---|---|---|---|
| 1 | … | … | … | … |
| 2 | … | … | … | … |
| 3 | … | … | … | … |
EOF
)"
```
Replace each `…` with the numbers from Steps 2 and 6 before saving; the table must contain no `…`.

- [ ] **Step 8: Review.** Run `/code-review low` on the diff, inline.

- [ ] **Step 9: Owner merges via `/trunk merge`.** After merge, confirm the push-to-main run is green (smoke only) and Vercel's `ci-pass` deployment check still passes.

---

### Task 7: Close-out

- [ ] **Step 1: Worktree cleanup list.** Merged worktrees: `flashback-wt/ci-shared`, `VoxCollage-wt/ci-shared`, `portfolio-wt/shared-check`. Do not remove them; list them for the owner (deletion policy) with `git worktree remove` commands.
- [ ] **Step 2: Memory.** Update `project_portfolio_ci_cost.md` (or a new `project_shared_ci_workflows.md` linked from it): v1 shipped, `V1_SHA`, merged PR numbers, traps found. Add a pointer line to `MEMORY.md`.
- [ ] **Step 3: Next items for the owner** (from the spec's follow-ups): copier template; Part 2 lint measurement; Part 3b with #617; PokePlanner and vps-ai-manager adoption.
