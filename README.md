# workflows

Reusable GitHub Actions jobs: `check.yml` for checks (lint, typecheck,
tests) and `claude-fix.yml` for one Claude fix run per issue or PR. Release,
publish and deploy jobs stay in each repo.

## Use

```yaml
jobs:
  test:
    uses: Phlares/workflows/.github/workflows/check.yml@<full sha> # v1.4.0
    with:
      node-version: "24"
      install: npm ci
      run: npm test
```

Pin the full commit hash with the tag as a comment. Dependabot
(`github-actions` ecosystem) opens the bump PR when a new tag ships.

The check is named `<caller job> / <name> (<shard>)`, for example
`test / check (1)`. Use that name for required checks.

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `name` | `check` | Job name and failure artifact prefix. Unique per caller workflow: two jobs with one name overwrite each other's artifact |
| `runs-on` | `ubuntu-latest` | Runner label |
| `node-version` | empty | Empty = not installed. npm cache needs `<working-directory>/package-lock.json`; without it the job fails in step `setup` |
| `python-version` | empty | Empty = not installed. pip cache needs `pyproject.toml` or `requirements*.txt` in `<working-directory>`; without them the job fails in step `setup` |
| `zig-version` | empty | Empty = not installed |
| `working-directory` | `.` | Where `install` and `run` execute |
| `install` | empty | Commands run before `run` |
| `run` | required | Commands; stops at the first failure |
| `env` | empty | `KEY=VALUE` lines exported for `install` and `run`. Blank and `#` lines are skipped. `NODE_OPTIONS` works |
| `shards` | `[1]` | JSON array, usually integers; each shard gets `SHARD_INDEX` (the array value) and `SHARD_TOTAL` (the array length) |
| `timeout-minutes` | `15` | Limit for `install` and for `run`, each |

`PYTHONUNBUFFERED=1` is set by default so a killed test keeps its output.

## Examples

Sharded JS:
```yaml
    with:
      node-version: "24"
      install: npm ci
      run: npm run test:ci -- --shard=$SHARD_INDEX/$SHARD_TOTAL
      shards: "[1,2,3]"
```

Python with a Zig build step on Windows:
```yaml
    with:
      runs-on: windows-latest
      python-version: "3.12"
      zig-version: 0.16.0
      env: |
        PYTHONUTF8=1
      install: pip install -e ".[dev]"
      run: |
        (cd core && zig build -Doptimize=ReleaseSafe)
        pytest tests/unit
```

Zig only:
```yaml
    with:
      zig-version: 0.16.0
      working-directory: core
      run: |
        zig fmt --check build.zig src
        zig build test
```

## On failure

The job writes a summary, one `::error` annotation, and an artifact
`ci-failure-<name>-<shard>` holding `report.json` (schema 1): repo, PR number,
commit, run URL, job, shard, failing step (`setup`, `install` or `run`) and the
last 40 log lines with colour codes removed. A timeout counts as a failure of
the step that ran out of time.

- The annotation shows the first of those 40 lines with a failure word, else
  the last line. A failure word is `error`, `exception`, `fail`, `assert` or
  `panic` at the start of a word, or `error` or `exception` at the end of one
  (`TypeError`), in any case. `pkg-fail` and `test_fail.py` do not count.
- `shard` in `report.json` is a number when the shard value is an integer,
  else a string.
- In the artifact name, every character outside `A-Z a-z 0-9 . _ -` becomes
  `-`: `name: "unit/py"` uploads `ci-failure-unit-py-1`.

## claude-fix

One fix run per request. Adding the `claude-fix` label to an issue or PR
starts it; it ends in a draft PR (issue) or one commit on the PR branch (PR).
Nothing merges and nothing is pushed to the default branch.

```yaml
name: claude-fix
on:
  issues: { types: [labeled] }
  pull_request: { types: [labeled] }
  # Auto fix (opt-in): uncomment.
  # workflow_run: { workflows: [CI], types: [completed] }
permissions: { contents: write, pull-requests: write, issues: write, actions: read, id-token: write }
jobs:
  fix:
    if: github.event.label.name == 'claude-fix' || github.event.workflow_run.conclusion == 'failure'
    uses: Phlares/workflows/.github/workflows/claude-fix.yml@<full sha> # v1.4.0
    with:
      node-version: "24"
      install: npm ci
      test-command: npx vitest run
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

Setup per repo: install the Claude GitHub App, add the
`CLAUDE_CODE_OAUTH_TOKEN` secret (from `claude setup-token`), and create the
five labels below.

| Input | Default | Meaning |
|---|---|---|
| `model` | `opus` | Model alias |
| `effort` | `medium` | Reasoning effort (`low`, `medium`, `high`, ...); empty = model default |
| `max-turns` | `50` | Turn limit for one run |
| `timeout-minutes` | `20` | Limit for the fix step and for `install` |
| `runs-on` | `ubuntu-latest` | Runner label |
| `node-version`, `python-version`, `zig-version`, `working-directory`, `install`, `env` | as `check.yml` | Setup before tests |
| `test-command` | empty | Command Claude may run with specific test names, in PR runs on a collaborator's PR only. Empty = no setup and no tests in the fix job |
| `auto-tries` | `2` | Auto fix tries per PR. `0` = stop on the first auto failure |

| Label | Meaning |
|---|---|
| `claude-fix` | Request one run. The run removes it; add it again to retry |
| `owner:local` | A local session owns fixes (set when it opens the PR) |
| `owner:cloud` | A cloud session owns fixes |
| `owner:action` | A `claude-fix` run is working |
| `needs-human` | Auto fix stopped at `auto-tries`; auto runs skip the PR until it is removed |

Rules:
- `test-command` runs from the repo root, only in PR runs on a PR written by
  a collaborator with no commits from other bots. Issue runs and bot PRs
  (Dependabot, Renovate) never install or run
  code: injected issue text or a bumped package's install script cannot run
  with the App token. Claude may
  call it only with test names; CI runs the full suite after the push.
- The caller file must be on the default branch before labels work: the
  token exchange compares it with the default branch. After a caller change,
  a PR opened before it needs the default branch merged in; until then its
  runs skip with "Claude did not run".
- Auto fix: uncomment `workflow_run` and list the CI workflow by its `name:`.
  It skips non-PR runs, forks, draft PRs (except Claude's own), PRs with an
  `owner:*` or `needs-human` label, commits pushed by a bot other than
  `claude[bot]`, and commits it already tried. The try is marked by a hidden
  line in the outcome comment from `github-actions[bot]`.
- Auto retry: a fix that still fails CI gets another auto try, up to
  `auto-tries` per PR. At the cap, the run posts one comment that mentions the
  PR author (the repo owner when the author is a bot) and adds `needs-human`.
  Label runs always run and do not count toward the cap.
- Issue runs take only issues written by collaborators (`OWNER`, `MEMBER`,
  `COLLABORATOR`). Other issues get a "Not run" comment. Text GitHub does not
  render (HTML comments, link reference lines, zero-width characters) is
  removed before Claude reads the issue: the person who added the label never
  saw it.
- On PR runs, files Claude Code reads at start-up (`.claude/`, `.mcp.json`,
  `CLAUDE.md` and the rest of `fix-paths.sh`) are reset to the default branch
  copies first, on auto runs too: a PR cannot plant a hook.
- Claude edits only inside the repo folder and reads only the repo and its
  task files. A run never changes `.github/`. The publish step also refuses unknown
  `.git/config` keys and an `origin` that is not this repo, and leaves out
  `CLAUDE.md`, `.claude/` and the other files the action resets on PR runs.
- Cloud hand-off: run `/autofix-pr` on the PR branch, then
  `gh pr edit <n> --add-label owner:cloud --remove-label owner:local`.

Both workflows fetch this repo into `.wf/` at the called commit. It holds
only `.github/actions/` and `.github/scripts/`, and git ignores it.

## Suppression guard

A prek hook that counts suppression comments in tracked files and fails
when a count rises above the repo's `.suppressions` baseline. Add it to
`.pre-commit-config.yaml`; the `lint` job and the commit hook then run it.
Dependabot's `pre-commit` updates move `rev`.

```yaml
  - repo: https://github.com/Phlares/workflows
    rev: <full sha>  # frozen: v1.5.0
    hooks:
      - id: suppressions
```

- What counts: the `MARKERS` table in `.github/scripts/suppressions.py`.
  Each row is a name, file globs, a regex, and a kind. The regex needs the
  comment opener before the marker, so text in a string with no opener
  does not count. Test skips (`.skip`, `.skipIf`, `pytest.mark.skip`,
  `pytest.importorskip`, …) count.
- Not scanned: files no row's globs select, such as `*.md` and files with
  no extension.
- Always fail, whatever the baseline: forms with no rule list (bare
  `type: ignore`, `pyright: ignore` without `[rule]`, blanket `noqa`,
  `ruff: noqa` without codes, `eslint-disable`, `oxlint-disable` or
  `stylelint-disable` with no rule) and `.only`.
- `.suppressions`: one `path<TAB>marker<TAB>count<TAB>reason` line per
  kept site, with no header. `marker` is a name from `--markers`. A line
  with no reason fails. No file means a baseline of 0.
- When a count drops, the hook lowers the line (or drops it at 0), writes
  the file, and fails, like a formatter. Stage the file and commit again.
  `--update` does the same and exits 0. Nothing raises a count; a new
  kept site is a hand edit with its reason.

## Versioning

Semver tags. A breaking input change bumps the major version. Each release
note lists input changes.
