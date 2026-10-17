# Python typecheck in CI (pyright)

Date: 2026-10-17. Status: draft for review. Issue: Phlares/workflows#12.
Builds on: `2026-10-15-part2-lint-design.md` (tiers, fix-pass rules, `check.yml` callers).

## Goal

flashback-sampler and VoxGarbler run pyright on every change, in CI only. Success means:

- Each repo has `[tool.pyright]` in `pyproject.toml` as the single config, a `typecheck` job through `check.yml`, and zero errors at merge of its fix PR.
- Test counts equal the base branch after every commit of the fix pass.
- flashback: `typecheck / typecheck (1)` is a required check on `main` and `dev`.
- `check.yml` does not change.

## Why typecheck, and what it does not buy

Lint (Part 2) finds style and a few bug patterns. A typechecker finds a `None` used as a value, a wrong argument type, and a missing attribute. Two findings from the measurement look like real latent crashes:

- `flashback_sampler/app/turntable_window.py:431` calls `.quit()` on `QCoreApplication.instance()`, which is `None` when no app exists.
- `src/vox_collage/selector.py:685` divides by a value that can be `None`.

Most findings are not bugs. In flashback about 160 are PySide6 enum shorthand (`Qt.AlignLeft`) that works at runtime but is absent from the 6.x stubs. The fix pass is mechanical for those and the check then holds the line for agent-written code.

## Decisions

| # | Decision | Why |
|---|---|---|
| T1 | Tool: **pyright**, pinned by version in the caller's `install` line | Fastest Python checker (4 s flashback, 20 s VoxGarbler). Same tool measured in Part 2. mypy needs per-package stubs for PySide6 and numpy. |
| T2 | Mode: **standard** (pyright's default) | Adds override, possibly-unbound and overlapping-overload rules to basic. Costs 1 extra error per repo today. Owner chose it 2026-10-17. |
| T3 | CI only, never in the commit hook | 4-20 s per run exceeds the 1 s hook budget (Part 2 L10). |
| T4 | Config lives in `[tool.pyright]` in `pyproject.toml` | One config for CI, editors (Pylance reads it) and local runs. No `pyrightconfig.json`. |
| T5 | `pythonVersion` = the repo's lowest supported version (`3.10` flashback, `3.11` VoxGarbler); `pythonPlatform` = the shipped target (`Windows` flashback, `Linux` VoxGarbler) | The check reports syntax and APIs newer than `requires-python`. Platform narrowing follows the product, not the runner. flashback on Linux vs Windows differs by 2 errors, both platform-only. |
| T6 | flashback: own `typecheck` job in `test.yml`, Ubuntu, required check | Runs in parallel with `pytest`, `zig` and `lint`. No Zig build. Owner chose it 2026-10-17. |
| T7 | VoxGarbler: `typecheck` job in `py-ci.yml`, not required | Same deps and path filter as `pytest`. A path-filtered check cannot be required (Part 2). Owner chose it 2026-10-17. |
| T8 | VoxGarbler sets `reportMissingImports = "warning"` | CI installs `requirements-ci.txt` only; 63 imports of 20 heavy modules (torch, transformers, whisperx) do not resolve there. pyright exits 0 on warnings, so the gate holds and the log keeps the list. A local run with the full venv still shows a typo as a warning. |
| T9 | Fix pass follows Part 2 rules: fix the code, never weaken the rule set; at most 10 inline suppressions per repo, each with a reason, listed in the PR body | Owner chose it 2026-10-17. The guide below covers the finding classes measured. |
| T10 | pyright version is a manual pin, like prek | Dependabot's pip ecosystem does not read a workflow file. A pinned version means a pyright release never turns an unrelated PR red. |

## Tier

Product tier (Part 2 table): typecheck in CI, standard mode. Strict mode stays for infra and science repos. Both repos here are product.

## Measurements

Default branches on 2026-10-17 (flashback `dev` 36d26ea, VoxGarbler `master` 171afda), pyright 1.1.414, run locally on Windows against each repo's full venv (Python 3.13).

| Repo | Files | Errors, basic | Errors, standard | Analysis time |
|---|---|---|---|---|
| flashback-sampler | 108 | 403 | 404 | 4 s |
| VoxGarbler | 271 | 190 | 191 | 20 s |

The issue's figures (404 and 191, measured 2026-10-15 with 1.1.408) were standard mode.

flashback by rule (standard): reportAttributeAccessIssue 176, reportArgumentType 143, reportOptionalMemberAccess 63, reportOperatorIssue 9, other 13. By location: `flashback_sampler/` 190, `tests/` 214.

flashback by cause:

| Cause | Count | Fix |
|---|---|---|
| PySide6 enum shorthand: `Qt.AlignLeft`, `QMessageBox.Yes`, `QPainter.Antialiasing`, `QSizePolicy.Expanding`, ... | ~160 | Long form: `Qt.AlignmentFlag.AlignLeft`. Same object at runtime. |
| `None` member access (`"x" is not a known attribute of "None"`) | 63 | Narrow. Tests: `assert obj is not None`. App code: handle the `None` branch. |
| `float \| None` passed to `float()` or an `int` parameter | ~50 | Narrow, or give the attribute a non-Optional type with a default. |
| Loose annotations (`Path \| str \| float`, `str \| int \| float \| None`) rejected at call sites | ~40 | Fix the annotation at its one source; do not touch the call sites. |
| `QualityPreset \| None` / `Manifest \| None` passed where the value is required | 28 | Narrow at the call. |

VoxGarbler by rule (standard): reportArgumentType 116, reportOptionalSubscript 17, reportAttributeAccessIssue 15, reportCallIssue 8, reportOptionalOperand 7, other 28. By location: `src/` 69, `tests/` 64, `scripts/` 54, `game/` 3, `deploy/` 1. `scripts/blind_ab.py` alone has 38, all one cause (a value inferred as `frozenset[str] | int` at its assignment).

Under the CI dependency set (`requirements-ci.txt`, no torch): 238 errors, of which 63 are reportMissingImports. With T8 those become warnings and the error count is 175: the unresolved modules type as `Unknown`, which hides 16 of the full-venv errors. The fix pass runs against the full local venv, so it fixes all 191.

Three imports do not resolve even in the full venv: `Charsiu` (vendored, optional), `tokenizer` (a sibling module in `labelprior_ctc_driver.py`) and `render_eval` (a script imported by a test). The builder resolves each by `extraPaths` or a narrowed guard; a suppression counts toward the cap.

## Config

flashback `pyproject.toml`:
```toml
[tool.pyright]
pythonVersion = "3.10"
pythonPlatform = "Windows"
# Setting exclude replaces pyright's default list, so the defaults are repeated.
exclude = ["build", "dist", "_ToRemove", "**/node_modules", "**/__pycache__", "**/.*"]
```

VoxGarbler `pyproject.toml`:
```toml
[tool.pyright]
pythonVersion = "3.11"
pythonPlatform = "Linux"
exclude = ["_ToRemove", "**/node_modules", "**/__pycache__", "**/.*"]
# CI installs requirements-ci.txt (no torch, whisperx, transformers).
# Those imports resolve locally and warn in CI; warnings do not fail the run.
reportMissingImports = "warning"
```

No `include`: pyright scans every `.py` under the repo root, so a new folder is checked without a config change. No `venv` setting: local runs use the activated venv's `python`, CI runs use the runner's.

Local run: `pip install pyright==<ver>` into the repo venv once, then `pyright` from the repo root. The version is the one in the caller file.

## CI `typecheck` job

Each caller adds one job through `check.yml`, pinned to the same commit as the sibling jobs in that file (v1.0.0 today; Dependabot bumps them together).

flashback `test.yml`:
```yaml
  typecheck:
    uses: Phlares/workflows/.github/workflows/check.yml@ef4ee4741aa6ee0017a6446b55356e50bf635c49 # v1.0.0
    with:
      name: typecheck
      python-version: "3.12"
      timeout-minutes: 5
      # The pyright version is a manual bump: Dependabot does not read it.
      install: pip install -e ".[dev]" pyright==1.1.414
      run: pyright
```

VoxGarbler `py-ci.yml`:
```yaml
  typecheck:
    uses: Phlares/workflows/.github/workflows/check.yml@ef4ee4741aa6ee0017a6446b55356e50bf635c49 # v1.0.0
    with:
      name: typecheck
      python-version: "3.12"
      timeout-minutes: 5
      # The pyright version is a manual bump: Dependabot does not read it.
      install: |
        pip install -r requirements-ci.txt pyright==1.1.414
        pip install --no-deps -e .
      run: pyright
```

- `[dev]` (flashback) and `requirements-ci.txt` (VoxGarbler) bring pytest, so `tests/` resolves.
- `pip install -e .` in flashback needs no Zig: the package has no build step; the DLL loads at runtime.
- The pip `pyright` package wraps the npm package of the same version and uses the runner's Node.
- pyright exits 1 on any error and 0 on warnings only, so `check.yml` reports a failure of step `run` with the normal `report.json`.
- Cost: about 1 min of pip install (PySide6 or the light ML set) plus 4-20 s of analysis.

Placement and gate per repo:

| Repo | Workflow | Trigger | Gate |
|---|---|---|---|
| flashback-sampler | `test.yml`, job `typecheck` | every PR and push to `main`/`dev` (same as `pytest`) | owner adds `typecheck / typecheck (1)` to required checks on `main` and `dev` |
| VoxGarbler | `py-ci.yml`, job `typecheck` | path-filtered, same as `pytest` | none, like `pytest` |

## Fix pass

One PR per repo, branch from the default branch (`dev` for flashback, `master` for VoxGarbler). Commits, in order; the full suite passes with equal test counts after each:

1. **Config and job.** `[tool.pyright]` plus the `typecheck` job. CI goes red here; this is the gate's proof. Record the error count from the CI log.
2. **Mechanical fixes.** flashback: enum long forms. VoxGarbler: the `blind_ab.py` inference fix and the `dict[Pos, ...]` annotations. Each is a find-and-replace or a one-line annotation with no behaviour change.
3. **Manual fixes.** Everything else, by the guide below. Behaviour-changing fixes (a real `None` path) each get a test that pins the fix and a line in the PR body.
4. Repeat 3 until `pyright` exits 0 locally against the full venv, and CI is green.

Fix guide. Fix the code; never weaken the rule set.

- **Enum shorthand** (`Cannot access attribute "X" for class "type[Qt]"` and other Qt classes): use the enum's long form. PySide6 documents only the long form.
- **`None` member access, subscript or operand**: in tests, `assert x is not None` right after the fixture or lookup. In app code, read the site: if `None` is reachable, handle it (return, raise, or default); if not, narrow with an assert and a short reason.
- **Optional passed to a required parameter**: narrow at the call. Do not add `| None` to the callee.
- **Loose union annotation rejected at many call sites**: fix the annotation where it is declared. One change, many sites green.
- **`float | None` into `float()` / `int()`**: give the source a concrete type and a default where the code already assumes one; otherwise narrow.
- **Wrong inferred type at an assignment** (`frozenset[str] | int`): annotate the variable at that assignment.
- **Type alias mismatch** (`dict[tuple[int, int], X]` vs `dict[Pos, X]`): annotate the variable with the alias.
- **Incompatible override**: match the base signature. If the subclass needs more, add keyword-only parameters with defaults.
- **Redeclaration**: rename the second declaration.
- **Unresolved local import**: `extraPaths` in `[tool.pyright]` when the folder is on `sys.path` at runtime (tests that import scripts). An optional vendored module gets a suppression.
- Anything not listed: read the rule doc and fix it.

`# pyright: ignore[<rule>]  # <reason>` is allowed only when the code is right and the check is wrong for that line. Each one is listed in the PR body. More than 10 in one repo: stop and ask the owner.

Test baselines (Part 2 ledger): flashback pytest 635 passed / 1 skipped / 2 deselected, zig 257; VoxGarbler 1008 passed / 11 skipped (light env). The plan re-measures each on the branch point before commit 1.

Mutation check: with CI green, push one commit that adds a call with a wrong argument type in a source file; `typecheck` must go red with step `run` in `report.json`. Revert.

## Rollout

1. flashback-sampler: config, job, fix pass. Larger count but mostly mechanical; proves the pattern.
2. VoxGarbler: config, job, fix pass.

The two repos are independent and can run in parallel sessions. Open PRs flashback #102 and VoxGarbler #76 (claude-fix callers) add `claude-fix.yml`; this work edits `test.yml` and `py-ci.yml`, so no conflict.

## Owner steps

- Merge each PR.
- Required check: flashback `typecheck / typecheck (1)` on `main` and `dev`. Session rules blocked the rulesets API this session.

## Risks

| Risk | Mitigation |
|---|---|
| A PySide6 release changes its stubs and turns `typecheck` red on an unrelated PR (PySide6 is `>=6.7`, unpinned) | Same exposure as `pytest` today (6.12 exit crash, #93). Fix in a cap PR; the lockfile follow-up (#11) removes it. |
| A manual fix changes behaviour | Mechanical and manual commits are separate; equal test counts after each; behaviour fixes get a pinning test. |
| VoxGarbler CI misses an error that the full venv shows (16 today) | The fix pass runs against the full venv. Local `pyright` before push is the developer's check. |
| pyright pin goes stale | Follow-up: a `requirements-typecheck.txt` read by Dependabot's pip ecosystem, scoped to pyright, once #14 confirms Dependabot keeps SHA pins. |
| 404 fixes conflict with open flashback branches | Land when few branches are open. Enum rewrites touch many lines; `.git-blame-ignore-revs` lists the mechanical commit. |

## Non-goals

- Typecheck in the commit hook.
- mypy, or strict mode.
- `check.yml` changes.
- Portfolio (JS; type-aware lint is a separate item), PokePlanner, vps-ai-manager.
- Pinning PySide6 or the ML set.

## Follow-ups

1. Dependabot-driven pyright bumps (see Risks).
2. Copier template (#13) gains the `[tool.pyright]` block per tier.
3. Strict mode for the infra/science tier when such a repo adopts CI.
