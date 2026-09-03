#!/bin/bash
# issue-types.sh [<owner>/<repo>]
# Print GitHub issue type names supported by this repository, one per line.
# Empty output is a valid answer for repositories without issue types.

set -e

if [[ -n "$1" ]]; then
  REPO="$1"
else
  REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null)
fi

if [[ -z "$REPO" || "$REPO" != */* ]]; then
  echo "ERROR: Could not resolve repo. Pass <owner>/<repo> as argument." >&2
  exit 1
fi

OWNER="${REPO%%/*}"
NAME="${REPO##*/}"
ERR_FILE=$(mktemp "${TMPDIR:-/tmp}/issue-types-err.XXXXXX")

DATA=$(gh api graphql \
  -f owner="$OWNER" \
  -f name="$NAME" \
  -f query='
query($owner:String!, $name:String!) {
  repository(owner:$owner, name:$name) {
    isInOrganization
    issueTypes(first: 20) { nodes { name } }
  }
}' 2>"$ERR_FILE") || {
  rc=$?
  cat "$ERR_FILE" >&2
  rm -f "$ERR_FILE"
  echo "ERROR: GraphQL issue type query failed" >&2
  exit "$rc"
}
rm -f "$ERR_FILE"

if ! printf '%s' "$DATA" | jq -e '.data.repository != null' >/dev/null; then
  echo "ERROR: Repository not found: $REPO" >&2
  exit 1
fi

printf '%s' "$DATA" | jq -r '.data.repository.issueTypes.nodes[]?.name'
