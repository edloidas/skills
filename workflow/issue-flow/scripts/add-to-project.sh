#!/bin/bash
# add-to-project.sh
# Add an issue to a GitHub Projects V2 board with an optional initial status.
# Usage: add-to-project.sh <issue-number> <project-title> [status]

set -e

ISSUE_NUMBER="$1"
PROJECT_TITLE="$2"
INITIAL_STATUS="$3"

if [[ -z "$ISSUE_NUMBER" || -z "$PROJECT_TITLE" ]]; then
  echo "Usage: add-to-project.sh <issue-number> <project-title> [status]"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GH_TOKEN=$(bash "$SCRIPT_DIR/resolve-project-token.sh" 2>/dev/null) || true
export GH_TOKEN

if [[ -z "$GH_TOKEN" ]]; then
  echo "ERROR: No token with read:project scope available"
  exit 1
fi

REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null)
OWNER=$(echo "$REPO" | cut -d/ -f1)
NAME=$(echo "$REPO" | cut -d/ -f2)

# Get issue node ID
ISSUE_NODE_ID=$(gh api graphql -f query="
  query {
    repository(owner: \"$OWNER\", name: \"$NAME\") {
      issue(number: $ISSUE_NUMBER) {
        id
      }
    }
  }
" --jq '.data.repository.issue.id' 2>/dev/null)

if [[ -z "$ISSUE_NODE_ID" || "$ISSUE_NODE_ID" == "null" ]]; then
  echo "ERROR: Could not find issue #$ISSUE_NUMBER"
  exit 1
fi

# Find matching project (try repo-level, then org-level)
ALL_PROJECTS=$(gh api graphql -f query="
  query {
    repository(owner: \"$OWNER\", name: \"$NAME\") {
      projectsV2(first: 20) {
        nodes { id title }
      }
    }
  }
" 2>/dev/null | jq -r '.data.repository.projectsV2.nodes[]? | "\(.id)\t\(.title)"' 2>/dev/null) || true

if [[ -z "$ALL_PROJECTS" ]]; then
  ALL_PROJECTS=$(gh api graphql -f query="
    query {
      organization(login: \"$OWNER\") {
        projectsV2(first: 50, orderBy: {field: UPDATED_AT, direction: DESC}) {
          nodes { id title }
        }
      }
    }
  " 2>/dev/null | jq -r '.data.organization.projectsV2.nodes[]? | "\(.id)\t\(.title)"' 2>/dev/null) || true
fi

if [[ -z "$ALL_PROJECTS" ]]; then
  echo "ERROR: Could not fetch projects"
  exit 1
fi

# Match project title (case-insensitive)
PROJECT_ID=$(echo "$ALL_PROJECTS" | awk -F'\t' -v title="$PROJECT_TITLE" \
  'tolower($2) == tolower(title) { print $1; exit }')

if [[ -z "$PROJECT_ID" ]]; then
  echo "ERROR: Project '$PROJECT_TITLE' not found"
  echo "Available projects:"
  echo "$ALL_PROJECTS" | awk -F'\t' '{ print "  - " $2 }'
  exit 1
fi

echo "Adding issue #$ISSUE_NUMBER to project '$PROJECT_TITLE'..."

# Add issue to project
ITEM_ID=$(gh api graphql -f query="
  mutation {
    addProjectV2ItemById(input: {
      projectId: \"$PROJECT_ID\"
      contentId: \"$ISSUE_NODE_ID\"
    }) {
      item { id }
    }
  }
" --jq '.data.addProjectV2ItemById.item.id' 2>/dev/null)

if [[ -z "$ITEM_ID" || "$ITEM_ID" == "null" ]]; then
  echo "ERROR: Failed to add issue to project"
  exit 1
fi

echo "SUCCESS: Issue #$ISSUE_NUMBER added to '$PROJECT_TITLE'"

# Optionally set initial status
if [[ -n "$INITIAL_STATUS" ]]; then
  echo "Setting status to '$INITIAL_STATUS'..."
  bash "$SCRIPT_DIR/project-status.sh" "$ISSUE_NUMBER" "$INITIAL_STATUS"
fi
