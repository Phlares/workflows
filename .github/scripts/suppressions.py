"""Count suppression markers in tracked files and hold them to a baseline.

Each MARKERS row is (name, file globs, regex, kind). A row matches only in
files its globs select, and its regex runs on each line. A regex requires
the comment opener before the marker, as the tools themselves do, so a
marker inside a string with no opener does not count. The exception is
gitleaks allow, which gitleaks honours anywhere on a line.
"""

import fnmatch
import os
import re
import subprocess
import sys

COUNT, FORBID = "count", "forbid"
BASELINE = ".suppressions"

PY = ("*.py", "*.pyi")
JS = (
    "*.js",
    "*.mjs",
    "*.cjs",
    "*.jsx",
    "*.ts",
    "*.mts",
    "*.cts",
    "*.tsx",
    "*.vue",
    "*.svelte",
)
CSS = ("*.css", "*.scss", "*.less")
SH = ("*.sh", "*.bash")
ACTIONLINT = (".github/actionlint.yaml", ".github/actionlint.yml")
ALL = ("*",)

H = r"#\s*"
C = r"(?://+|/\*+)\s*"
TEST = r"\b(?:it|test|describe|suite)\."
# A directive's rule list starts after spaces with a letter or a scope.
# The (?![-\w]) stops "-next-line" from being skipped to fake a bare form.
RULE = r"(?:-next-line|-line)?[ \t]+[\w@]"
NO_RULE = r"(?:-next-line|-line)?(?![-\w])(?![ \t]+[\w@])"
PYTEST = "pytest"  # joined at use: the plain dotted names would count here
GITLEAKS = "gitleaks"  # joined at use: the plain marker would count here
ENTRY = r"^[ \t]*[^\s#]"


def _disable(tool, globs):
    return [
        (f"{tool}-disable", globs, C + tool + "-disable" + RULE, COUNT),
        (f"bare {tool}-disable", globs, C + tool + "-disable" + NO_RULE, FORBID),
    ]


MARKERS = [
    (name, globs, re.compile(rx), kind)
    for name, globs, rx, kind in [
        ("type: ignore", PY, H + r"type:\s*ignore\[", COUNT),
        ("bare type: ignore", PY, H + r"type:\s*ignore(?!\[)", FORBID),
        ("pyright: ignore", PY, H + r"pyright:\s*ignore\[", COUNT),
        ("bare pyright: ignore", PY, H + r"pyright:\s*ignore(?!\[)", FORBID),
        ("noqa", PY, H + r"(?i:noqa):", COUNT),
        ("blanket noqa", PY, H + r"(?i:noqa)(?!:)", FORBID),
        ("ruff: noqa", PY, H + r"(?:ruff|flake8):\s*noqa:", COUNT),
        ("blanket ruff: noqa", PY, H + r"(?:ruff|flake8):\s*noqa(?!:)", FORBID),
        ("pragma: no cover", PY, H + r"pragma:\s*no\s+cover", COUNT),
        ("fmt: off", PY, H + r"fmt:\s*off", COUNT),
        ("fmt: skip", PY, H + r"fmt:\s*skip", COUNT),
        (PYTEST + ".mark.skip", PY, r"\bpytest\.mark\.skip(?:if)?\b", COUNT),
        (PYTEST + ".mark.xfail", PY, r"\bpytest\.mark\.xfail\b", COUNT),
        (PYTEST + ".skip", PY, r"\bpytest\.(?:skip|xfail)\(", COUNT),
        (PYTEST + ".importorskip", PY, r"\bpytest\.importorskip\(", COUNT),
        *_disable("eslint", JS),
        *_disable("oxlint", JS),
        ("biome-ignore", JS + CSS, C + r"biome-ignore", COUNT),
        ("@ts-ignore", JS, C + r"@ts-ignore", COUNT),
        ("@ts-expect-error", JS, C + r"@ts-expect-error", COUNT),
        ("@ts-nocheck", JS, C + r"@ts-nocheck", COUNT),
        ("istanbul ignore", JS, C + r"istanbul\s+ignore", COUNT),
        ("c8 ignore", JS, C + r"c8\s+ignore", COUNT),
        ("v8 ignore", JS, C + r"v8\s+ignore", COUNT),
        (".skip", JS, TEST + r"skip\b", COUNT),
        (".skipIf", JS, TEST + r"(?:skipIf|runIf)\b", COUNT),
        (".todo", JS, TEST + r"todo\b", COUNT),
        (".only", JS, TEST + r"only\b", FORBID),
        *_disable("stylelint", CSS),
        ("shellcheck disable", SH, H + r"shellcheck\s+disable=", COUNT),
        ("actionlint ignore", ACTIONLINT, r"^\s*ignore:", COUNT),
        # gitleaks honours the marker anywhere on a line, so no opener.
        ("gitleaks allow", ALL, GITLEAKS + ":allow", COUNT),
        (".gitleaksignore entry", (".gitleaksignore",), ENTRY, FORBID),
        (".gitleaks.toml entry", (".gitleaks.toml",), ENTRY, FORBID),
    ]
]


def scan(paths):
    """Return ({(path, name): [line, ...]}, [(path, line, name), ...] forbidden)."""
    counts, forbidden = {}, []
    for path in paths:
        rows = [m for m in MARKERS if any(fnmatch.fnmatchcase(path, g) for g in m[1])]
        if not rows or not os.path.isfile(path):
            continue
        with open(path, "rb") as f:
            text = f.read().decode("utf-8", "replace")
        for n, line in enumerate(text.split("\n"), 1):
            for name, _, rx, kind in rows:
                for _ in rx.finditer(line):
                    if kind == FORBID:
                        forbidden.append((path, n, name))
                    else:
                        counts.setdefault((path, name), []).append(n)
    return counts, forbidden


def tracked():
    out = subprocess.run(
        ["git", "ls-files", "-z"], capture_output=True, check=True
    ).stdout
    return [p for p in out.decode("utf-8").split("\0") if p]


def load(text):
    """Parse .suppressions: ({(path, name): (count, reason)}, [error, ...])."""
    counted = {m[0] for m in MARKERS if m[3] == COUNT}
    baseline, errors = {}, []
    for n, line in enumerate(text.split("\n"), 1):
        if not line:
            continue
        fields = line.split("\t", 3)
        if len(fields) != 4:
            errors.append(f"{BASELINE}:{n}: want path<TAB>marker<TAB>count<TAB>reason")
            continue
        path, name, count, reason = fields
        if name not in counted:
            errors.append(f"{BASELINE}:{n}: {name!r} is not a counted marker")
        elif not count.isdigit() or int(count) < 1:
            errors.append(f"{BASELINE}:{n}: count must be a whole number of at least 1")
        elif not reason.strip():
            errors.append(f"{BASELINE}:{n}: no reason given")
        elif (path, name) in baseline:
            errors.append(f"{BASELINE}:{n}: duplicate line for {path} {name}")
        else:
            baseline[(path, name)] = (int(count), reason)
    return baseline, errors


def main():
    args = sys.argv[1:]
    # Windows pipes default to CRLF and the ANSI code page.
    sys.stdout.reconfigure(newline="\n", encoding="utf-8", errors="replace")
    if "--markers" in args:
        print("\n".join(m[0] for m in MARKERS))
        return 0
    top = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"], capture_output=True, check=True
    )
    os.chdir(top.stdout.decode().strip())
    counts, forbidden = scan(tracked())
    try:
        with open(BASELINE, encoding="utf-8-sig") as f:
            baseline, errors = load(f.read())
    except FileNotFoundError:
        baseline, errors = {}, []
    for path, n, name in forbidden:
        errors.append(f"{path}:{n}: {name} always fails")
    for key, lines in sorted(counts.items()):
        allowed = baseline.get(key, (0, ""))[0]
        if len(lines) > allowed:
            errors.append(f"{key[0]}: {key[1]}: {len(lines)} > baseline {allowed}")
            errors.extend(f"  {key[0]}:{n}: {key[1]}" for n in lines)
    lowered = {}
    for key, (allowed, reason) in sorted(baseline.items()):
        found = len(counts.get(key, ()))
        if found < allowed:
            print(f"{key[0]}: {key[1]}: {allowed} -> {found}")
        if min(found, allowed):
            lowered[key] = (min(found, allowed), reason)
    stale = lowered != baseline
    # Lower only on an otherwise clean run: a bad line, or a rename that
    # shows as one count up and one down, would lose its reason.
    if stale and not errors:
        write(lowered)
        print(f"{BASELINE} {'lowered' if lowered else 'removed'}; stage it")
    if errors:
        print("\n".join(errors))
    return 1 if errors or (stale and "--update" not in args) else 0


def write(baseline):
    if not baseline:
        os.remove(BASELINE)
        return
    with open(BASELINE, "w", encoding="utf-8", newline="\n") as f:
        f.writelines(
            f"{path}\t{name}\t{count}\t{reason}\n"
            for (path, name), (count, reason) in baseline.items()
        )


if __name__ == "__main__":
    sys.exit(main())
