# Part 3b: CI-fix routing and the `claude-fix` workflow — design

Date: 2026-10-15. Status: approved; revised 2026-10-17 after review (F13, F14, F17, F18; flow 3a; risks) and for v1.2.0 (F13, F17, flow 3b marker); revised for v1.4.0 (F7, F18, flows 3a and 4: bounded auto retry, #22; commit author, #19).
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
| F7 | Auto fix skips: non-PR runs, fork PRs, draft PRs not opened by `claude[bot]`, PRs with any `owner:*` or `needs-human` label, commits pushed by a bot other than `claude[bot]`, and commits that already had an auto try. A PR gets at most `auto-tries` auto tries (default 2). At the cap, the run posts one stop comment that mentions the PR author (the repository owner when the author is a bot) and adds `needs-human`. Label runs always run and do not count. | A fix that is close but wrong gets a second try; the cap stops loops, and the stop reaches a person instead of waiting silently. A person's draft is often red on purpose. Other bots stay out: claude-code-action admits only the bots in `allowed_bots`, here `claude`. A label is a person asking. |
| F8 | Billing: `CLAUDE_CODE_OAUTH_TOKEN` (subscription). No API key. | Documented for CI on Pro and Max plans. No dollar cap; caps per run (F9) and a usage review instead. |
| F9 | Caps per run: `max-turns` 50, `timeout-minutes` 20, one run at a time per issue or PR | The median portfolio CI fix in session history took 35 turns and 13-16 min. |
| F10 | `model` is a caller input. Default `opus` until the pilot (Rollout step 3) sets it. | Session history holds no Sonnet CI fixes, so there is no basis for a cheaper default yet. |
| F11 | Targeted tests: the run may call `test-command` only with test files or IDs from the failure, never bare. Empty `test-command` = no setup, no tests. | Install plus targeted tests costs 1-2 runner minutes. A wrong blind push costs a full CI run (at least 15 minutes in portfolio). |
| F12 | Toolchain setup moves into a composite action `.github/actions/setup`, used by `check.yml` and `claude-fix.yml`. Both ship as v1.1.0; `check.yml` inputs do not change. | Two workflows now share the steps. Reverses D9, whose reason ("one workflow") no longer holds. |
| F13 | Tools: issue runs, and PR runs on a PR whose author is not a collaborator (a bot such as Dependabot) or that holds a commit from another bot (Renovate, an autofix App; this repo's own `github-actions[bot]` and `claude[bot]` count as people), get file edit tools and the publish script only: no setup, no tests, no shell. PR runs on a collaborator's PR also get a general shell and `test-command`. No web fetch in any run. Edit and Write are scoped to the workspace and denied under `$RUNNER_TEMP`, the runner's `_*` work folders, the tool cache and home dotfiles (the workspace sits under home); reads outside the workspace and the task folder are refused. | An issue run that could write a file and then run it (a test, a config) would run injected code with the App token in its environment. For the same reason, no step after the fix step runs code from the workspace: they use a read-only copy of the scripts outside it, and the workspace `.git` (and any `.wf` Claude wrote) is moved out. A bare Write would reach the runner's own files, such as `$GITHUB_ENV`, which later steps apply; a bare Read would reach the process environment, which holds the Claude token. PR runs read the repo's own code and CI logs. |
| F14 | Output is a draft PR or a commit on an existing PR branch. A run never merges, never pushes to the default branch, and never edits `.github/`. | Branch protection enforces the first two. `fix-publish.sh` enforces the third, and refuses unknown `.git/config` keys and an `origin` that is not this repo (Claude can write under `.git/`). |
| F15 | When no clear fix exists, the run posts a comment with its findings and stops | A wrong fix costs more review time than a note. |
| F16 | Routines: a watch item only | Research preview. No CI-failure trigger. Revisit when one ships, or when an HTTP fire from a workflow is documented. |
| F17 | Trust follows the author of the text Claude reads. Issue runs take only issues whose author is `OWNER`, `MEMBER` or `COLLABORATOR`; other issues get a "Not run" comment. The same rule decides whether a PR run may run code (F13). HTML comments are removed from the issue body. | The label shows a maintainer read the issue, but CI and Vercel run whatever the fix pushes, before review. Until there is a gated lane (F18), untrusted text must not reach Claude. Comments do not render, so the labeller never saw them. |
| F18 | Untrusted authors (#617 visitor issues) get a second lane later: the fix pushes with `GITHUB_TOKEN`, so its PR CI waits for "Approve and run workflows". Not built in v1.1.0. | The model GitHub uses for its Copilot coding agent. Open items: the "Allow GitHub Actions to create pull requests" setting, Vercel previews (they build every pushed branch, and repo config cannot block them), a live check of the hold, and the F13 exemption for `github-actions[bot]` commits: that lane pushes visitor-shaped code as that account, so the exemption goes when it lands. Since v1.4.0 (#19) claude-fix commits carry `claude[bot]` as author, so only older fix commits need it. Required-reviewer environments are public-repo only on Pro. |

## Labels

| Label | Meaning | Set by | Removed by |
|---|---|---|---|
| `owner:local` | A live local session owns fixes | the CI-watch hook, at `gh pr create` | the session-end hook; a manual `claude-fix` |
| `owner:cloud` | A cloud session owns fixes | the developer, with `/autofix-pr` | the developer; merge or close |
| `owner:action` | A `claude-fix` run is working | `claude-fix.yml`, at start | `claude-fix.yml`, at end (also on failure) |
| `claude-fix` | Request a fix run | the developer; the session-end hook | `claude-fix.yml`, at start |
| `needs-human` | Auto fix stopped at its cap (F7); auto runs skip the PR | `claude-fix.yml`, at the cap | the developer |

The plan creates the five labels in each adopting repo (`gh label create`).

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
2. Gate (F17): an issue not written by a collaborator gets a "Not run" comment and stops.
3. Claim: remove `claude-fix`, add `owner:action`.
4. Check out the default branch. No setup and no tests (F13).
5. claude-code-action runs with the issue title and body, HTML comments removed, as the task.
6. Claude edits and calls `fix-publish.sh`, which pushes `claude/issue-<n>-<run id>` and opens a draft PR that says `Fixes #<n>`.
7. Release: remove `owner:action`. The push starts the PR's CI.
8. A failure on that PR gets auto tries when auto fix is on (flow 4), then goes to the developer. They may add `claude-fix` to the PR (flow 3b).

### 3b. `claude-fix` on a PR

1. `pull_request: labeled` starts the caller. Fork PRs are refused.
2. Claim: remove `claude-fix` and any owner label, add `owner:action`.
3. Check out the PR head branch. Run setup when `test-command` is set and the PR author is a collaborator (F13): a bot's PR, such as a dependency bump, brings install scripts no collaborator wrote.
4. Collect the failure: download the `ci-failure-*` artifacts (`report.json`) from failed runs on the head commit. For a failed job without a report, save the last 200 lines of `gh run view --log-failed`.
5. claude-code-action runs with those files as the task. Claude fixes, runs targeted tests, and pushes one commit to the PR branch. The commit author is `claude[bot]` (the action's `bot_id` and `bot_name`).
6. Release: remove `owner:action`. The push starts CI.

### 3c. Hand-off to the cloud

The developer runs `/autofix-pr` on the PR branch, then `gh pr edit <n> --add-label owner:cloud --remove-label owner:local`. The cloud session reacts to each failed check and review comment until the PR closes or auto-fix is turned off. A later helper script may do both steps in one command.

### 4. Auto fix (opt-in)

1. A listed CI workflow completes with conclusion `failure`. `workflow_run` runs the caller from the default branch, so a PR cannot change the gate.
2. The gate step applies F7. Each auto run hides a marker line, `<!-- claude-fix/auto <sha> -->`, in its outcome comment. The gate reads only comments by `github-actions[bot]`: only workflows in the repo post as that account, so visitors cannot forge it. A marker for the failed commit means it was tried. The number of distinct commits in the markers is the try count for the PR. A forged or stray marker would only stop auto fix early. (v1.1 used a commit status; that needed `statuses: write`. A run history check does not work: `workflow_run` runs carry the default branch commit, not the PR commit.)
3. If the gate passes, the run continues as flow 3b from step 2. A `claude[bot]` push starts CI again, so a fix that fails CI comes back here as the next try.
4. At the cap, the run posts the stop comment (F7), adds `needs-human`, and stops. Later auto runs skip the PR on that label. A person who removes it gets one more stop at the next failure, not more tries.

An example with the default cap: a person's commit A fails (try 1, marker A, push B); B fails (try 2, marker B, push C); C fails (stop). A person who keeps a PR red gets the same: two tries on their commits, then one stop.

Several workflows can fail on one commit. `concurrency: claude-fix-<pr>` (no cancel) queues them. The first run posts the marker when it ends; later runs start after it, see it and stop. If the outcome comment fails to post, one more auto try can happen on that commit.

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
| `auto-tries` | number | `2` | Auto tries per PR (F7). `0` = stop on the first auto failure |

Secret: `CLAUDE_CODE_OAUTH_TOKEN` (required), passed by name (D5).

The caller grants: `contents: write`, `pull-requests: write`, `issues: write`, `actions: read`, `id-token: write`.

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
permissions: { contents: write, pull-requests: write, issues: write, actions: read, id-token: write }
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
| Hooks or MCP servers planted in a PR (`.claude/`, `.mcp.json`) | `fix-reset-config.sh` restores the default branch copies before setup and before Claude starts, on label and auto runs. The action does this only on `pull_request` events. |
| Prompt injection through issue text | F17 author gate and comment strip; F13 tools (no code runs in issue runs); F14 enforced in `fix-publish.sh`; draft PRs; branch protection |
| CI and Vercel run Claude-written code with repo secrets before review | Accepted for collaborator-authored issues and PR runs (trusted input). Untrusted input waits for F18. |
| Claude reads the App token from `.git/config` | Issue runs have no network tool and no shell; the token is revoked when the fix step ends |
| The App's Workflows write lets a hijacked run change CI | Branch protection; draft-only output; human review of every diff |
| Usage limits drain | F9 caps; auto off by default; `auto-tries` per PR (F7); two-week review |
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

1. Backlog picker for #617: claims issues with `owner:*` labels. Needs F18 first, because visitor issues fail the F17 gate.
2. Helper script for the cloud hand-off (flow 3c).
3. Routines, when a CI-failure trigger or a documented workflow fire exists.
