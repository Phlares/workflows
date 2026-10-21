"""Fail when an installed distribution's license is outside the allowlist.

Run it with the project's interpreter after `uv sync --locked --no-dev`, so it
sees exactly what the project ships. The license is the PEP 639
License-Expression when present; otherwise every license classifier, joined
with AND; otherwise the older License field, read as an SPDX expression.
Exceptions are pinned to one version in pyproject.toml:

    [tool.licenses.exceptions]
    "name==1.2.3" = "why it is allowed"
"""

import re
import sys
from importlib import metadata

import tomllib  # Python 3.11+

ALLOW = {"mit", "mit-0", "bsd-2-clause", "bsd-3-clause", "0bsd", "isc"}
ALLOW |= {"apache-2.0", "psf-2.0", "zlib", "cc0-1.0", "unlicense"}
ALLOW |= {"mit-cmu", "cnri-python"}  # notice-only: pillow, regex
# Allowed classifiers only; any other classifier fails under its own name.
# "BSD License" names no variant; both variants are allowed.
CLASSIFIERS = {
    "MIT License": "MIT",
    "MIT No Attribution License (MIT-0)": "MIT-0",
    "BSD License": "BSD-3-Clause",
    "ISC License (ISCL)": "ISC",
    "Apache Software License": "Apache-2.0",
    "Python Software Foundation License": "PSF-2.0",
    "zlib/libpng License": "Zlib",
    "The Unlicense (Unlicense)": "Unlicense",
}
LICENSE_CLASSIFIER = "License :: "


def norm(name):
    return re.sub(r"[-_.]+", "-", name).lower()


def allowed(expr):
    """Evaluate an SPDX expression; raise ValueError when it does not parse."""
    tokens = re.findall(r"[()]|[^\s()]+", expr)
    pos = 0

    def peek():
        return tokens[pos].upper() if pos < len(tokens) else None

    def take():
        nonlocal pos
        if pos == len(tokens):
            raise ValueError("ends early")
        pos += 1
        return tokens[pos - 1]

    def either():
        ok = both()
        while peek() == "OR":
            take()
            ok = both() or ok
        return ok

    def both():
        ok = one()
        while peek() == "AND":
            take()
            ok = one() and ok
        return ok

    def one():
        tok = take()
        if tok == "(":
            ok = either()
            if take() != ")":
                raise ValueError("unclosed (")
            return ok
        if tok == ")" or tok.upper() in ("AND", "OR", "WITH"):
            raise ValueError(f"unexpected {tok}")
        if peek() == "WITH":
            take()
            take()
        return tok.removesuffix("+").lower() in ALLOW

    ok = either()
    if pos != len(tokens):
        raise ValueError(f"unexpected {tokens[pos]}")
    return ok


def license_of(dist):
    """Return (SPDX expression, text to show when it fails)."""
    expr = dist.metadata.get("License-Expression")
    if expr:
        return expr, expr
    found = [
        c.rsplit(" :: ", 1)[1]
        for c in dist.metadata.get_all("Classifier") or ()
        if c.startswith(LICENSE_CLASSIFIER)
    ]
    if found:
        # An unknown classifier becomes a LicenseRef, which never passes.
        spdx = [CLASSIFIERS.get(c, "LicenseRef-unknown") for c in found]
        return " AND ".join(spdx), "; ".join(found)
    # Free text: passes only when it happens to be an allowed SPDX expression.
    text = (dist.metadata.get("License") or "").strip()
    return text, text.splitlines()[0][:80] if text else "no license metadata"


def main():
    with open("pyproject.toml", "rb") as f:
        project = tomllib.load(f)
    own = norm(project.get("project", {}).get("name", ""))
    exceptions = project.get("tool", {}).get("licenses", {}).get("exceptions", {})
    pinned = {norm(k.split("==")[0]) + "==" + k.split("==")[-1]: k for k in exceptions}
    used, errors, seen = set(), [], set()
    for dist in metadata.distributions():
        name, version = dist.metadata["Name"], dist.version
        if norm(name) in seen or norm(name) == own:
            continue
        seen.add(norm(name))
        expr, shown = license_of(dist)
        try:
            ok = bool(expr) and allowed(expr)
        except ValueError as e:
            ok, shown = False, f"{shown} (does not parse: {e})"
        key = f"{norm(name)}=={version}"
        if key in pinned:
            used.add(key)
            if ok:
                errors.append(f"unused exception: {pinned[key]} is allowed without it")
            continue
        if not ok:
            errors.append(f"{name} {version}: {shown}")
    errors += [f"unused exception: {pinned[k]}" for k in pinned.keys() - used]
    if errors:
        print("\n".join(errors))
        print(
            "Allowed: "
            + ", ".join(sorted(ALLOW))
            + ". Pin others in [tool.licenses.exceptions]."
        )
        return 1
    print(f"licenses ok: {len(seen)} package{'s' * (len(seen) != 1)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
