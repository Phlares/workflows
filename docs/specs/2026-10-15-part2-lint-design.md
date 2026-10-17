# Part 2: lint and VoxGarbler Python CI — design

Date: 2026-10-15. Status: draft for review.
Builds on: `2026-10-12-shared-ci-workflows-design.md` (v1, decisions D1-D9).
Research: `Documents/dev/reports/Shared CI standard for solo developers.md` (layers and tiers), `Portfolio CI history audit.md` (escape audit), `Fuzz and mutation testing CI.md` (tier table).

## Goal

Every CI repo lints each commit on the developer's machine and again in CI, with one config file as the single source of truth. VoxGarbler gets Python CI. Success means:

- portfolio, VoxGarbler and flashback-sampler each have one `.pre-commit-config.yaml`, a commit hook installed from it, and a `lint` CI job that runs the same file.
- Each repo has zero findings at merge of its fix PR, and `lint` blocks merge from then on.
- VoxGarbler runs its Python tests on every PR that touches Python.
- `check.yml` stays at v1.0.0. Part 2 adds no inputs.

## Why lint, and what it does not buy

- Lint is the cheapest CI layer: seconds per run, and every tier runs it (standard report, section 5).
- The portfolio escape audit found no past bug that lint or typecheck would have caught. For portfolio, lint buys consistent style and tidier agent-written code, not bug prevention.
- In the Python repos, lint finds latent defects: an `is` comparison with a literal (F632), shadowed imports (F811), and unused results.

## Decisions

| # | Decision | Why |
|---|---|---|
| L1 | One `.pre-commit-config.yaml` per repo drives the commit hook and the CI `lint` job | One file holds every tool version. The same check runs in both places. |
| L2 | Runner: **prek** (Rust rewrite of pre-commit, MIT) locally and in CI. The config uses only upstream pre-commit YAML keys. | prek adds 0.6 s per commit against 1.2 s for pre-commit (measured, Windows). Upstream keys keep pre-commit a one-word fallback. |
| L3 | JS and TS: **oxlint** with `--deny-warnings` | 0.3-0.4 s per repo, no config needed, official pre-commit mirror. oxlint exits 0 on warnings without the flag. |
| L4 | Python: **ruff** rule families E, F, W, I, B, UP (E501 off) plus `ruff format` | The formatter clears most E7xx findings. E501 (line length) overlaps the formatter. |
| L5 | Zig: no new linter. `zig fmt` moves from the `zig` CI job into the hook config. | The compiler already rejects unused names. One place for the format check. |
| L6 | Hooks fix locally and fail in CI on any change: `ruff check --fix`, `ruff format`, `zig fmt` | A blocked commit usually needs only a re-stage. CI fails when a hook modifies a file. |
| L7 | Fix all existing findings in one PR per repo. No baseline file. | Counts are small after autofix. oxlint has no baseline mode. Baselines rot. |
| L8 | `lint` blocks merge from the merge of each repo's fix PR | Zero findings from that point, so the gate costs nothing to hold. |
| L9 | Dependabot adds the `pre-commit` ecosystem (supported since 2026-03-10), grouped, monthly | Hook versions move the same way action pins do (D7). |
| L10 | Hook budget: under 1 s per tool on a typical commit. Typecheck and tests never go in the hook. | A commit hook runs on every agent commit. |
| L11 | Hook configs ship by hand. The copier template follows Part 2. | Same reason as D8: write the template from working callers. |
| L12 | Typecheck stays out of Part 2 | pyright basic mode finds 404 errors in flashback and 191 in VoxGarbler. Fixing them is its own project. |
| L13 | The 7 deferred v1.1 minors stay out of Part 2 | Part 2 needs no `check.yml` change: `pipx` ships on the runner image, so the lint job sets no toolchain input except Zig. |

All tools are MIT-licensed open source. All work in private repos: callers reach the public `check.yml` (D1), hook repos are public and fetched over HTTPS, and Dependabot's `pre-commit` ecosystem works in private repos. Part 2 does not use pre-commit.ci.

## Tiers

A tier is a set of rule values chosen in each repo's config. The shared workflow has no tier input (D4).

| Tier | Use for | Python | JS/TS | Typecheck |
|---|---|---|---|---|
| Prototype | Greybox, spikes, throwaway | ruff default rules + `ruff format` | oxlint default | none |
| Product | Live sites, personal tools, released apps | E, F, W, I, B, UP (E501 off) + `ruff format` | oxlint + `--deny-warnings` | CI only (follow-up) |
| Infra / science / publication | Benchmarks, published tools and research code | Product + stricter families chosen per repo | Product + type-aware rules | CI, strict mode |

All three repos in Part 2 are **product** tier. Strictness above product is chosen per repo when one needs it.

## Measurements

Default branches on 2026-10-15, run locally on Windows. Tools: ruff 0.15.9, oxlint 1.88.0, ESLint 9.39.5, Biome 2.5.15, pyright 1.1.408.

Findings per repo:

| Repo | Tool | Findings | Left after autofix (+ format for ruff) | Time |
|---|---|---|---|---|
| portfolio (493 files) | oxlint | 138 | 120 | 0.4 s |
| VoxGarbler `game/` | oxlint | 13 | 13 | 0.3 s |
| flashback (108 py files) | ruff product set | 145 | 16 | 0.1 s |
| VoxGarbler Python (270 files) | ruff product set | 578 | 138, of which 35 are B008 on FastAPI calls | 0.1 s |

Rejected candidates:
- **ESLint recommended** found 69 in portfolio (5.5 s) and 105 in `game/` (17 s). It needs a config and npm dependencies, and 15 of the portfolio findings are false `no-undef` hits on page-injected globals.
- **Biome** reported over 15 000 findings untuned.

Reformat scope: `ruff format` rewrites 75 of 108 files in flashback and 248 of 270 in VoxGarbler.

Hook cost per commit (VoxGarbler hooks, 4 staged files, warm cache, mean of 8):

| Runner | Commit time | Hook overhead |
|---|---|---|
| none | 119 ms | — |
| pre-commit 4.7.0 | 1351 ms | 1.2 s |
| prek 0.5.5 | 731 ms | 0.6 s |

- **Full-repo run:** 1.6 s, warm.
- **Cold start:** 39 s the first time a hook version runs on a machine. The cache is shared across repos and worktrees.
- **Session estimate:** the busiest day in 90 days was 91 commits (portfolio). prek adds about 0.9 min to such a day.
- **Larger cost:** blocked commits cost the agent about one turn each. At an assumed 10% block rate, that is 3-9 min on a 91-commit day. L6 makes most blocks a plain re-stage. A lint failure caught in CI instead costs a 3-15 min round trip.

VoxGarbler Python tests, Windows, Python 3.12:
- With light dependencies only (no torch, whisperx or transformers): 1008 passed and 11 skipped in 64 s. Install takes about 10 s with uv.
- Full suite with ML dependencies: 1014 passed and 5 skipped in 68 s.
- No test needs corpus data.

## Hook configs

Hook versions are pinned by tag. Dependabot moves them (L9).

portfolio:
```yaml
repos:
  - repo: https://github.com/oxc-project/mirrors-oxlint
    rev: v1.88.0
    hooks:
      - id: oxlint
        args: [--deny-warnings]
```

VoxGarbler:
```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.17.1
    hooks:
      - id: ruff-check
        args: [--fix]
      - id: ruff-format
  - repo: https://github.com/oxc-project/mirrors-oxlint
    rev: v1.88.0
    hooks:
      - id: oxlint
        args: [--deny-warnings]
        files: ^game/
```

flashback-sampler:
```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.17.1
    hooks:
      - id: ruff-check
        args: [--fix]
      - id: ruff-format
  - repo: local
    hooks:
      - id: zig-fmt
        name: zig fmt
        entry: zig fmt
        language: system
        files: ^core/.*\.zig$
```

The ruff rules live in each `pyproject.toml`, so editors and plain `ruff` calls use the same rules:
```toml
[tool.ruff.lint]
select = ["E", "F", "W", "I", "B", "UP"]
ignore = ["E501"]

[tool.ruff.lint.flake8-bugbear]
# VoxGarbler only: FastAPI dependency markers are meant to sit in defaults.
extend-immutable-calls = ["fastapi.Depends", "fastapi.Query", "fastapi.Header", "fastapi.Cookie", "fastapi.Body", "fastapi.Form", "fastapi.File"]
```

`target-version` comes from `requires-python` (flashback 3.10, VoxGarbler 3.11), so UP rules never suggest syntax the floor cannot run.

Excludes (generated files, vendored code, `public/` assets) are set during each fix PR, with an `exclude:` regex in the config. They do not go in tool-specific ignore files.

## CI `lint` job

Each caller adds one job through `check.yml` v1.0.0:

```yaml
  lint:
    uses: Phlares/workflows/.github/workflows/check.yml@ef4ee4741aa6ee0017a6446b55356e50bf635c49 # v1.0.0
    with:
      name: lint
      timeout-minutes: 5
      run: pipx run --spec prek==0.5.5 prek run --all-files --show-diff-on-failure
```

- No `install` and no `node-version` or `python-version` input. `pipx` and Node are on the `ubuntu-latest` image. This avoids the setup-python cache error in a folder with no `pyproject.toml` (deferred minor 4).
- flashback adds `zig-version: 0.16.0` and drops `zig fmt --check build.zig src` from its `zig` job.
- No cache for the prek home directory. A cold run takes about 40 s. A cache needs a `check.yml` input, which is a v1.1 decision.
- A failing hook, or a hook that modifies a file, exits non-zero (verified with prek 0.5.5) and produces the normal `report.json` (job `lint`, step `run`).
- The prek version in `run` is a manual bump: Dependabot does not read it. The plan adds a line in each repo's caller comment saying so.

Placement and gate per repo:

| Repo | Workflow | Trigger | Gate |
|---|---|---|---|
| portfolio | `ci.yml`, job `lint`, `if: github.event_name != 'push'` | every PR | added to `ci-pass` `needs` |
| flashback-sampler | `test.yml`, job `lint` | every PR and push (same as `pytest` and `zig`) | owner adds `lint / lint (1)` to required checks on `main` and `dev` |
| VoxGarbler | new `lint.yml` | every PR, push to `master` | owner adds `lint / lint (1)` as a required check on `master` |

VoxGarbler's lint gets its own file because its other workflows filter by path. A path-filtered check cannot be required: a skipped check never reports.

Each repo's `.github/dependabot.yml` gains:
```yaml
  - package-ecosystem: pre-commit
    directory: /
    schedule:
      interval: monthly
    groups:
      hooks:
        patterns: ["*"]
```
flashback keeps `target-branch: dev` on the new entry.

## VoxGarbler Python CI

New workflow `py-ci.yml`:

```yaml
on:
  pull_request:
    paths: &py ["src/**", "tests/**", "scripts/**", "deploy/**", "pyproject.toml", "requirements-ci.txt", ".github/workflows/py-ci.yml"]
  push:
    branches: [master]
    paths: *py

jobs:
  pytest:
    uses: Phlares/workflows/.github/workflows/check.yml@ef4ee4741aa6ee0017a6446b55356e50bf635c49 # v1.0.0
    with:
      name: pytest
      python-version: "3.12"
      timeout-minutes: 5
      install: |
        pip install -r requirements-ci.txt
        pip install --no-deps -e .
      run: pytest -q
```

- `requirements-ci.txt` lists the light set: pytest, numpy, soundfile, flask, fastapi, uvicorn[standard], authlib, itsdangerous, httpx, requests, cmudict, scikit-learn, pyloudnorm, librosa, pillow, praat-parselmouth. The plan pins versions from the working local environment.
- `pyproject.toml` dependencies stay as they are, so the deploy images do not change.
- Tests that need torch or models skip already. A new test that imports a heavy module without a skip guard fails this job, which is the wanted signal.
- The pip cache keys on `pyproject.toml` and `requirements*.txt`, both present.
- Runner: `ubuntu-latest`, because the deploy images run Linux. The suite was measured on Windows only, so the plan's first task runs it on Linux and records the result.
- `pytest` is not a required check, because the path filter can skip it. This matches `game-ci`.

## Rollout

One PR per repo per step. Each PR is watched by the CI-watch hook.

1. **VoxGarbler Python CI** (`py-ci.yml`, `requirements-ci.txt`). Must be green before step 3, so the lint fix PR is tested.
2. **flashback-sampler lint**: config, `pyproject.toml` rules, fix pass, `lint` job, `zig fmt` move, Dependabot entry. Smallest finding count, so it proves the pattern first.
3. **VoxGarbler lint**: same set, plus `lint.yml`.
4. **portfolio lint**: config, fix pass, `lint` job in `ci.yml`, `ci-pass` needs, Dependabot entry. Merge through Trunk.

Each fix PR keeps behaviour-changing fixes separate from mechanical ones:
- **Commit 1:** `ruff format` alone.
- **Commit 2:** autofixes (`--fix`, `oxlint --fix`).
- **Commit 3:** manual fixes.
- **Then:** `.git-blame-ignore-revs` lists commits 1 and 2.

The full test suite must pass unchanged after each commit, with the same test counts as the base branch.

## Owner steps

- `uv tool install prek` (installed 2026-10-15 during measurement; keep it).
- VoxCollage: `git config --unset core.hooksPath`. prek and pre-commit refuse to install while it is set, and it has Windows worktree bugs.
- `prek install` once in each repo's main checkout. Linked worktrees share the hook.
- Required checks: flashback `lint / lint (1)` on `main` and `dev`; VoxGarbler `lint / lint (1)` on `master`. Session deny rules block these edits.
- Merge each PR.

## Risks

| Risk | Mitigation |
|---|---|
| Reformat commit conflicts with open branches | Land each fix PR when few branches are open; `.git-blame-ignore-revs` keeps blame useful |
| An autofix changes behaviour | Autofix and manual fixes are separate commits; full suite with equal test counts after each |
| A Dependabot hook bump adds new findings | The bump PR runs `lint` and fails; fix in the bump PR. ruff adds rules to stable families only in minor releases |
| prek is young (0.x) and breaks | Config uses upstream keys only; switch `prek` to `pre-commit` in the run line and the local install |
| `pipx` leaves the runner image | The `lint` job fails at once and visibly; fix by adding `python-version` once deferred minor 4 ships |
| Hook slows agent sessions | Budget L10; typecheck and tests stay out of the hook |
| An agent bypasses the hook | Global rules forbid `--no-verify` and `core.hooksPath` edits; CI `lint` catches anything that slips |
| VoxGarbler tests fail on Linux | First plan task measures on Linux before any lint work |

## Non-goals

- Typecheck for Python (pyright or mypy). A follow-up item, CI only, with its own fix pass.
- Type-aware TS lint rules.
- The copier template.
- `check.yml` changes, including a prek cache input and the 7 deferred minors.
- PokePlanner and vps-ai-manager adoption.
- The vitest `expect-expect` rule (standard tier in the fuzz report). oxlint 1.88 does not list it; revisit when it ships.

## Follow-ups

1. Copier template: caller file, `dependabot.yml`, hook config per tier.
2. Python typecheck in CI (pyright), product tier.
3. `check.yml` v1.1: deferred minors, and a cache input if the cold lint run proves slow.
4. Part 3b (separate spec).
