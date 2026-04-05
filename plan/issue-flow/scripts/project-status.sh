#!/bin/bash
# project-status.sh
# Change an issue's status in a GitHub Projects V2 board.
# Usage: project-status.sh <issue-number> <status>
#
# Finds the issue's project, discovers the Status field, and updates via GraphQL.

set -e

ISSUE_NUMBER="$1"
TARGET_STATUS="$2"

if [[ -z "$ISSUE_NUMBER" || -z "$TARGET_STATUS" ]]; then
  echo "Usage: project-status.sh <issue-number> <status>"
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

# Find projects associated with this issue
PROJECT_ITEMS=$(gh api graphql -f query="
  query {
    node(id: \"$ISSUE_NODE_ID\") {
      ... on Issue {
        projectItems(first: 10) {
          nodes {
            id
            project {
              id
              title
            }
          }
        }
      }
    }
  }
" 2>/dev/null | jq -c '.data.node.projectItems.nodes[]' 2>/dev/null)

if [[ -z "$PROJECT_ITEMS" ]]; then
  echo "ERROR: Issue #$ISSUE_NUMBER is not in any project"
  exit 1
fi

# Get first project's ID and item ID
FIRST_ITEM=$(echo "$PROJECT_ITEMS" | head -1)
PROJECT_ID=$(echo "$FIRST_ITEM" | jq -r '.project.id')
ITEM_ID=$(echo "$FIRST_ITEM" | jq -r '.id')
PROJECT_TITLE=$(echo "$FIRST_ITEM" | jq -r '.project.title')

echo "Project: $PROJECT_TITLE"

# Get the Status field ID and option IDs
FIELD_DATA=$(gh api graphql -f query="
  query {
    node(id: \"$PROJECT_ID\") {
      ... on ProjectV2 {
        fields(first: 30) {
          nodes {
            ... on ProjectV2SingleSelectField {
              id
              name
              options {
                id
                name
              }
            }
          }
        }
      }
    }
  }
" 2>/dev/null)

STATUS_FIELD_ID=$(echo "$FIELD_DATA" | jq -r '.data.node.fields.nodes[] | select(.name == "Status") | .id')

if [[ -z "$STATUS_FIELD_ID" || "$STATUS_FIELD_ID" == "null" ]]; then
  echo "ERROR: Could not find Status field in project"
  exit 1
fi

# Find the target status option (case-insensitive match)
OPTION_ID=$(echo "$FIELD_DATA" | jq -r --arg status "$TARGET_STATUS" \
  '.data.node.fields.nodes[] | select(.name == "Status") | .options[] | select(.name | ascii_downcase == ($status | ascii_downcase)) | .id')

if [[ -z "$OPTION_ID" || "$OPTION_ID" == "null" ]]; then
  echo "ERROR: Status '$TARGET_STATUS' not found. Available statuses:"
  echo "$FIELD_DATA" | jq -r '.data.node.fields.nodes[] | select(.name == "Status") | .options[].name'
  exit 1
fi

# Update the status
gh api graphql -f query="
  mutation {
    updateProjectV2ItemFieldValue(input: {
      projectId: \"$PROJECT_ID\"
      itemId: \"$ITEM_ID\"
      fieldId: \"$STATUS_FIELD_ID\"
      value: { singleSelectOptionId: \"$OPTION_ID\" }
    }) {
      projectV2Item { id }
    }
  }
" > /dev/null 2>&1

echo "SUCCESS: Issue #$ISSUE_NUMBER status set to '$TARGET_STATUS' in '$PROJECT_TITLE'"
