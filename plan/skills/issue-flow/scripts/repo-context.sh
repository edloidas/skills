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

PROJECT_TOKEN=$(bash "$SCRIPT_DIR/_resolve-project-token.sh" 2>/dev/null) || true

if [[ -z "$PROJECT_TOKEN" ]]; then
  echo "(no token with read:project scope available; run gh auth refresh -s read:project)"
else
  ERR_FILE=$(mktemp "${TMPDIR:-/tmp}/repo-context-projects-err.XXXXXX")
  DATA=$(GH_TOKEN="$PROJECT_TOKEN" gh api graphql \
    -f owner="$OWNER" \
    -f name="$NAME" \
    -f query='
query($owner:String!, $name:String!) {
  repository(owner:$owner, name:$name) {
    projectsV2(first: 20) { nodes { id title updatedAt } }
  }
  repositoryOwner(login:$owner) {
    ... on Organization { projectsV2(first: 50, orderBy: {field: UPDATED_AT, direction: DESC}) { nodes { id title updatedAt } } }
    ... on User         { projectsV2(first: 50, orderBy: {field: UPDATED_AT, direction: DESC}) { nodes { id title updatedAt } } }
  }
}' 2>"$ERR_FILE") || {
    cat "$ERR_FILE" >&2
    rm -f "$ERR_FILE"
    echo "(failed to fetch projects: Projects V2 lookup requires read:project scope; run gh auth refresh -s read:project)"
    exit 0
  }
  rm -f "$ERR_FILE"

  PROJECTS=$(printf '%s' "$DATA" | jq -r '
    ([.data.repository.projectsV2.nodes[]?] + [.data.repositoryOwner.projectsV2.nodes[]?])
    | unique_by(.id)
    | .[]
    | "\(.id)\t\(.title)"' 2>/dev/null) || true

  if [[ -z "$PROJECTS" ]]; then
    echo "(no projects found)"
  else
    echo "$PROJECTS"
  fi
fi
