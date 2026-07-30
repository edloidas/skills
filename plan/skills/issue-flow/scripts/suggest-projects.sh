#!/bin/bash
# suggest-projects.sh [<owner>/<repo>]
# Suggest up to 4 projects for a new issue, ranked by signal:
#   USED    — projects where you've recently filed issues (top 2 by count)
#   RELATED — other active projects from repo/org, sorted by recent activity (top 2)
# Output: one project per line, tab-separated: <bucket>\t<project-id>\t<project-title>\t<note>

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GH_TOKEN=$(bash "$SCRIPT_DIR/_resolve-project-token.sh" 2>/dev/null) || true
export GH_TOKEN

if [[ -z "$GH_TOKEN" ]]; then
  echo "ERROR: No token with read:project scope available" >&2
  exit 1
fi

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

LOGIN=$(gh api user --jq '.login' 2>/dev/null)
if [[ -z "$LOGIN" ]]; then
  echo "ERROR: Could not determine current user" >&2
  exit 1
fi

DATA=$(gh api graphql \
  -f owner="$OWNER" \
  -f name="$NAME" \
  -f me="$LOGIN" \
  -f query='
query($owner:String!, $name:String!, $me:String!) {
  repository(owner:$owner, name:$name) {
    issues(first: 20, orderBy: { field: CREATED_AT, direction: DESC },
           filterBy: { createdBy: $me, assignee: $me }) {
      nodes {
        projectItems(first: 10) {
          nodes { project { id title } }
        }
      }
    }
    projectsV2(first: 50) { nodes { id title updatedAt } }
  }
  repositoryOwner(login:$owner) {
    ... on Organization { projectsV2(first: 100) { nodes { id title updatedAt } } }
    ... on User         { projectsV2(first: 100) { nodes { id title updatedAt } } }
  }
}' 2>/dev/null) || true

if [[ -z "$DATA" ]]; then
  echo "ERROR: GraphQL query failed" >&2
  exit 1
fi

USED=$(echo "$DATA" | jq -r '
  [.data.repository.issues.nodes[]?.projectItems.nodes[]?.project | select(.)]
  | group_by(.id)
  | map({id: .[0].id, title: .[0].title, count: length})
  | sort_by(-.count)
  | .[0:2]
  | .[]
  | "USED\t\(.id)\t\(.title)\t\(.count) recent"
')

USED_IDS=$(printf '%s\n' "$USED" | awk -F'\t' 'NF{print $2}')

RELATED=$(echo "$DATA" | jq --arg used "$USED_IDS" -r '
  ([.data.repository.projectsV2.nodes[]?] + [.data.repositoryOwner.projectsV2.nodes[]?])
  | unique_by(.id)
  | map(select(.id as $id | ($used | split("\n") | index($id)) | not))
  | sort_by(.updatedAt) | reverse
  | .[0:2]
  | .[]
  | "RELATED\t\(.id)\t\(.title)\tupdated \(.updatedAt[0:10])"
')

[[ -n "$USED" ]] && printf '%s\n' "$USED"
[[ -n "$RELATED" ]] && printf '%s\n' "$RELATED"
