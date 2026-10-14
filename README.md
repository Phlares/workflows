# workflows

One reusable GitHub Actions job for checks: lint, typecheck, tests. Release,
publish and deploy jobs stay in each repo.

## Use

```yaml
jobs:
  test:
    uses: Phlares/workflows/.github/workflows/check.yml@<full sha> # v1.0.0
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
| `name` | `check` | Job name and failure artifact prefix. Unique per caller workflow; no `/`, `:` or `\` |
| `runs-on` | `ubuntu-latest` | Runner label |
| `node-version` | empty | Empty = not installed. npm cache needs `<working-directory>/package-lock.json` |
| `python-version` | empty | Empty = not installed. pip cache needs `pyproject.toml` or `requirements*.txt` in `<working-directory>` |
| `zig-version` | empty | Empty = not installed |
| `working-directory` | `.` | Where `install` and `run` execute |
| `install` | empty | Commands run before `run` |
| `run` | required | Commands; stops at the first failure |
| `env` | empty | `KEY=VALUE` lines exported for `install` and `run`. Blank and `#` lines are skipped. `NODE_OPTIONS` works |
| `shards` | `[1]` | JSON array of integers; each shard gets `SHARD_INDEX` and `SHARD_TOTAL` |
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

## Versioning

Semver tags. A breaking input change bumps the major version. Each release
note lists input changes.
