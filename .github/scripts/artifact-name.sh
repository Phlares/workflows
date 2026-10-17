#!/usr/bin/env bash
# Prints the failure artifact name of a check.yml job. upload-artifact refuses
# " : < > | * ? \ / and line breaks, so every character outside A-Z a-z 0-9 . _ -
# becomes -. check-report.sh and fix-collect.sh must agree on it.
# Usage: artifact-name.sh <name> <shard>
set -euo pipefail
printf 'ci-failure-%s-%s\n' "$1" "$2" | LC_ALL=C tr -c 'A-Za-z0-9._\n-' '-'
