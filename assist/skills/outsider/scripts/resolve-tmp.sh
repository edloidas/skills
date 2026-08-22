#!/usr/bin/env bash
# Resolve the temp directory for outsider files.
# Outputs the resolved path without a trailing newline.
# Usage: bash assist/skills/outsider/scripts/resolve-tmp.sh
printf '%s' "${TMPDIR:-/tmp}"
