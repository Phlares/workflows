# Copier template per tier, and uv.lock for Python deps

Date: 2026-10-19. Status: draft for review. Issues: Phlares/workflows#13, #32.
Builds on: `2026-10-15-part2-lint-design.md` (tiers, lint), `2026-10-17-typecheck-design.md` (pyright), #28 (suppression guard, v1.5.0), #29 (Dependabot groups).

## Goal

A new repo gets its CI, hook and Dependabot files from one copier template, at the tier it needs. Python dependencies in every repo move from compiled `requirements-*.txt` locks to one `uv.lock`, so Dependabot version and security updates both keep hashes and platform markers.

Success means:

- `copier copy` of each tier and language mix writes the expected files, and the generated repo's checks pass (tests in this repo, run in `self-test`).
- `copier update` moves a generated repo to a newer template tag and keeps Dependabot's pin edits.
- VoxGarbler has one `uv.lock`, no `requirements-*.{in,txt}`, and green CI.
- claude-fix-sandbox is regenerated from the template and runs it live on GitHub.

## Why

- Each caller's files were written by hand, three times. A new repo copies one of them and drifts from it.
- Dependabot security updates treat `requirements-ci.txt` as a plain pip file. In VoxGarbler#89 that removed `colorama`, dropped the Python 3.13 packages and lowered scipy. Version updates do not have this bug (#32).

## Tiers

A tier is a set of values in the generated files. Each tier is the one below it plus additions. `check.yml` has no tier input (D4).

| Tier | For | What the template writes |
|---|---|---|
| Greybox | Local exploration (PokePlanner, LocalModelsLand) | Nothing. The template does not offer it. |
| Prototype | Work that starts to formalize | Hooks + CI `lint` job. ruff default rules + `ruff format` + RUF100, PGH004. oxlint default rules with unused directives as errors. Suppression guard. `check-merge-conflict`. Dependabot with minor/major/security groups. |
| Product | Talks to the public: OSS, data, secrets, security, uptime | Prototype plus: ruff E, F, W, I, B, UP (E501 off). oxlint `--deny-warnings`. gitleaks hook. Test job. Python: pyright standard with `enableTypeIgnoreComments = false` and `reportUnnecessaryTypeIgnoreComment = "error"`. |
| Publication / science | Benchmarks, research code | Not shipped. Intent: consistency checks, blinding and route tests (blinded data never flows upstream), benchmarks. It is defined when the first such repo exists. |

Prototype runs tests locally only. CI runs lint.

## Decisions

| # | Decision | Why |
|---|---|---|
| C1 | The template lives in this repo: `copier.yml` at the root with `_subdirectory: template`. It shares the `v1.x` tags. | One version line. `copier update` picks the newest tag. |
| C2 | The generated caller pins `check.yml@{{ _copier_conf.vcs_ref_hash }} # {{ _copier_conf.vcs_ref }}`. The suppression hook `rev` uses the same values. Real copies and updates use tags only; tests generate from untagged commits and assert the hash, not the comment. | The template never carries a stale pin to itself. One source of truth: the commit the repo was generated from. |
| C3 | Update flow: Dependabot owns package, action and hook pins after the copy. Toolchain versions (`uv-version`, Python, Node) move by `copier update` or by hand; Dependabot does not read them. `copier update` runs by hand for structural changes (a new rule, group or hook). A pin line that both sides changed conflicts; take the newer. | Decision 2026-10-19. Copier writes conflicts as inline markers; the `check-merge-conflict` hook stops them reaching a commit. |
| C4 | New repos only. VoxGarbler, flashback-sampler and portfolio keep hand-owned files. | Decision 2026-10-19. Their custom parts (Zig, Trunk, `game/`, npm security-only) would become template options or update conflicts. |
| C5 | claude-fix-sandbox is the live adopter, at product tier, Node. On a branch, `copier copy --overwrite` runs over the existing tree: `ci.yml` and `dependabot.yml` are replaced; `package.json`, `src/`, `test/` and `claude-fix.yml` stay; `pyproject.toml` and `uv.lock` are added. The PR diff is the review. | Decision 2026-10-19. It runs the real Dependabot, lint, test and `copier update` path on GitHub. Product, because claude-fix pilots need its test job. |
| C6 | Copier asks: `tier` (prototype, product), `languages` (multiselect: python, node), `default_branch` (default `main`), `target_os` (ubuntu-latest, windows-latest; product only), `python_version` (default `3.12`; always, since the lint job runs prek through uv), `node_version` (default `24`; node only). | The four questions in #13, plus the toolchain versions. Zig is out: no new repo needs it. |
| C7 | `target_os` sets both the test runner and pyright's `pythonPlatform` (Linux or Windows). `python_version` sets `requires-python`, pyright's `pythonVersion` and the CI Python. | T5 (typecheck spec): platform and version follow the product. A new repo has one of each. |
| C8 | Secrets: gitleaks, as a pre-commit hook pinned by hash, at product tier. | GitHub secret scanning is free on public repos only. On a personal account, private repos cannot get it (it needs Secret Protection on an organization or Enterprise). gitleaks (MIT) runs the same locally and in CI on public and private repos. |
| C9 | The guard's marker table gains `gitleaks:allow` (all files). | It is an inline suppression like `noqa`. It must sit in `.suppressions` with a reason. |
| C10 | Every generated repo has `pyproject.toml` with `[dependency-groups]` and a `uv.lock`, including Node-only repos. The generated file has no `[build-system]`, so uv does not build or install the project. `lint = ["prek"]` in every repo. | One pin mechanism. prek is a Python package; Node-only repos install it the same way. |
| C11 | `pyproject.toml` and `.gitignore` are written only when absent (`_skip_if_exists`), so `copier update` never touches them. Rule values live in template-owned files that `copier update` does reach: `ruff.toml` and `pyrightconfig.json`. When `pyproject.toml` already exists, the post-copy message lists the groups to add. | A repo that already has a `pyproject.toml` keeps it. Pylance reads `pyrightconfig.json`, so T4's one-config rule holds; template repos use the file instead of `[tool.pyright]`. ruff reads `ruff.toml` before `[tool.ruff]`, so a repo must not keep both. |
| C12 | The template does not create `uv.lock`. The post-copy message says to run `uv lock`. No `_tasks`. | Tasks make the template "unsafe" (copier needs `--trust`). Without a lock, `uv sync --locked` fails CI at once, which makes the missing step loud. |
| C14 | Tool sources: ruff, oxlint and gitleaks run as hook repos (Dependabot `pre-commit`). pyright and pytest sit in uv groups (Dependabot `uv`). prek installs Node for the oxlint hook, so a lint job sets only `python-version` and `uv-version`. | As the callers run today; VoxGarbler's lint job lints `game/` with only Python set up. |
| C15 | The workflow is named `CI`. | claude-fix callers trigger on `workflow_run: { workflows: [CI] }` (README, sandbox). |
| C13 | Repo settings are out of reach of copier. The post-copy message lists them: Dependabot alerts and security updates on, required checks, `needs-human` label for claude-fix. | Copier writes files only. |

### uv in CI (#32)

| # | Decision | Why |
|---|---|---|
| U1 | `check.yml` and the `setup` action gain `uv-version` (empty = not installed), through `astral-sh/setup-uv` pinned by hash, with its cache keyed on `<working-directory>/uv.lock`. Release v1.6.0. | Decision 2026-10-19. Same pattern as `node-version` and `zig-version`. `pip install uv` would be an unhashed install and break #11. |
| U2 | Install line: `lint` uses `uv sync --locked --only-group lint`; `test` and `typecheck` use `uv sync --locked --group <job>` (project, runtime deps and the group). Run line: `uv run --no-sync <tool>`. | Lint needs no project deps. Tests and pyright need the project's imports. `--no-sync` stops `uv run` from changing the env after install, so failures stay in the step that caused them. |
| U3 | One group per job: `lint`, `typecheck`, `test`. VoxGarbler is the exception: its runtime deps include torch, so its light set is a `ci` group installed with `--only-group ci` plus `uv pip install --no-deps -e .`, as today. | One group per install line. |
| U4 | `uv.lock` is universal (uv's default). No `[tool.uv] environments` limit. | Spike 2026-10-19: VoxGarbler's full deps (torch 2.8.0, whisperx) lock universally in 3 s: 361 packages, 1.5 MB, 4,496 hashes. |
| U5 | Dependabot: `package-ecosystem: uv`, `versioning-strategy: lockfile-only`, groups as #29. | Unchanged from today. Dependabot reads `uv.lock` for both version and security updates. |
| U6 | Hash guarantee (#11) holds. | Spike 2026-10-19, uv 0.9.24: adding a dep without relocking makes `uv sync --locked` fail ("needs to be updated"); changing every prek hash in `uv.lock` makes it fail with a hash mismatch. |

Example (VoxGarbler `lint`):

```yaml
    with:
      name: lint
      python-version: "3.12"
      uv-version: "<pinned>"
      install: uv sync --locked --only-group lint
      run: uv run --no-sync prek run --all-files --show-diff-on-failure
```

## Generated files

| File | Prototype | Product | Notes |
|---|---|---|---|
| `.copier-answers.yml` | yes | yes | Never edited by hand. |
| `.github/workflows/ci.yml` | `lint` | `lint`, `test`, and `typecheck` (python) | Workflow name `ci`. `permissions: contents: read`, concurrency cancel, no path filter (required checks must always report). Python and Node tests are separate jobs when both languages are chosen. |
| `.github/dependabot.yml` | yes | yes | `github-actions`, `pre-commit`, `uv`; `npm` when node. Each with the minor/patch, major and security groups (pre-commit keeps one `hooks` group, as #29). |
| `.pre-commit-config.yaml` | yes | yes | `check-merge-conflict`, ruff (python), oxlint (node), suppression guard, gitleaks (product). Every `rev` is a hash with `# frozen:`. |
| `ruff.toml` | python | python | Rule set by tier. |
| `pyrightconfig.json` | no | python | Standard mode, the two flags, `pythonVersion`, `pythonPlatform` (C7). |
| `pyproject.toml` | yes | yes | Only when absent. `[dependency-groups]`; no `[build-system]`, so uv never builds the project. |
| `.gitignore` | yes | yes | Only when absent. `.venv/`. |

No `.suppressions` file: an absent file is a baseline of 0.

Node test job: `npm ci` then `npm test`. TypeScript typecheck is out: no adopter uses TypeScript yet.

## Order of work

1. **v1.6.0** (this repo): `uv-version` input; guard row `gitleaks:allow`. Tests first, as for every script here.
2. **VoxGarbler** (after its hook PR #91 merges): groups `lint` and `ci` in `pyproject.toml`, `uv.lock`, `lint.yml` and `py-ci.yml` on v1.6.0 with the U2 lines, `git rm` of `requirements-ci.{in,txt}` and `requirements-lint.{in,txt}`, and the `py-ci` path filter switched from `requirements-ci.txt` to `uv.lock`. Approving this spec approves those removals. `deploy/` and `release.yml` do not read the requirements files and do not change. The `dev` extra stays for local `pip install -e .[dev]`.
3. **Template** (this repo), test-first, release v1.7.0.
4. **claude-fix-sandbox**: regenerate from v1.7.0 at product tier, Node. Its `claude-fix.yml` stays. Run `copier update` once against a later commit to prove the update path.
5. flashback-sampler and portfolio move to `uv.lock` in later sessions (#32 stays open for them).

## Tests (this repo)

A test script generates each combination into a temp dir: 2 tiers × 3 language sets (python, node, both) = 6. For each:

- The file set equals the table above, exactly.
- `ci.yml` and the hook config pin the HEAD commit hash (C2). Rule values match the tier (RUF100, PGH004, the pyright flags, oxlint flags).
- actionlint passes on `ci.yml`. `dependabot.yml` passes the SchemaStore schema (check-jsonschema).
- After `uv lock` and `uv sync --locked --only-group lint`, `prek run --all-files` passes on a clean seed file per language.
- Mutation checks: a `# noqa` in the seed fails `prek run`; at product tier, a fake secret fails gitleaks and a stale `# pyright: ignore[...]` fails pyright.

Update test: generate from a temp tag on an older commit, change one pin by hand (as Dependabot would), tag HEAD, run `copier update`. The changed pin survives, or the conflict appears as markers and `check-merge-conflict` fails.

The test job joins `self-test` (Ubuntu).

## Not in scope

- Retrofitting existing callers (C4).
- vps-ai-manager: keep-or-delete and security fixes first (Phlares/vps-ai-manager#40).
- Publication tier, Zig, TypeScript typecheck, eslint (no template user runs eslint).
- Repo settings automation (C13).

## Open for the builder

- setup-uv version and cache input names; whether `setup-python`'s pip cache stays on when `uv-version` is set.
- Exact ruff `ruff.toml` layout for prototype (`extend-select`) vs product (`select`).
- The node seed for the oxlint mutation check.
