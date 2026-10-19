# Secrets check in the template (gitleaks)

Date: 2026-10-19. Status: draft for review. Issue: Phlares/workflows#34.
Builds on: `2026-10-19-template-uv-design.md` (template, C8 is replaced here), #28 (suppression guard).

## Goal

Every repo generated from the template blocks hardcoded secrets at commit time and in CI. This covers private repos, where GitHub secret scanning is not available on a personal account.

Success means:

- A seeded test key fails the commit hook in every generated tier and language set (template test).
- The same key, committed without the hook, fails the generated `lint` job's command (template test).
- `gitleaks:allow` counts toward the suppression baseline, and any entry in `.gitleaksignore` or `.gitleaks.toml` fails the guard (guard tests).
- A warm `lint` job skips the gitleaks Go build (about 23 s cold on Ubuntu).
- Release v1.8.0 ships all of the above.

## Why

- VoxGarbler and portfolio (product tier) are private, so nothing scans them for secrets today.
- vps-ai-manager held a hardcoded password in client JS (Phlares/vps-ai-manager#40), and nothing caught it. gitleaks flags 42 history hits there (41 `generic-api-key`, 1 `jwt`), in the files #40 names.

## Spike results (2026-10-19, throwaway)

gitleaks v8.30.1 (`83d9cd684c87d95d656c1458ef04895a7f1cbd8e`, the latest release), prek 0.5.5.

| Check | Windows | Ubuntu CI |
|---|---|---|
| prek builds the `language: golang` hook | yes; cold 54 s, prek fetched its own Go | yes; cold 23 s, runner Go 1.24 |
| seeded `ghp_` key fails the hook | yes (Git Bash, PowerShell, `git commit`) | yes |
| `# gitleaks:allow` skips the line | yes | — |
| committed key, upstream entry, `--all-files` | — | passes (scans nothing) |
| committed key, history entry (S2) | yes | yes, also in a depth-1 clone |

- Hook time on VoxGarbler: about 0.3 s per commit with prek overhead. A depth-1 tree scan takes 0.6 s (4.75 MB).
- Full-history scans: VoxGarbler 0 hits (915 commits, 1.8 s), portfolio 0 hits (785 commits, 5.6 s).
- The Ubuntu prek store after the build is 45 MB (23 MB compressed). Go's module cache (422 MB) and build cache (180 MB) sit outside it, in `~/go` and `~/.cache/go-build`.
- `gitleaks dir` with more than one path scans the whole working folder instead, so it cannot take prek's file list.

## Decisions

| # | Decision | Why |
|---|---|---|
| S1 | Tool: gitleaks (MIT), hook repo `gitleaks/gitleaks`, rev `83d9cd684c87d95d656c1458ef04895a7f1cbd8e  # frozen: v8.30.1`, built by prek (`language: golang`). Dependabot's `pre-commit` group moves it. | Decision 2026-10-19. TruffleHog is AGPL, slower, and its verification sends found keys to the providers' APIs. detect-secrets' baseline file is not needed: both product histories are clean. |
| S2 | One hook block with two entries. `id: gitleaks` (upstream entry, staged changes) runs on commit. A second `id: gitleaks` with `alias: gitleaks-history`, `entry: gitleaks git --redact --verbose` and `stages: [manual]` scans the commits in the clone. | The upstream entry is `gitleaks git --pre-commit --staged`. CI has nothing staged, so it alone passes on a committed secret (spike). |
| S3 | The template `lint` job runs `prek run --all-files --hook-stage manual --show-diff-on-failure`. Hooks with no `stages` run in the manual stage too, so every hook still runs once, plus the history entry. | One prek call. The `check.yml` checkout is depth 1, so the history entry scans the HEAD tree (for a PR, the merge result). Run locally, it scans the full history (2–6 s on the spiked repos). |
| S4 | All tiers. No tier condition in the template. | Decision 2026-10-19. 0.3 s per commit. The one real leak (#40) was in a prototype-grade repo. |
| S5 | `gitleaks:allow` is a COUNT row in the guard named `gitleaks allow` (no colon, so `.suppressions` lines do not match it): all tracked files, regex `gitleaks:allow` with no comment opener. Each kept site gets a `.suppressions` line with its reason. | Decision 2026-10-19. gitleaks honours the marker anywhere on the line, so the row must match the same way. Row name: builder's call. |
| S6 | `.gitleaksignore` is a FORBID row: any line that is not blank or a `#` comment fails. | Decision 2026-10-19. Its fingerprints carry no reason, so they bypass the baseline. `gitleaks:allow` plus a reason is the one way to suppress. |
| S6b | `.gitleaks.toml` is a FORBID row too: any line that is not blank or a `#` comment fails. `--config` and `GITLEAKS_CONFIG` stay an accepted gap. | Decision 2026-10-19. An allowlist there skips paths or patterns with no reason, and a file without `[extend] useDefault = true` replaces every built-in rule. A repo that needs custom rules changes the guard on purpose. The flag and the env var can only be set in hook args or CI files, which show in a reviewed diff. |
| S7 | `check.yml` and the `setup` action gain `prek-cache` (boolean, default false). When true, the setup action sets `PREK_HOME` to `~/.cache/prek` for the job and runs `actions/cache` (pinned by hash, v6.1.0 `55cc8345863c7cc4c66a329aec7e433d2d1c52a9`) on that path. Key: `prek-v1-<runner.os>-<runner.arch>-<python-version>-<hash of <working-directory>/.pre-commit-config.yaml and <working-directory>/uv.lock>`. The `uv.lock` part tracks the prek version (lint group); a repo with no `uv.lock` hashes the config alone. No `restore-keys`. The template `lint` job sets `prek-cache: true`. | Decision 2026-10-19. Only the job that runs prek fills the store, so only it opts in. This matches the setup action's one-input-per-tool idiom and `setup-uv`'s explicit cache switch. The key follows `j178/prek-action`. `PREK_HOME` makes the path the same on every OS. With no `restore-keys`, a key never restores a near match, so a stale store is never saved under a new key. A hook bump costs one cold build. |
| S8 | `actions/cache` saves only on job success (its `post-if: success()`). Pushes to the default branch warm the cache for every PR. Caches saved on a PR run stay scoped to that PR. | GitHub cache rules: 10 GB per repo, entries unused for 7 days are evicted. |
| S9 | Callers adopt in their own follow-up PRs. This repo does not add gitleaks to its own hooks. | Decision 2026-10-19. This repo is public, so GitHub secret scanning already covers it. |

## Template changes

`template/.pre-commit-config.yaml.jinja`, after `check-merge-conflict` and before the language hooks:

```yaml
  - repo: https://github.com/gitleaks/gitleaks
    rev: 83d9cd684c87d95d656c1458ef04895a7f1cbd8e  # frozen: v8.30.1
    hooks:
      - id: gitleaks
      # The lint job runs the manual stage: CI has nothing staged, so the
      # entry above scans nothing there. A depth-1 checkout scans HEAD's tree.
      - id: gitleaks
        alias: gitleaks-history
        entry: gitleaks git --redact --verbose
        stages: [manual]
```

`template/.github/workflows/ci.yml.jinja`, `lint` job: add `prek-cache: true` and change `run` to `uv run --no-sync prek run --all-files --hook-stage manual --show-diff-on-failure`.

## Tests

`tests/template.test.sh`, for every tier and language set:

- Hook order includes `id: gitleaks id: gitleaks` after `check-merge-conflict`.
- `lint` job `run` and `prek-cache` values.
- Mutation, commit stage: a staged file with a seeded key fails `prek run gitleaks`.
- Mutation, CI: a commit made with hooks off that holds a seeded key fails the generated `lint` job's run command. The test then removes the commit.
- `lint passes on seeds` keeps passing with the history entry in the run.

The seeded key is built at test run time (for example `ghp_` plus 36 characters from a fixed mixed pattern). No literal key sits in this repo, so GitHub push protection and later adopters' own scans stay quiet.

`tests/suppressions.test.sh`:

- The test file builds the marker string from parts, as it does for `shellcheck`.
- A sample line for the `gitleaks allow` COUNT row (in a file type no other row selects, such as `.env.example`, to prove the all-files glob).
- Sample lines for the `.gitleaksignore` and `.gitleaks.toml` FORBID rows, and a check that blank and `#` lines in both pass.
- The guard's own source builds the marker string from parts (as `PYTEST` does), so the row does not count itself.

`prek-cache` in `check.yml` and the setup action: `actionlint` passes, and `self-test` runs a `check.yml` caller with `prek-cache: true` and `working-directory` set to a new fixture (`fixtures/prek/`, holding a `.pre-commit-config.yaml` with the gitleaks hook) that runs `prek run --all-files --hook-stage manual`. Before tagging v1.8.0, a rerun of the PR's CI must show a cache hit and no Go build in that job's log (hand check; a PR run can restore its own PR-scoped cache). Builder's call.

## Docs and release

- README: `prek-cache` in Inputs. Template: the gitleaks hook and the manual-stage lint run. Suppression guard: the three new rows, and that `gitleaks:allow` is matched in every tracked file, `*.md` included.
- The `gitleaks:allow` row scans this repo's own docs too. Each doc that names the marker gets a `.suppressions` line ("names the marker in docs").
- `pyproject.toml` version 1.8.0, tag `v1.8.0`, release note listing the new `prek-cache` input.

## Non-goals

- Key verification (TruffleHog) or a scheduled full-history scan.
- Adopting the hook in VoxGarbler, portfolio or other callers (S9).
- Scanning commits a PR added and then removed: the CI scan sees the merge-result tree, not each commit.

## Anti-goals

- An unpinned gitleaks binary, or a `language: system` hook.
- A suppression path with no reason.
- A cache that restores in jobs that never run prek.

## Left to the builder

- Exact regex text for the S6 and S6b FORBID rows and the seeded-key generator.
- How the CI mutation test drops its commit (reset or a throwaway clone).
- Wording of comments and README text.
