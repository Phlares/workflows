"""Run a repo's check list in order and write a summary."""

import json
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

import tomllib  # Python 3.11+

LIST = "gate.toml"
COLOUR = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")


def git(*args):
    return subprocess.run(
        ["git", *args], check=True, capture_output=True, text=True
    ).stdout.strip()


def emit(text):
    """Write bytes: text mode would add CR on Windows and reorder around check output."""
    sys.stdout.buffer.write(text.encode() + b"\n")
    sys.stdout.buffer.flush()


def load(root):
    with open(root / LIST, "rb") as f:
        checks = tomllib.load(f)["check"]
    return [
        {**c, "source": LIST, "count": [re.compile(p) for p in c.get("count", [])]}
        for c in checks
    ]


def run_check(check, root, logdir, bash):
    emit(f"gate: {check['name']}")
    log = f"{check['name']}.log"
    pair = check["count"]
    counts = [0] * len(pair)
    start = time.monotonic()
    with open(logdir / log, "wb") as f:
        proc = subprocess.Popen(
            [bash, "-eo", "pipefail", "-c", check["run"]],
            cwd=root,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        for raw in proc.stdout:
            f.write(raw)
            sys.stdout.buffer.write(raw)
            sys.stdout.buffer.flush()
            text = COLOUR.sub("", raw.decode(errors="replace")).rstrip("\r\n")
            counts = [n + bool(p.search(text)) for n, p in zip(counts, pair)]
        code = proc.wait()
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


def main():
    root = Path(git("rev-parse", "--show-toplevel"))
    logdir = Path(git("rev-parse", "--absolute-git-dir")) / "gate"
    commit = git("rev-parse", "HEAD")
    clean = not git("status", "--porcelain")
    checks = load(root)
    # A bare name would find WSL's bash before Git's on Windows; which() follows PATH.
    bash = shutil.which("bash")
    logdir.mkdir(exist_ok=True)
    results = [run_check(c, root, logdir, bash) for c in checks]
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
        "skipped": [],
    }
    (logdir / "summary.json").write_text(
        json.dumps(summary, indent=2) + "\n", encoding="utf-8", newline="\n"
    )
    emit(line)
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
