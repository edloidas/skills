#!/usr/bin/env bash
# Resolve the temp directory for claude files.
# Outputs the resolved path without a trailing newline.
# Usage: bash assist/skills/claude/scripts/resolve-tmp.sh
printf '%s' "${TMPDIR:-/tmp}"
