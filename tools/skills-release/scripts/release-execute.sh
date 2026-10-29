#!/bin/bash

# Release Execution Script
# Non-interactive release: release-bump.sh, then release-push.sh, with no
# approval gate between them. Either step failing stops the run, so a commit
# whose tag could not be created or verified is never pushed.
# Usage: release-execute.sh <version>

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -z "$1" ]]; then
  echo "ERROR: Version argument required"
  echo "Usage: release-execute.sh <version>"
  exit 1
fi

if ! bash "$SCRIPT_DIR/release-bump.sh" "$1"; then
  echo "ERROR: Bump failed; nothing was pushed"
  exit 1
fi

bash "$SCRIPT_DIR/release-push.sh" "$1"
