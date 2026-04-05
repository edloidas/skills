#!/usr/bin/env bash
# Create a unique temp directory for this issue-flow invocation.
# Outputs the directory path. Caller writes files inside it.
# Usage: bash plan/issue-flow/scripts/resolve-tmp.sh
set -euo pipefail
dir=$(mktemp -d "${TMPDIR:-/tmp}/issue-flow-XXXXXX")
printf '%s' "$dir"
