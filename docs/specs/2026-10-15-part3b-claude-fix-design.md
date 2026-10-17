# Part 3b: CI-fix routing and the `claude-fix` workflow — design

Date: 2026-10-15. Status: draft for review.
Builds on: `2026-10-12-shared-ci-workflows-design.md` (v1, D1-D9) and `2026-10-15-part2-lint-design.md`.
Consumer: portfolio epic #617 (PostHog finding, then issue, then fix PR).

## Goal

A CI failure or a reported bug gets exactly one fixer, chosen by a rule, not by chance. Success means:

- The session that opened a PR fixes its own CI failures. This is the default.
- Adding the `claude-fix` label to an issue or a PR starts one fix run, which ends in a draft PR or a commit on the PR branch.
- An automatic fix on CI failure exists, is off by default, and is turned on per repo.
- No two fixers work on one issue or PR at the same time.
- Nothing merges without a human. No run pushes to a protected branch.
- A caller file is under 25 lines.

## Executors

| Executor | Runs on | GitHub Actions minutes | Claude usage | Starts |
|---|---|---|---|---|
| Local session | The developer's PC | none for the agent | subscription | the CI-watch hook wakes it (exists) |
| Cloud session (`/autofix-pr`) | Anthropic VM | none for the agent | subscription | by hand, per PR |
| `claude-fix.yml` (claude-code-action) | GitHub runner | the whole job (private repos draw on the 3,000-minute Pro quota; public repos are free) | subscription | `claude-fix` label, or a failed CI run when auto is on |

CI runs that any fix triggers use runner minutes as before.

The Claude GitHub App connects them. It gives the Action its push identity (`claude[bot]`), and its pushes start CI. It delivers check failures and review comments to cloud sessions. One install covers the chosen repos. It always holds its full permission set, Workflows write included; GitHub has no partial grant.

## Decisions

| # | Decision | Why |
|---|---|---|
| F1 | Ownership is a label on the issue or PR: `owner:local`, `owner:cloud`, `owner:action`. At most one at a time. | Anthropic documents no coordination between local and cloud sessions. Labels are visible, cheap, and readable by every executor. |
| F2 | A session claims a PR when it opens it, not when CI fails | No delayed start is needed. A delay costs billed minutes on private repos (environment wait timers are public-repo only on Pro; a 15-minute sleep bills 16 minutes), and races. |
| F3 | The claim ends with the session. At session end, a red PR is handed to the Action by adding `claude-fix`. | A PR left red is picked up, not forgotten. The label is set with the developer's token, so it starts workflows. |
| F4 | `claude-fix` is a request. The run removes it at start. Adding it again means retry. | A natural loop guard: one label, one run. |
| F5 | A manual `claude-fix` overrides any owner label | The human decides. The run replaces the owner label with `owner:action`. |
| F6 | Auto fix is on when the caller lists the `workflow_run` trigger. There is no `auto` input. | One mechanism: the trigger is the switch (D4). |
| F7 | Auto fix skips: non-PR runs, fork PRs, PRs with any `owner:*` label, commits pushed by `claude[bot]`, and commits that already had an auto attempt | The bot never re-fixes its own failure. That failure goes to the human. |
| F8 | Billing: `CLAUDE_CODE_OAUTH_TOKEN` (subscription). No API key. | Documented for CI on Pro and Max plans. No dollar cap; caps per run (F9) and a usage review instead. |
| F9 | Caps per run: `max-turns` 50, `timeout-minutes` 20, one run at a time per issue or PR | The median portfolio CI fix in session history took 35 turns and 13-16 min. |
| F10 | `model` is a caller input. Default `opus` until the pilot (Rollout step 3) sets it. | Session history holds no Sonnet CI fixes, so there is no basis for a cheaper default yet. |
| F11 | Targeted tests: the run may call `test-command` only with test files or IDs from the failure, never bare. Empty `test-command` = no setup, no tests. | Install plus targeted tests costs 1-2 runner minutes. A wrong blind push costs a full CI run (at least 15 minutes in portfolio). |
| F12 | Toolchain setup moves into a composite action `.github/actions/setup`, used by `check.yml` and `claude-fix.yml`. Both ship as v1.1.0; `check.yml` inputs do not change. | Two workflows now share the steps. Reverses D9, whose reason ("one workflow") no longer holds. |
| F13 | Tools: issue runs get file edit tools and `test-command` only. PR runs also get a general shell. No web fetch in either. | Issue text from #617 holds visitor-generated content and can carry prompt injection. PR runs read the repo's own code and CI logs. |
| F14 | Output is a draft PR or a commit on an existing PR branch. A run never merges, never pushes to the default branch, and never edits `.github/`. | Branch protection enforces the first two. The prompt states the third; review catches a breach. |
| F15 | When no clear fix exists, the run posts a comment with its findings and stops | A wrong fix costs more review time than a note. |
| F16 | Routines: a watch item only | Research preview. No CI-failure trigger. Revisit when one ships, or when an HTTP fire from a workflow is documented. |

## Labels

| Label | Meaning | Set by | Removed by |
|---|---|---|---|
| `owner:local` | A live local session owns fixes | the CI-watch hook, at `gh pr create` | the session-end hook; a manual `claude-fix` |
| `owner:cloud` | A cloud session owns fixes | the developer, with `/autofix-pr` | the developer; merge or close |
| `owner:action` | A `claude-fix` run is working | `claude-fix.yml`, at start | `claude-fix.yml`, at end (also on failure) |
| `claude-fix` | Request a fix run | the developer; the session-end hook | `claude-fix.yml`, at start |

The plan creates the four labels in each adopting repo (`gh label create`).

## Flows

### 1. Local session (default)

1. The session runs `gh pr create`. The CI-watch hook adds `owner:local` and records the PR in a per-session state file.
2. The hook wakes the session when checks finish. The wake message names the PR's owner label.
3. If the owner is still `owner:local`, the session fixes and pushes. If another owner holds the PR, the session stands down.

### 2. Session end

A `SessionEnd` hook reads the state file. For each PR still labelled `owner:local`:
1. It removes `owner:local`.
2. If the PR's checks are red and the repo has a `claude-fix` caller, it adds `claude-fix` (flow 3b).

A session that dies without `SessionEnd` leaves a stale `owner:local`. The developer removes it, or adds `claude-fix` (F5).

### 3a. `claude-fix` on an issue

1. `issues: labeled` starts the caller. The job runs only for the `claude-fix` label.
2. Claim: remove `claude-fix`, add `owner:action`.
3. Check out the default branch. Run setup when `test-command` is set.
4. claude-code-action runs with the issue title and body as the task (F13 tools).
5. Claude edits, runs targeted tests, and pushes `claude/issue-<n>`. It opens a draft PR that says `Fixes #<n>`.
6. Release: remove `owner:action`. The push starts the PR's CI.
7. A failure on that PR goes to the developer (F7). They may add `claude-fix` to the PR (flow 3b).

### 3b. `claude-fix` on a PR

1. `pull_request: labeled` starts the caller. Fork PRs are refused.
2. Claim: remove `claude-fix` and any owner label, add `owner:action`.
3. Check out the PR head branch. Run setup when `test-command` is set.
4. Collect the failure: download the `ci-failure-*` artifacts (`report.json`) from failed runs on the head commit. For a failed job without a report, save the last 200 lines of `gh run view --log-failed`.
5. claude-code-action runs with those files as the task. Claude fixes, runs targeted tests, and pushes one commit to the PR branch.
6. Release: remove `owner:action`. The push starts CI.

### 3c. Hand-off to the cloud

The developer runs `/autofix-pr` on the PR branch, then `gh pr edit <n> --add-label owner:cloud --remove-label owner:local`. The cloud session reacts to each failed check and review comment until the PR closes or auto-fix is turned off. A later helper script may do both steps in one command.

### 4. Auto fix (opt-in)

1. A listed CI workflow completes with conclusion `failure`. `workflow_run` runs the caller from the default branch, so a PR cannot change the gate.
2. The gate step applies F7. The per-commit marker is a commit status, context `claude-fix/auto`, state `success`, set before the fix starts.
3. If the gate passes, the run continues as flow 3b from step 2.

Several workflows can fail on one commit. `concurrency: claude-fix-<pr>` (no cancel) queues them. The first run sets the marker; later runs see it and stop.

## `claude-fix.yml` interface

Trigger: `workflow_call`. One job.

| Input | Type | Default | Meaning |
|---|---|---|---|
| `model` | string | `opus` | Model alias passed as `--model` |
| `max-turns` | number | `50` | Passed as `--max-turns` |
| `timeout-minutes` | number | `20` | Job limit |
| `runs-on` | string | `ubuntu-latest` | Runner label |
| `node-version`, `python-version`, `zig-version`, `working-directory`, `install`, `env` | | as `check.yml` | Setup, through the composite action |
| `test-command` | string | `""` | Command the run may call with specific tests. Empty = no setup, no tests |

Secret: `CLAUDE_CODE_OAUTH_TOKEN` (required), passed by name (D5).

The caller grants: `contents: write`, `pull-requests: write`, `issues: write`, `actions: read`, `statuses: write`, `id-token: write`.

Steps: target (issue or PR, from the event), gate (auto only), claim, checkout, setup, collect, fix (claude-code-action, pinned by hash, D6), release (`if: always()`).

The prompt template lives in `claude-fix.yml`, not in callers. It states F11, F14 and F15, and names the failure files.

## Composite `setup` action

- Location: `.github/actions/setup/action.yml`. Steps: setup-node, setup-python, setup-zig, each when its version is set, and the `env` parse.
- A reusable workflow resolves `uses: ./...` against the caller's repo. So both workflows check out `Phlares/workflows` at `${{ job.workflow_sha }}` (the called workflow's own commit) into `.wf/`, then use `./.wf/.github/actions/setup`. The action always matches the workflow's version, with no second pin.
- `check.yml` keeps its inputs, outputs, check names and `report.json`. The v1 self-test cases must pass unchanged.

## Caller example (portfolio)

```yaml
name: claude-fix
on:
  issues: { types: [labeled] }
  pull_request: { types: [labeled] }
  # Auto fix (opt-in): uncomment.
  # workflow_run: { workflows: [ci], types: [completed] }
permissions: { contents: write, pull-requests: write, issues: write, actions: read, statuses: write, id-token: write }
jobs:
  fix:
    if: github.event.label.name == 'claude-fix' || github.event.workflow_run.conclusion == 'failure'
    uses: Phlares/workflows/.github/workflows/claude-fix.yml@<full sha> # v1.1.0
    with:
      node-version: "24"
      install: npm ci
      test-command: npx vitest run
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

## Local hooks

These live in `~/.claude`, outside this repo. The spec fixes their contract; the plan builds them with tests.

- `watch-pr.sh` (exists): on `gh pr create`, add `owner:local` and append the PR URL to `~/.claude/state/owned-prs/<session id>`. On wake, print the owner label. A missing label in the repo is a warning, not an error.
- `session-end-handoff.sh` (new `SessionEnd` hook): flow 2. It reads the caller's presence with `gh api repos/<repo>/contents/.github/workflows/claude-fix.yml`.

## Self-test

`self-test.yml` gains cases that need no Claude call:

| Job | Proves |
|---|---|
| `setup-composite` | `check.yml` through the composite action passes all v1 cases unchanged |
| `fix-gate` | the gate script's decisions for each F7 case, from fixture event JSON |
| `fix-collect` | the collect step finds `report.json` from the `fail` job and the log fallback from a job without one |

A full `claude-fix` run is tested in the pilot, not in self-test, because it spends subscription usage.

## Rollout

1. `Phlares/workflows`: composite action, `check.yml` and `claude-fix.yml` v1.1.0, self-test cases. Merge on green `verify`; tag `v1.1.0`.
2. First plan task: verify that claude-code-action's App-token exchange (OIDC) works when the action runs inside a reusable workflow from another repo. If it fails, the spec returns for a decision before any caller ships.
3. **Pilot, portfolio.** Labels, caller, `CLAUDE_CODE_OAUTH_TOKEN` secret. Seed 4 failures on throwaway PRs. Run each on Sonnet and on Opus. Record fixed or not, turns, minutes, and the `/usage` change. Pin the `model` default from the result.
4. Local hooks: `owner:local` claim and session-end hand-off.
5. flashback-sampler and VoxGarbler callers. Each repo needs branch protection on its default branch first (VoxGarbler `master`: done 2026-10-16).
6. Review after two weeks: usage, minutes, fix rate. Tune F9 and F10.

## Owner steps

- Install the Claude GitHub App on the adopting repos.
- `claude setup-token`; add `CLAUDE_CODE_OAUTH_TOKEN` as a secret in each adopting repo.
- Review the pilot table and confirm the model default.
- Merge each PR.

## Risks

| Risk | Mitigation |
|---|---|
| OIDC token exchange fails inside a cross-repo reusable workflow | Rollout step 2 tests it first |
| Prompt injection through issue text | F13 tools; no `.github/` edits (F14); draft PRs; branch protection |
| The App's Workflows write lets a hijacked run change CI | Branch protection; draft-only output; human review of every diff |
| Usage limits drain | F9 caps; auto off by default; two-week review |
| Stale `owner:local` after a crash | Manual `claude-fix` overrides (F5) |
| Runs fight over one PR | F1 single owner; per-PR concurrency group |
| Targeted test rule ignored | The full suite still runs in CI after the push |
| `workflow_run` runs with secrets on PR code | Fork PRs refused (F7); same-repo branch authors already have write access |

## Non-goals

- The PostHog-to-issue step and backlog picking (#617). It reuses the F1 labels.
- Routines (F16).
- API-key billing.
- Fixes on default-branch push failures.
- Review agents on PRs.

## Follow-ups

1. Backlog picker for #617: claims issues with `owner:*` labels.
2. Helper script for the cloud hand-off (flow 3c).
3. Routines, when a CI-failure trigger or a documented workflow fire exists.
