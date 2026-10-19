"""Print one fact about a YAML file for tests/template.test.sh.

yamlq.py FILE jobs                 sorted job ids
yamlq.py FILE job ID KEY           a job's uses, or with.KEY (runs-on defaults as check.yml)
yamlq.py FILE ecosystems           sorted package-ecosystem values
yamlq.py FILE groups ECOSYSTEM     "name:update-types|applies-to" per group
"""

import sys

import yaml

path, what, *args = sys.argv[1:]
doc = yaml.safe_load(open(path, encoding="utf-8"))
if what == "jobs":
    print(" ".join(sorted(doc["jobs"])))
elif what == "job":
    job, key = args
    j = doc["jobs"][job]
    default = "ubuntu-latest" if key == "runs-on" else ""
    print(j[key] if key == "uses" else j.get("with", {}).get(key, default))
elif what == "ecosystems":
    print(" ".join(sorted(u["package-ecosystem"] for u in doc["updates"])))
elif what == "groups":
    (u,) = [u for u in doc["updates"] if u["package-ecosystem"] == args[0]]
    print(
        " ".join(
            f"{n}:{','.join(g.get('update-types', [])) or g.get('applies-to', 'all')}"
            for n, g in u["groups"].items()
        )
    )
    print(u.get("versioning-strategy", ""))
