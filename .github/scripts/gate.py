"""Run a repo's check list in order and write a summary."""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:
    print("gate: needs Python 3.11 or later", file=sys.stderr)
    raise SystemExit(2) from None

LIST = "gate.toml"
LOCAL = "gate.local.toml"
NAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")
COLOUR = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")


def stop(msg):
    print(f"gate: {msg}", file=sys.stderr)
    raise SystemExit(2)


def git(*args):
    try:
        done = subprocess.run(
            ["git", *args], check=True, capture_output=True, encoding="utf-8"
        )
    except (OSError, subprocess.CalledProcessError) as e:
        stop(f"git {' '.join(args)}: {getattr(e, 'stderr', '') or e}".strip())
    return done.stdout.strip()


def emit(text):
    """Write bytes: text mode would add CR on Windows and reorder around check output."""
    sys.stdout.buffer.write(text.encode() + b"\n")
    sys.stdout.buffer.flush()


def only(keys, found, where):
    if extra := sorted(set(found) - keys):
        stop(f'{where}: unknown key "{extra[0]}"')


def parse(check, source):
    name = check.get("name")
    if not (isinstance(name, str) and NAME.fullmatch(name)):
        stop(f"{source}: name {name!r} does not match {NAME.pattern}")
    where = f'{source}: check "{name}"'
    only({"name", "run", "count"}, check, where)
    if not isinstance(check.get("run"), str):
        stop(f"{where}: run must be a string")
    pair = check.get("count", [])
    if not (
        isinstance(pair, list)
        and len(pair) in (0, 2)
        and all(isinstance(p, str) for p in pair)
    ):
        stop(f"{where}: count must be two patterns")
    try:
        patterns = [re.compile(p) for p in pair]
    except re.error as e:
        stop(f"{where}: count pattern: {e}")
    return {"name": name, "run": check["run"], "count": patterns, "source": source}


def read(source):
    try:
        with open(source, "rb") as f:
            data = tomllib.load(f)
    except (OSError, tomllib.TOMLDecodeError) as e:
        stop(f"{source}: {e}")
    only({"check"}, data, source)
    checks = data.get("check")
    if not (
        isinstance(checks, list) and checks and all(isinstance(c, dict) for c in checks)
    ):
        stop(f"{source}: no checks")
    return [parse(c, source) for c in checks]


def load():
    checks = read(LIST)
    if os.path.exists(LOCAL):
        # Exit 1 covers a tracked file too: git ignores only untracked paths.
        if subprocess.run(["git", "check-ignore", "-q", LOCAL], check=False).returncode:
            stop(f"{LOCAL} is not ignored by git")
        checks += read(LOCAL)
    # Folded: the name is a log file name, and Windows folds file names.
    names = [c["name"].casefold() for c in checks]
    for check, name in zip(checks, names):
        if names.count(name) > 1:
            stop(f'two checks are named "{check["name"]}"')
    return checks


def run_check(check, logdir, bash):
    emit(f"gate: {check['name']}")
    log = f"{check['name']}.log"
    pair = check["count"]
    counts = [0] * len(pair)
    start = time.monotonic()
    with open(logdir / log, "wb") as f:
        proc = subprocess.Popen(
            [bash, "-eo", "pipefail", "-c", check["run"]],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        raw = b"\n"
        for raw in proc.stdout:
            f.write(raw)
            sys.stdout.buffer.write(raw)
            sys.stdout.buffer.flush()
            text = COLOUR.sub("", raw.decode(errors="replace")).rstrip("\r\n")
            counts = [n + bool(p.search(text)) for n, p in zip(counts, pair)]
        code = proc.wait()
    if not raw.endswith(b"\n"):
        emit("")
    # No pair: both tests hold for the empty list. A pair: equal and not zero.
    passed = code == 0 and len(set(counts)) <= 1 and all(counts)
    return {
        "name": check["name"],
        "source": check["source"],
        "status": "pass" if passed else "fail",
        "exit": code,
        "count": counts or None,
        "seconds": round(time.monotonic() - start, 3),
        "log": log,
    }


def fragment(result):
    text = f"{result['name']} {'ok' if result['status'] == 'pass' else 'FAIL'}"
    if result["exit"]:
        text += f" exit {result['exit']}"
    if result["count"]:
        a, b = result["count"]
        text += f" {a}{'=' if a == b else '!='}{b}"
    return text


def main(argv=None):
    parser = argparse.ArgumentParser(prog="gate", description=__doc__)
    parser.add_argument("check", nargs="*", help="run only these checks")
    args = parser.parse_args(argv)
    root, gitdir, commit = git(
        "rev-parse", "--show-toplevel", "--absolute-git-dir", "HEAD"
    ).splitlines()
    os.chdir(root)
    logdir = Path(gitdir) / "gate"
    # A run that stops early must not leave an earlier run's result behind.
    (logdir / "summary.json").unlink(missing_ok=True)
    clean = not git("status", "--porcelain")
    checks = load()
    names = [c["name"] for c in checks]
    wanted = set(args.check) or set(names)
    if unknown := sorted(wanted - set(names)):
        stop(f"no check named {', '.join(unknown)}; the list has {', '.join(names)}")
    # Windows resolves a bare "bash" to System32 (WSL) before PATH; which()
    # follows PATH, so a run from Git Bash gets Git's bash.
    bash = shutil.which("bash") or stop("bash is not on PATH")
    logdir.mkdir(exist_ok=True)
    results = [run_check(c, logdir, bash) for c in checks if c["name"] in wanted]
    passed = all(r["status"] == "pass" for r in results)
    line = "gate: {} {}/{} checks at {} {}: {}".format(
        "PASS" if passed else "FAIL",
        len(results),
        len(checks),
        commit[:12],
        "clean" if clean else "dirty",
        ", ".join(map(fragment, results)),
    )
    summary = {
        "schema": 1,
        "commit": commit,
        "clean": clean,
        "status": "pass" if passed else "fail",
        "line": line,
        "checks": results,
        "skipped": [n for n in names if n not in wanted],
    }
    (logdir / "summary.json").write_text(
        json.dumps(summary, indent=2) + "\n", encoding="utf-8", newline="\n"
    )
    emit(line)
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
