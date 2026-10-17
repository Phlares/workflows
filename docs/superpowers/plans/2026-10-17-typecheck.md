# Python typecheck in CI (pyright) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** flashback-sampler and VoxGarbler run pyright (standard mode) on every change in CI, and each repo has zero pyright errors when its PR merges.

**Architecture:** Each repo gets one `[tool.pyright]` block in `pyproject.toml`, a hash-locked pyright pin, and one `typecheck` job that calls `check.yml`. One PR per repo carries three kinds of commit: the gate (red CI), mechanical fixes, and manual fixes (green CI).

**Tech Stack:** pyright 1.1.414 (PyPI wheel; bundles the JS, runs on the runner's Node), uv 0.9 (`uv pip compile`), GitHub Actions through `Phlares/workflows` `check.yml` v1.0.0, PySide6, pytest, zig 0.16.0.

**Spec:** `C:\Users\Ryon\Documents\dev\workflows\docs\specs\2026-10-17-typecheck-design.md`. Session rules and conflict rules: `C:\Users\Ryon\Documents\dev\workflows\.cache\handoffs\handoff-2026-10-17-wave1.md` (S1 section).

## Global Constraints

- pyright mode: **standard** (pyright's default). The config never sets `typeCheckingMode`. The rule set is never weakened.
- `[tool.pyright]` blocks: verbatim from the spec's Config section. flashback `pythonVersion = "3.10"`, `pythonPlatform = "Windows"`. VoxGarbler `pythonVersion = "3.11"`, `pythonPlatform = "Linux"`, `reportMissingImports = "warning"`. No `include`, no `venv`, no `pyrightconfig.json`. `extraPaths` only if Task 6 needs it.
- `typecheck` job: verbatim from the spec's CI section. Pin `Phlares/workflows/.github/workflows/check.yml@ef4ee4741aa6ee0017a6446b55356e50bf635c49 # v1.0.0` (same as the sibling jobs today; if S2 has re-pinned the siblings when you merge default in, match them). `python-version: "3.12"`, `timeout-minutes: 5`, `run: pyright`.
- Lock recipe, verbatim: `uv pip compile <name>.in --output-file <name>.txt --generate-hashes --universal --python-version 3.12`. Never `-o`, never `--python-platform` (Dependabot's uv updater drops it).
- Suppressions: `# pyright: ignore[<rule>]  # <reason>`, at most 10 per repo, each listed in the PR body. An 11th: stop and ask the owner.
- Test counts after every commit equal the branch-point baseline (re-measured in Task 1 / Task 4). Spec baselines for reference: flashback pytest 635 passed / 1 skipped / 2 deselected, zig 257; VoxGarbler 1008 passed / 11 skipped (light env).
- Branches: `ci/typecheck`, cut from the default branch (flashback `origin/dev`, VoxGarbler `origin/master`). Update by merging the default branch in, never rebase (conflict rule 2). One open PR per repo.
- Worktrees: `Documents/dev/flashback-wt/typecheck`, `Documents/dev/VoxCollage-wt/typecheck`. Never switch the owner's checkouts.
- Text rules: plain short sentences. No AI attribution in commits, PRs or issues. Git identity stays the owner's.
- Git Bash: set `MSYS2_ARG_CONV_EXCL='*'` per `git show ref:path` or `gh api` call only, never exported for a whole chain (it breaks `/c/` paths for `git worktree add` and `uv`).
- Deletion policy: no `rm -r`, `git clean`, `git worktree remove`. Move candidates to `_ToRemove/`; one approval prompt at the end.
- Required checks, rulesets and merges are owner steps.
- Ledger: `workflows/.superpowers/sdd/2026-10-17-typecheck/progress.md` (gitignored). One line per event: task, result, ruling with cost-if-wrong.

## Deviations from the spec

- **D1. The `.in` line is loose (`pyright`), not `pyright==1.1.414`.** Dependabot's uv entry runs `lockfile-only`: it moves the lock inside the `.in` constraint and never edits the `.in`. An exact pin in the `.in` would freeze pyright, against T10 ("bumps pyright monthly"). prek uses the same loose form. 1.1.414 is the latest release today (PyPI, 2026-10-17), so the lock resolves to the measured version. Step checks below fail if it resolves to anything else.
- **D2. Branches come from the default branch**, not `ci/pin-hashes` (merged 2026-10-17).

## Review Focus

1. **Local and CI counts disagree for flashback.** `pythonPlatform = "Windows"` fixes platform narrowing, so the Linux runner and a Windows laptop must report the same error count with the same deps. Pinned by Task 1 Step 7 (CI count == local count).
2. **VoxGarbler CI passes while the full venv still has errors.** The light CI set hides 16 errors as `Unknown`. Merging on CI green alone would ship them. Pinned by Task 6 Step 3 (full-venv `pyright` exit 0 is the gate, CI green is the second check).
3. **`exclude` replaces pyright's defaults, so a missed folder floods the count.** A worktree venv (`.venv-ci`) or `_ToRemove/` inside the repo root would be scanned if the list were wrong. Pinned by Task 1 Step 4 and Task 4 Step 4 (source-file count within ±5 of the spec's 108 / 271, and no path under `.venv` in the output).
4. **pyright silently downloads Node.** The wheel falls back to `nodeenv` (unpinned download) when no global `node` is on PATH. ubuntu-latest has Node. Pinned by Task 1 Step 7 and Task 4 Step 7 (job log has no `nodeenv` line).
5. **The mechanical commit's hash is lost from blame.** `.git-blame-ignore-revs` lists a branch commit hash. Both repos merge with merge commits, so the hash survives unless the branch is rebased. Pinned by Task 7 Step 3 (`git merge-base --is-ancestor <hash> origin/<default>` after the owner merges).

---

## File map

| Repo (worktree) | File | Change |
|---|---|---|
| flashback-sampler (`flashback-wt/typecheck`, base `dev`) | `pyproject.toml` | Add `[tool.pyright]` |
| | `requirements-typecheck.in` | Create: `pyright` |
| | `requirements-typecheck.txt` | Create: hash lock |
| | `.github/workflows/test.yml` | Add `typecheck` job; header comment says four jobs |
| | `.git-blame-ignore-revs` | Append the enum commit |
| | `flashback_sampler/**`, `tests/**`, `tools/**`, `packaging/**` | Fix pass |
| VoxGarbler (`VoxCollage-wt/typecheck`, base `master`) | `pyproject.toml` | Add `[tool.pyright]` |
| | `requirements-ci.in` | Add `pyright` |
| | `requirements-ci.txt` | Recompile (other pins stay) |
| | `.github/workflows/py-ci.yml` | Add `typecheck` job; header comment |
| | `.git-blame-ignore-revs` | Append the mechanical commit |
| | `src/**`, `tests/**`, `scripts/**`, `game/**`, `deploy/**` | Fix pass |

`.github/dependabot.yml` needs no change: the uv entry (`directory: /`) already pairs every `requirements*.in` with its `.txt` by basename.

## Shared procedures

**P1. Worktree.** Inputs `<repo-dir>`, `<wt>`, `<base>`.
```bash
cd /c/Users/Ryon/Documents/dev/<repo-dir> && git fetch -q origin
git worktree add -b ci/typecheck ../<wt> origin/<base>
```

**P2. Worktree venv (uv).** An editable install in the owner's venv points at the owner's checkout, so each worktree gets its own venv. Inputs `<python>`, `<install>`.
```bash
uv venv --python <python> .venv-ci && source .venv-ci/Scripts/activate && <install>
echo .venv-ci/ >> "$(git rev-parse --git-common-dir)/info/exclude"
```

**P3. pyright count.** `pyright --outputjson > "$S/pyright-<repo>-<tag>.json"; echo "exit=$?"`, then read `.summary` (`filesAnalyzed`, `errorCount`, `warningCount`) with `python -c`. Group errors by `rule` for the ledger. `$S` = this session's scratchpad.

**P4. Commit gate.** Run the repo's suite; the summary line must equal the baseline. Then `git add -u` (VoxGarbler: first `git restore` the tracked asset files the bake tests rewrote; `git status --short` must hold only intended files) and commit.

---

### Task 1: flashback gate (config, pin, job)

**Files:** `pyproject.toml`, `requirements-typecheck.in`, `requirements-typecheck.txt`, `.github/workflows/test.yml`

**Interfaces:**
- Produces: check `typecheck / typecheck (1)`; `FB_BASE` (pytest line + zig count); `FB_E0` (local error count, by rule); draft PR number `FB_PR`.

- [ ] **Step 1: Worktree and venv.** P1 with `flashback-sampler`, `flashback-wt/typecheck`, `dev`. P2 with `3.12` and `uv pip install -e ".[dev]"`. Build the DLL: `(cd core && zig build -Doptimize=ReleaseSafe)`.
- [ ] **Step 2: Baseline.** `QT_QPA_PLATFORM=offscreen PYTHONUTF8=1 FLASHBACK_REQUIRE_NATIVE=1 pytest tests/unit -m "not audio_hw and not perf" -q -p no:cacheprovider 2>&1 | tail -1` and `(cd core && zig build test --summary all 2>&1 | tail -3)`. Compare the pytest line with the last green `dev` run (`gh run list -R Phlares/flashback-sampler --workflow test.yml --branch dev --status success -L 1`, then its `pytest` job log). Record `FB_BASE`. A mismatch: find why before going on.
- [ ] **Step 3: Pin.** Create `requirements-typecheck.in` with one comment line (same style as `requirements-lint.in`) and `pyright`. Compile with the lock recipe. Expected: the `.txt` holds `pyright==1.1.414`, `nodeenv`, `typing-extensions`, every line hashed. Any other pyright version: stop and record (D1 assumption broke). Mutation: alter every pyright hash, `pip install --require-hashes --target "$S/hashcheck" -r requirements-typecheck.txt` → hash mismatch error; restore with `git checkout`.
- [ ] **Step 4: Config.** Add the spec's flashback `[tool.pyright]` block after `[tool.ruff.lint]`. `uv pip install --require-hashes -r requirements-typecheck.txt`. P3 tag `e0`. Expected: `filesAnalyzed` 103-113, no file path containing `.venv-ci` or `_ToRemove`, `errorCount` about 404. Record `FB_E0`.
- [ ] **Step 5: Job.** Add the spec's `typecheck` job to `test.yml` after `lint`. Update the header comment: four jobs, `typecheck` runs pyright on Ubuntu. Run actionlint (`gh release download -R rhysd/actionlint -p 'actionlint_*_windows_amd64.zip' -D "$S"` once): clean.
- [ ] **Step 6: Commit, push, draft PR.** P4, then commit `ci: pyright typecheck job (red until the fix pass)`. Push, `gh pr create --draft --base dev`. PR body: what the gate is, `FB_E0` by rule, D1, the owner step (required check `typecheck / typecheck (1)` on `main` and `dev`), and an empty "Suppressions" and "Behaviour fixes" list.
- [ ] **Step 7: Red CI is the gate's proof.** `gh pr checks <FB_PR> --watch`. Expected: `typecheck / typecheck (1)` fails; `report.json` failing step is `run`; the log's summary `N errors` equals `FB_E0`; the log has no `nodeenv` line; `pytest`, `zig`, `lint` green. A count mismatch: diff the two outputs and find why before any fix.

### Task 2: flashback mechanical fixes (enum long forms)

**Files:** `flashback_sampler/**`, `tests/**`, `.git-blame-ignore-revs`

**Interfaces:**
- Consumes: `FB_E0` JSON from Task 1 Step 4.
- Produces: commit hash `FB_MECH`; `FB_E1` count.

- [ ] **Step 1: Rewriter, in the scratchpad (not committed).** `"$S/enum_longform.py" <pyright.json>`: for each `reportAttributeAccessIssue` whose message matches `Cannot access attribute "(\w+)" for class "type\[(\w+)\]"`, import the class from PySide6 (`QtCore`, `QtGui`, `QtWidgets`, in that order), find every nested `enum.Enum` subclass on it that has the member, and if exactly one does, replace the member name at the diagnostic's range with `<Enum>.<member>`, keeping the qualifier before it (`Qt.AlignLeft` → `Qt.AlignmentFlag.AlignLeft`). Zero or several matches: print the site and leave it for Task 3. Apply edits bottom-up per file so ranges stay valid.
- [ ] **Step 2: Run it.** `prek run --all-files` (ruff format may re-wrap long lines): exit 0. P3 tag `e1`. Expected: `errorCount` drops by about 160; no new rule appears in the by-rule table versus `FB_E0`.
- [ ] **Step 3: Commit.** P4 with `FB_BASE`. Commit `style: PySide6 enum long forms`. Record `FB_MECH` = its hash. Append `FB_MECH # style: PySide6 enum long forms` to `.git-blame-ignore-revs`; commit `chore: blame ignores the enum long forms`. Push.

### Task 3: flashback manual fixes to zero

**Files:** `flashback_sampler/**`, `tests/**`, `tools/**`, `packaging/**` as the findings require; test files for behaviour fixes.

**Interfaces:**
- Consumes: `FB_E1` JSON.
- Produces: green `typecheck`; suppression list; behaviour-fix list.

- [ ] **Step 1: Work by cause, one commit per cause** (spec fix guide, in this order: loose annotations at their source; `float | None` sources; `None` member access in tests via `assert x is not None`; Optional at call sites; the rest). After each commit: P3 (count only falls) and P4 with `FB_BASE`.
- [ ] **Step 2: Behaviour fixes, TDD.** For each site where `None` is reachable in app code (first: `flashback_sampler/app/turntable_window.py:431`, `QCoreApplication.instance()` is `None` with no app): write a test that calls the path with the `None` condition and fails today (`AttributeError`), run it red, fix (handle the `None` branch), run green. Name pattern `test_<function>_without_<thing>`. Add a PR body line per fix. Commit `fix: <what> when <condition>`.
- [ ] **Step 3: Zero.** P3: `errorCount` 0, `exit=0`. Suppressions counted with `git grep -n "pyright: ignore" | wc -l` ≤ 10. zig suite once: count equals `FB_BASE`. Push.
- [ ] **Step 4: CI green.** `gh pr checks <FB_PR> --watch`: all four checks green; CI pytest line equals `FB_BASE`.
- [ ] **Step 5: Mutation check.** Commit `test: typecheck mutation (revert next)` that adds `int("x", base="ten")` (wrong argument type) to a function body in `flashback_sampler/`. Push. Expected: `typecheck` red, `report.json` step `run`, one error naming that line. Revert with `git revert --no-edit HEAD`, push, green. Record both run ids in the ledger and PR body.

### Task 4: VoxGarbler gate (config, pin, job)

**Files:** `pyproject.toml`, `requirements-ci.in`, `requirements-ci.txt`, `.github/workflows/py-ci.yml`

**Interfaces:**
- Produces: check `typecheck / typecheck (1)` (not required); `VG_BASE`; `VG_E0` (light-env count); `VG_F0` (full-venv count); draft PR `VG_PR`; venvs `.venv-ci` (light) and `.venv-full`.

- [ ] **Step 1: Worktree and venvs.** P1 with `VoxCollage`, `VoxCollage-wt/typecheck`, `master`. P2 with `3.12` and `uv pip install --require-hashes -r requirements-ci.txt && uv pip install --no-deps -e .` (CI set). Full venv for the fix pass: `uv venv --python 3.13 .venv-full`, then install `../../VoxCollage/.venv/Scripts/python -m pip freeze --exclude-editable` into it with `uv pip install --python .venv-full -r -`, then `uv pip install --python .venv-full --no-deps -e .`. A pin that does not resolve (a local `+cu` torch build): use the index URL from the owner venv's pip config, and record it in the ledger. Add `.venv-full/` to `info/exclude`.
- [ ] **Step 2: Baseline.** `.venv-ci`: `pytest -q -p no:cacheprovider 2>&1 | tail -1`. Must equal the last green `py-ci` run on `master`. Bake tests need `D:\VoxCollage\GameAssets`; restore tracked files they touch (P4). Record `VG_BASE`.
- [ ] **Step 3: Pin.** Add `pyright` to `requirements-ci.in` (alphabetical). Recompile with the lock recipe. uv keeps the existing pins as preferences. Expected `git diff requirements-ci.txt`: only added blocks for `pyright==1.1.414`, `nodeenv` and their hashes, plus `via` comment lines; no other version changes. A moved pin: stop and record. Hash mutation as in Task 1 Step 3.
- [ ] **Step 4: Config.** Add the spec's VoxGarbler `[tool.pyright]` block. Install pyright into both venvs from the lock. P3 tag `e0` with `.venv-ci` active → `VG_E0` ≈ 175 errors, ≈ 63 warnings. P3 tag `f0` with `pyright --pythonpath .venv-full/Scripts/python.exe` → `VG_F0` ≈ 191. Both: `filesAnalyzed` 266-276, no `.venv-ci`/`.venv-full`/`_ToRemove` path.
- [ ] **Step 5: Job.** Add the spec's `typecheck` job after `pytest` in `py-ci.yml`. Header comment: pyright runs on the same light set; heavy imports warn. actionlint clean.
- [ ] **Step 6: Commit, push, draft PR.** P4, commit `ci: pyright typecheck job (red until the fix pass)`, `gh pr create --draft --base master`. Body as Task 1 Step 6, with both counts and the note that the job is not required (path filter).
- [ ] **Step 7: Red CI.** Expected: `typecheck` fails at step `run`; log count equals `VG_E0`; no `nodeenv` line; `pytest` green with `VG_BASE`.

### Task 5: VoxGarbler mechanical fixes

**Files:** `scripts/blind_ab.py`, files holding `dict[tuple[int, int], X]` values passed as `dict[Pos, X]`, `.git-blame-ignore-revs`

**Interfaces:**
- Consumes: `VG_F0` JSON.
- Produces: `VG_MECH` hash; `VG_F1`.

- [ ] **Step 1: `blind_ab.py`.** Annotate the variable at the assignment pyright infers as `frozenset[str] | int` with its real type. P3 (full venv): the 38 `blind_ab.py` errors drop to 0 or near it.
- [ ] **Step 2: `Pos` aliases.** Annotate each variable with the `Pos` alias where the error names `dict[Pos, ...]`. P3: those errors gone, no new rule.
- [ ] **Step 3: Commit.** P4 with `VG_BASE`. Commit `style: type annotations for inferred unions and Pos maps`. Record `VG_MECH`; append to `.git-blame-ignore-revs`; commit `chore: blame ignores the annotation commit`. Push.

### Task 6: VoxGarbler manual fixes to zero

**Files:** as the findings require; test files for behaviour fixes; `pyproject.toml` only for `extraPaths`.

**Interfaces:**
- Consumes: `VG_F1` JSON.
- Produces: zero errors in both venvs; green `typecheck`.

- [ ] **Step 1: Manual fixes by cause**, one commit per cause, as Task 3 Step 1. After each: P3 with `.venv-full` (count only falls) and P4 with `VG_BASE`.
- [ ] **Step 2: Behaviour fixes, TDD**, as Task 3 Step 2. First: `src/vox_collage/selector.py:685`, division by a value that can be `None`.
- [ ] **Step 3: Unresolved local imports.** `render_eval` (script imported by a test): `extraPaths = ["scripts"]` only if the test puts `scripts/` on `sys.path` at runtime (read the test); otherwise narrow. `tokenizer` (sibling of `labelprior_ctc_driver.py`): `extraPaths` for its folder under the same rule. `Charsiu` (vendored, optional): one suppression with reason. Commit `ci: pyright paths for runtime sys.path entries`.
- [ ] **Step 4: Zero in both venvs.** P3 with `.venv-full`: `errorCount` 0. P3 with `.venv-ci`: `errorCount` 0, warnings are `reportMissingImports` only. Suppressions ≤ 10. Push.
- [ ] **Step 5: CI green** with `pytest` line equal to `VG_BASE`.
- [ ] **Step 6: Mutation check** as Task 3 Step 5, in a file under `src/vox_collage/` (inside the path filter).

### Task 7: Review, PRs ready, close-out

**Interfaces:**
- Consumes: both PRs green.

- [ ] **Step 1: Review per repo.** `/simplify` then `/code-review medium`, inline, one pass each, on each branch diff (the manual and behaviour commits; skip the mechanical commit). Fix findings in new commits; P4 after each. Merge the default branch in (never rebase); CI green again.
- [ ] **Step 2: PRs ready.** PR body complete (counts by rule before/after, suppression list ≤ 10 with reasons, behaviour fixes with their tests, mutation run ids, D1, owner step). `gh pr ready`. Owner merges; then the other wave-1 sessions merge default into theirs (conflict rule 2).
- [ ] **Step 3: After each merge.** `git merge-base --is-ancestor <FB_MECH|VG_MECH> origin/<default>` → exit 0. Comment on Phlares/workflows#12 with both PR links and the owner step; close #12 when both are merged and the required check is set, else post NEXT.
- [ ] **Step 4: Close-out.** Update memory `project_typecheck_ci` and its `MEMORY.md` line. List worktrees, branches and `.venv-ci`/`.venv-full` folders for the owner to remove. One `_ToRemove/` approval prompt.
