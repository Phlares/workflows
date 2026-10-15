# Handoff: specs for Part 2 (lint) and Part 3b (label-triggered fix)

Start a fresh session in `C:\Users\Ryon\Documents\dev` and paste:

> Write the specs for Part 2 and Part 3b of the shared CI standard. Read `workflows/docs/handoff-2026-10-15-part2-3b.md` first, then the v1 spec it names. Use superpowers:brainstorming for each part, Part 2 first. Batch your questions to me per part. Spec only: no plans, no code, no repo changes outside `workflows/docs/specs/`.

## State at handoff

- v1 shipped. `Phlares/workflows` `check.yml` v1.0.0 = `ef4ee4741aa6ee0017a6446b55356e50bf635c49`.
- Callers merged: flashback-sampler #92 (python + zig), VoxGarbler #70 (game/, js), portfolio #636 (unit shards).
- Read first: `workflows/docs/specs/2026-10-12-shared-ci-workflows-design.md` (decisions D1-D9, non-goals, "After v1" list) and `workflows/README.md`.
- Ledger with rulings and deferred minors: `workflows/.superpowers/sdd/2026-10-12-shared-ci-workflows/progress.md`. The 7 deferred minors are v1.1 candidates. Decide whether Part 2 absorbs any of them.
- Part 3a is live: `~/.claude/bin/watch-pr.sh` (PostToolUse hook) wakes the session when PR checks pass or fail.

## Part 2 scope (from the v1 spec)

1. **Lint measurement.** No repo runs a linter today. Measure locally first: which linters, how many findings per repo, run time. Repos: portfolio (js), VoxGarbler `game/` (ts), flashback-sampler (python + zig). The owner likes linters.
2. **Where lint runs.** Pre-commit hook first, CI as the last line (a lint line in the caller's `run`, or a separate shard). Decide how the hook config reaches each repo.
3. **VoxGarbler Python CI.** None exists today. Scope which Python parts get CI, with what runner, data and time limit.

Open questions to settle in the spec:
- The copier template (D8, item 1 of "After v1") carries the pre-commit config. Does Part 2 include the template, or ship hook configs by hand first?
- Fix existing findings in one pass per repo, or a baseline file plus "no new findings"?
- Does lint failure block merge (`ci-pass` / required checks) from day one?

## Part 3b scope (from the v1 spec and portfolio epic #617)

`claude-code-action` starts on a `claude-fix` label, reads the failure `report.json` artifact from `check.yml`, and drafts a fix PR. Portfolio epic #617 (PostHog scouts → issue → `claude-fix` → PR) is the first consumer. Ruled 2026-10-12: CI standard before #617.

Open questions to settle in the spec:
- Billing order. `CLAUDE_CODE_OAUTH_TOKEN` (subscription) vs API credits. The owner's Max-plan API credits cover the API and Agent SDK, not Claude Code. Verify which one the action uses and what a run costs.
- Trigger scope: a failed CI check, a labelled issue, or both. The label stays manual: the owner decides which failures get a fix attempt.
- Security: no workflow runs on untrusted input without the label. Avoid `pull_request_target` with a checkout of PR code. Token scopes are minimal. The action can never push to `main` (branch protection already requires `ci-pass`). `Phlares/workflows` is public, so callers pass secrets by name (`secrets: inherit` is org-only).
- Cost cap per run and per month.
- Generic workflow in `Phlares/workflows` vs per-repo file. Epic #617 asks for it parameterised (repo, labels, PostHog project).
- Relation to Part 3a research: cloud auto-fix (`/autofix-pr`), routines, `claude -p --cloud`. Say why the label-triggered action wins, or what replaces it.

## Session rules

- Spec before plan: brainstorm, batch owner questions, verify every issue claim against the code or the API. Plans come later, in their own session.
- Decisions to the owner get a sectioned primer: mechanism, who reads it, effect, fix, why here.
- Write specs to `workflows/docs/specs/2026-10-15-<part>-design.md`. Commit through a PR on `Phlares/workflows` (`main` requires `verify`).
- No AI attribution in commits, PRs or issues.

## Traps

- Session deny rules block branch-protection and ruleset reads and edits. Those are owner steps.
- Never switch the owner's checkouts (`VoxCollage` sits on a feature branch). Use worktrees.
- Git Bash mangles `ref:path` arguments (`git show origin/main:file`). Set `MSYS2_ARG_CONV_EXCL='*'`.
- The job log API needs `--allow-escape-sequences`. `gh run view --log` refuses while any job runs.
- actionlint is not installed. Download the release zip to the scratchpad.
- No shellcheck locally, so a local actionlint misses SC findings that CI catches.
- Equivalence baselines must run on the same tree. A PR branch run can predate other merges.
