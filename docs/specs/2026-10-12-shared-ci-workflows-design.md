# Shared CI workflows v1 — design

Date: 2026-10-12. Status: draft for review.
Research: `Documents/dev/reports/Shared CI standard for solo developers.md` (46 sources) and `Documents/dev/reports/Fuzz and mutation testing CI.md` (tier table).

## Goal

One public repo, `Phlares/workflows`, holds the check job that every CI repo calls. v1 serves three repos: portfolio (JS), VoxGarbler `game/` (JS), and flashback-sampler (Python + Zig). Success means all three run their existing checks through the shared job, with the same coverage, and each failure produces one machine-readable report.

## Decisions

| # | Decision | Why |
|---|---|---|
| D1 | New **public** repo `Phlares/workflows` | A public repo cannot call a workflow in a private repo; PokePlanner and flashback-sampler are public. |
| D2 | Checks only. Release, publish and deploy jobs stay in each repo. | PyPI trusted publishing rejects reusable workflows; npm checks the caller filename. |
| D3 | **One** reusable workflow, `check.yml`, with value inputs | The five existing check jobs differ only in values; one job needs two toolchains. Departs from the research's per-language files on purpose. |
| D4 | No `tier` input and no on/off flags | Flags per caller are the wrong parameterization. A tier picks input values in the caller file. |
| D5 | Secrets passed by name; no `secrets: inherit` | `inherit` is documented for organizations only. v1 needs no secrets. |
| D6 | Third-party actions pinned to full commit hashes with a `# vX.Y.Z` comment; callers pin `check.yml` the same way | Supply-chain hardening (tj-actions 2025). |
| D7 | Every CI repo runs Dependabot for the `github-actions` ecosystem, grouped, monthly. npm and pip updates are opt-in per repo. | Hash pins never move on their own. Actions-only keeps bot CI runs to about one per repo per month. Revisit Renovate (shared preset) at about 10 CI repos. |
| D8 | Copier template deferred to the first item after v1 | Write it from three working callers, not from a guess. |
| D9 | No composite actions in v1 | One workflow has nothing to share them with. |

## Non-goals (v1)

- Linting (Part 2: measure locally first, then a pre-commit hook plus a lint line in `run`).
- VoxGarbler Python CI (Part 2; none exists today).
- Copier template, `claude-code-action`, label-triggered fix loop (Part 3b, epic #617).
- PokePlanner and vps-ai-manager adoption.

## Repo layout

```
Phlares/workflows/
  .github/workflows/check.yml       reusable (workflow_call)
  .github/workflows/self-test.yml   CI for this repo
  .github/dependabot.yml            github-actions, grouped, monthly
  fixtures/js/                      tiny npm project with 2 test files
  fixtures/js-sub/app/              npm project in a subfolder
  fixtures/py-zig/                  pytest + a Zig build step
  fixtures/fail/                    a test that always fails
  fixtures/fail-install/            lock file out of sync, so npm ci fails
  docs/specs/                       this file
  README.md                         inputs, caller examples per language, versioning
```

GitHub requires reusable workflows to sit flat in `.github/workflows/`.

## `check.yml` interface

Trigger: `workflow_call`. One job, `check`, with a matrix over `shards`.

| Input | Type | Default | Meaning |
|---|---|---|---|
| `name` | string | `check` | Job display name and artifact name prefix |
| `runs-on` | string | `ubuntu-latest` | Runner label |
| `node-version` | string | `""` | Empty = Node not installed |
| `python-version` | string | `""` | Empty = Python not installed |
| `zig-version` | string | `""` | Empty = Zig not installed |
| `working-directory` | string | `.` | Where `install` and `run` execute |
| `install` | string | `""` | Commands run once before `run` |
| `run` | string | required | Commands; the step stops at the first failing command |
| `env` | string | `""` | `KEY=VALUE` lines written to `$GITHUB_ENV` before `install` |
| `shards` | string (JSON array) | `[1]` | Matrix values; each shard gets `SHARD_INDEX` and `SHARD_TOTAL` |
| `timeout-minutes` | number | `15` | Per shard |

Behaviour:
- `permissions: contents: read`. `fail-fast: false` on the matrix.
- All `run:` steps use `shell: bash` (Git Bash on Windows runners).
- Toolchain setup steps run only when their version input is non-empty.
- npm cache keys on `<working-directory>/package-lock.json`; pip cache keys on `<working-directory>/pyproject.toml` and `requirements*.txt`.
- `SHARD_TOTAL` is the length of `shards`. A caller that does not shard ignores both variables.
- `run` executes as `bash -eo pipefail` with output also written to `$RUNNER_TEMP/run.log`.
- No concurrency group; callers own triggers and cancellation.

## Failure report

On failure of `install` or `run`, one step (`if: failure()`):
1. Writes a job summary: job name, shard, failing step, last 40 lines of `run.log`.
2. Emits one `::error title=<name> (shard i/n)::<last line>` annotation.
3. Uploads artifact `ci-failure-<name>-<shard>` containing `report.json`:

```json
{
  "schema": 1,
  "repo": "Phlares/portfolio",
  "pr": 640,
  "sha": "<head sha>",
  "run_url": "https://github.com/.../actions/runs/<id>",
  "job": "unit",
  "shard": 2,
  "shard_total": 3,
  "step": "run",
  "tail": ["...last 40 lines..."]
}
```

`pr` is null outside pull requests. The local CI-watch hook (`~/.claude/bin/watch-pr.sh`) and the later #617 loop both read this format.

## Versioning

- Semver tags with a GitHub release note per tag listing input changes. A breaking input change bumps the major version.
- Callers pin `Phlares/workflows/.github/workflows/check.yml@<full sha> # v1.0.0`. Their Dependabot opens the bump PR, which runs the caller's own CI.
- No moving `v1` tag.

## Self-test

`self-test.yml` runs on pull requests and pushes to `main`. It calls `./.github/workflows/check.yml`:

| Job | Inputs | Proves |
|---|---|---|
| `js` | node, `shards: [1,2]`, run asserts `SHARD_TOTAL=2` and runs that shard's test file | Node setup, npm cache, shard variables |
| `js-sub` | node, `working-directory: fixtures/js-sub/app` | subfolder installs and runs |
| `py-zig` | `windows-latest`, python + zig, one `env` line asserted in a test | two toolchains, `env`, Windows |
| `fail` | node, `working-directory: fixtures/fail`, run `npm test` (one always-failing test) | failure report is produced |
| `fail-win` | same as `fail` on `windows-latest` | failure report works on Windows |
| `fail-install` | `npm ci` on a lock file out of sync with `package.json` | report names step `install` when `run` never starts |
| `lint` | runs `actionlint` on all workflow files (plain job, not `check.yml`) | expression and syntax errors |
| `verify` | `needs` all, `if: always()` | every case passed except `fail`, which failed; downloads `ci-failure-fail-1` and asserts its JSON fields |

`verify` is the one required check on `main`.

## Callers

| Repo / job | Inputs |
|---|---|
| flashback-sampler `zig` | `zig-version: 0.16.0`, `working-directory: core`, run `zig fmt --check build.zig src` + `zig build test`, timeout 3 |
| flashback-sampler `pytest` | `runs-on: windows-latest`, `python-version: "3.12"`, `zig-version: 0.16.0`, env `QT_QPA_PLATFORM=offscreen`, `PYTHONUTF8=1`, `FLASHBACK_REQUIRE_NATIVE=1`, install `pip install -e ".[dev]"`, run build core (ReleaseSafe) then `pytest tests/unit -m "not audio_hw and not perf"`, timeout 6 |
| VoxGarbler `game-ci` | `node-version: "22"`, `working-directory: game`, install `npm ci`, run `npx tsc --noEmit`, `npm test`, `npm run build` |
| portfolio `unit` | `node-version: "24"`, install `npm ci`, run `npm run test:ci -- --shard=$SHARD_INDEX/$SHARD_TOTAL`, `shards: [1,2,3]`, env `NODE_OPTIONS=--max-old-space-size=4096`, timeout 15 |

Each caller keeps its triggers, path filters, `changes` job, `if:` conditions and `ci-pass`. Each caller PR adds `.github/dependabot.yml` with the `github-actions` ecosystem if missing (D7).

**Required-check names change** to `<caller job> / <name> (<shard>)`, `(1)` when unsharded. flashback-sampler requires `pytest (windows / py3.12)` and `zig (ubuntu)` on `main` and `dev` (per the `test.yml` header comment; the owner confirms in the UI, since session deny rules block reading protection); the owner renames them in the web UI when the PR merges. Portfolio requires only `ci-pass`; VoxGarbler has none.

## Portfolio equivalence check

Baseline: the `unit` jobs of PR #634's last CI run. Candidate: the swap PR's run.
- **Must match (merge blocker):** test files per shard, total tests, passed, skipped.
- **Reported, not gated:** wall time per shard (runner noise is about ±3 min on identical shards).
- The PR body carries the comparison table.

## Rollout

1. Create `Phlares/workflows` (public) and push this spec as the first commit. Build `check.yml`, fixtures and self-test on a branch; merge on green `verify`; tag `v1.0.0`. Owner sets branch protection (`verify` required, strict off, no force push).
2. flashback-sampler PR. Owner renames its required checks at merge.
3. VoxGarbler PR.
4. portfolio PR with the equivalence table; merge through Trunk (`/trunk merge`).

Each PR is watched by the CI-watch hook, which wakes the session on pass or fail.

## Owner steps

- Approve creating the public repo.
- Branch protection on `Phlares/workflows` `main` (session deny rules block protection edits).
- Rename flashback-sampler required checks at step 2.
- Merge each PR.

## Risks

| Risk | Mitigation |
|---|---|
| A bad `check.yml` change breaks every caller | Callers pin hashes; a new tag reaches a repo only through its own bump PR and CI |
| Required-check rename missed, flashback PRs block | Rename is an explicit owner step in the step-2 PR description |
| Portfolio test count silently drops | Equivalence table is a merge blocker |
| Windows bash differences break `run` | `py-zig` self-test runs on `windows-latest` |
| Public repo leaks internals | Repo holds generic logic only; no repo names, paths or secrets in `check.yml` |

## Follow-ups (not v1)

1. Copier template: caller file, `dependabot.yml`, pre-commit config.
2. Part 2: lint measurement, lint lines, VoxGarbler Python CI.
3. Part 3b: `claude-code-action` on `claude-fix` label, reading `report.json`; billing order to verify.
4. PokePlanner and vps-ai-manager adoption.
