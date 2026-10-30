#!/bin/bash
# repo-ownership.sh
# Classify the current repo's ownership relative to the authenticated user.
# Used to decide whether assignment can be defaulted silently or must be asked.
#
# Usage: repo-ownership.sh [<owner>/<repo>]
#
# Output (tab-separated key/value lines):
#   REPO        <owner>/<repo>
#   VIEWER      <authenticated login>
#   OWNER_TYPE  User | Organization
#   KIND        personal | org | external
#
# KIND meanings:
#   personal — owned by the authenticated user's own account
#   org      — owned by an organization
#   external — owned by a different user's personal account

set -e

REPO="${1:-}"
if [[ -z "$REPO" ]]; then
  REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || true)
fi

if [[ -z "$REPO" ]]; then
  echo "ERROR: Not in a GitHub repository or gh CLI not authenticated" >&2
  exit 1
fi

VIEWER=$(gh api user --jq '.login' 2>/dev/null || true)
OWNER_TYPE=$(gh api "repos/$REPO" --jq '.owner.type' 2>/dev/null || true)
OWNER_LOGIN=$(echo "$REPO" | cut -d/ -f1)

# A failed `gh api` call can still print an error body on stdout (e.g. a 404 JSON
# payload), so validate the value instead of trusting a non-empty string.
if [[ "$OWNER_TYPE" != "User" && "$OWNER_TYPE" != "Organization" ]]; then
  OWNER_TYPE=""
fi

if [[ -z "$VIEWER" || -z "$OWNER_TYPE" ]]; then
  echo "ERROR: Could not resolve viewer or owner type for $REPO" >&2
  exit 1
fi

if [[ "$OWNER_TYPE" == "Organization" ]]; then
  KIND="org"
elif [[ "$OWNER_LOGIN" == "$VIEWER" ]]; then
  KIND="personal"
else
  KIND="external"
fi

printf 'REPO\t%s\n' "$REPO"
printf 'VIEWER\t%s\n' "$VIEWER"
printf 'OWNER_TYPE\t%s\n' "$OWNER_TYPE"
printf 'KIND\t%s\n' "$KIND"
