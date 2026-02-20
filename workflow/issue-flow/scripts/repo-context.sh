#!/bin/bash
# repo-context.sh
# Fetch repository context: labels, collaborators, top contributors, projects.
# Outputs structured sections for the agent to parse.

set -e

REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null)
if [[ -z "$REPO" ]]; then
  echo "ERROR: Not in a GitHub repository or gh CLI not authenticated"
  exit 1
fi

echo "=== Repository ==="
echo "$REPO"
echo ""

echo "=== Labels ==="
gh label list --repo "$REPO" --json name -q '.[].name' 2>/dev/null || echo "(failed to fetch)"
echo ""

echo "=== Collaborators ==="
gh api "repos/$REPO/collaborators" --jq '.[].login' 2>/dev/null || echo "(failed to fetch)"
echo ""

echo "=== Top Contributors ==="
gh api "repos/$REPO/contributors" --jq '.[].login' 2>/dev/null || echo "(failed to fetch)"
echo ""

echo "=== Projects V2 ==="
OWNER=$(echo "$REPO" | cut -d/ -f1)
NAME=$(echo "$REPO" | cut -d/ -f2)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PROJECT_TOKEN=$(bash "$SCRIPT_DIR/resolve-project-token.sh" 2>/dev/null) || true

if [[ -z "$PROJECT_TOKEN" ]]; then
  echo "(no token with read:project scope available)"
else
  PROJECTS=$(GH_TOKEN="$PROJECT_TOKEN" gh api graphql -f query="
    query {
      repository(owner: \"$OWNER\", name: \"$NAME\") {
        projectsV2(first: 20) {
          nodes { id title }
        }
      }
    }
  " 2>/dev/null | jq -r '.data.repository.projectsV2.nodes[]? | "\(.id)\t\(.title)"' 2>/dev/null) || true

  if [[ -z "$PROJECTS" ]]; then
    PROJECTS=$(GH_TOKEN="$PROJECT_TOKEN" gh api graphql -f query="
      query {
        organization(login: \"$OWNER\") {
          projectsV2(first: 50, orderBy: {field: UPDATED_AT, direction: DESC}) {
            nodes { id title }
          }
        }
      }
    " 2>/dev/null | jq -r '.data.organization.projectsV2.nodes[]? | "\(.id)\t\(.title)"' 2>/dev/null) || true
  fi

  if [[ -z "$PROJECTS" ]]; then
    echo "(no projects found or token lacks read:project scope)"
  else
    echo "$PROJECTS"
  fi
fi
