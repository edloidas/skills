#!/bin/bash
# resolve-project-token.sh
# Resolve a GitHub token with read:project scope for Projects V2 API.
#
# Resolution order:
#   1. GH_PROJECTS_TOKEN environment variable
#   2. Current gh auth token (may lack read:project scope)
#
# Usage:
#   TOKEN=$(bash scripts/resolve-project-token.sh)
#
# Token is printed to stdout. Diagnostics go to stderr.

set -e

is_valid_token() {
  local t="$1"
  [[ -n "$t" && ${#t} -ge 30 ]]
}

# 1. Try GH_PROJECTS_TOKEN environment variable
if is_valid_token "${GH_PROJECTS_TOKEN:-}"; then
  echo "$GH_PROJECTS_TOKEN"
  exit 0
fi

# 2. Fall back to current gh auth token
TOKEN=$(gh auth token 2>/dev/null) || true

if is_valid_token "$TOKEN"; then
  echo "WARNING: Using default gh token — may lack read:project scope" >&2
  echo "$TOKEN"
  exit 0
fi

echo "ERROR: No GitHub token found." >&2
echo "  Set GH_PROJECTS_TOKEN with a PAT that has read:project scope," >&2
echo "  or authenticate with: gh auth login" >&2
exit 1
