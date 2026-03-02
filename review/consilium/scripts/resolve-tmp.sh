#!/usr/bin/env bash
# Resolve the temp directory for consilium files.
# Outputs the resolved path without a trailing newline.
# Usage: bash review/consilium/scripts/resolve-tmp.sh
printf '%s' "${TMPDIR:-/tmp}"
