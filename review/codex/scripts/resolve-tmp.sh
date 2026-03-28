#!/usr/bin/env bash
# Resolve the temp directory for codex files.
# Outputs the resolved path without a trailing newline.
# Usage: bash review/codex/scripts/resolve-tmp.sh
printf '%s' "${TMPDIR:-/tmp}"
