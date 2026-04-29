#!/bin/bash
# get-issue-projects.sh
# List projects (V2) that a given issue is currently a member of.
# Usage: get-issue-projects.sh <issue-number>
# Output: tab-separated <project-id>\t<project-title>, one per line. Empty output if none.

set -e

ISSUE_NUMBER="$1"

if [[ -z "$ISSUE_NUMBER" ]]; then
  echo "Usage: get-issue-projects.sh <issue-number>" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GH_TOKEN=$(bash "$SCRIPT_DIR/_resolve-project-token.sh" 2>/dev/null) || true
export GH_TOKEN

if [[ -z "$GH_TOKEN" ]]; then
  echo "ERROR: No token with read:project scope available" >&2
  exit 1
fi

REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null)
if [[ -z "$REPO" ]]; then
  echo "ERROR: Not in a GitHub repository or gh CLI not authenticated" >&2
  exit 1
fi
OWNER=$(echo "$REPO" | cut -d/ -f1)
NAME=$(echo "$REPO" | cut -d/ -f2)

gh api graphql -f query="
  query {
    repository(owner: \"$OWNER\", name: \"$NAME\") {
      issue(number: $ISSUE_NUMBER) {
        projectItems(first: 20) {
          nodes {
            project { id title }
          }
        }
      }
    }
  }
" 2>/dev/null | jq -r '.data.repository.issue.projectItems.nodes[]?.project | "\(.id)\t\(.title)"'
