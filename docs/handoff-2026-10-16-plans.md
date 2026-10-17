# Handoff: plans for Part 2 (lint) and Part 3b (claude-fix)

Both specs are approved and on `main` (PR #4, `010a90c`). Each part gets its own fresh session in `C:\Users\Ryon\Documents\dev`. The two sessions are independent and can run at the same time.

## Part 2 prompt

> Write the implementation plan for Part 2 of the shared CI standard. Read `workflows/docs/handoff-2026-10-16-plans.md` first (shared rules and the Part 2 section), then `workflows/docs/specs/2026-10-15-part2-lint-design.md`. Use superpowers:writing-plans. Save the plan to `workflows/docs/superpowers/plans/2026-10-16-part2-lint.md` and commit it through a PR on Phlares/workflows. Stop for my review before executing.

## Part 3b prompt

> Write the implementation plan for Part 3b of the shared CI standard. Read `workflows/docs/handoff-2026-10-16-plans.md` first (shared rules and the Part 3b section), then `workflows/docs/specs/2026-10-15-part3b-claude-fix-design.md`. Use superpowers:writing-plans. Save the plan to `workflows/docs/superpowers/plans/2026-10-16-part3b-claude-fix.md` and commit it through a PR on Phlares/workflows. Stop for my review before executing.

## Shared state

- `check.yml` v1.0.0 = `ef4ee4741aa6ee0017a6446b55356e50bf635c49`. Callers: flashback-sampler, VoxGarbler `game-ci`, portfolio `unit`.
- Format model for the plan: `workflows/docs/superpowers/plans/2026-10-12-shared-ci-workflows.md`. Its ledger (`workflows/.superpowers/sdd/2026-10-12-shared-ci-workflows/progress.md`) shows the ruling and mutation-check style. Each plan gets its own ledger folder.
- The CI-watch hook (`~/.claude/bin/watch-pr.sh`) wakes the session when PR checks finish.

## Part 2 notes

- Rollout order is fixed by the spec: VoxGarbler `py-ci`, flashback lint, VoxGarbler lint, portfolio lint (through Trunk).
- `prek` 0.5.5 is installed in `~/.local/bin` (uv tool).
- `requirements-ci.txt` versions come from the working env `VoxCollage/.venv`. The spec's first task runs the light suite on Linux (measured only on Windows: 1008 passed, 64 s).
- The VoxGarbler `master` ruleset exists (deletion, force push, PR required, 0 approvals) and has no required checks. The owner adds `lint / lint (1)` after the VoxGarbler lint PR merges.
- Owner steps from the spec: `git config --unset core.hooksPath` in VoxCollage, `prek install` per main checkout, required-check edits, merges.

## Part 3b notes

- Task 1 is the go/no-go: claude-code-action's App-token exchange (OIDC) inside a reusable workflow called from another repo. On failure, stop and return to the owner with the spec; no caller ships.
- The composite `setup` action is loaded by checking out `Phlares/workflows` at `${{ job.workflow_sha }}` (verified in the GitHub contexts reference: the called workflow's commit). `check.yml` keeps every input, check name and `report.json` field; the v1 self-test cases must pass unchanged.
- The pilot spends subscription usage: 4 seeded failures × Sonnet and Opus, on throwaway portfolio PRs. The owner confirms before it starts and picks the model default from the table.
- The local hooks (`watch-pr.sh` change, new `session-end-handoff.sh`) live in `~/.claude`. Test them with a fake `gh` (the existing hook already takes `GH=` for this).
- Owner steps: install the Claude GitHub App on adopting repos, `claude setup-token`, add the `CLAUDE_CODE_OAUTH_TOKEN` secret per repo.

## Session rules

- TDD for code. Mutation-check every new test (break the code, confirm red).
- No AI attribution in commits, PRs or issues.
- `main` on Phlares/workflows requires `verify`. The CI-watch hook always reports FAILED there (`fail`, `fail-win`, `fail-install` fail on purpose). Check `verify` with `gh run view`.
- Never switch the owner's checkouts. Use worktrees in the session scratchpad.
- Deletion policy: move candidates to `_ToRemove/`; one approval prompt at the end.
- Decisions to the owner get a sectioned primer: mechanism, who reads it, effect, fix, why here.

## Traps

- Git Bash mangles `ref:path` arguments. Set `MSYS2_ARG_CONV_EXCL='*'`.
- Session deny rules block branch-protection edits. Rule reads through `gh api repos/<r>/rules/branches/<b>` work.
- The job log API needs `--allow-escape-sequences`. `gh run view --log` refuses while any job runs.
- actionlint is not installed: download the release zip to the scratchpad. No shellcheck locally, so CI can catch SC findings that local actionlint misses.
- A required check on a path-filtered workflow never reports when skipped and blocks the PR.
