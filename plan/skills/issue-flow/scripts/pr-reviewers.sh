#!/bin/bash
# pr-reviewers.sh
# Find users with actual recent PR-review activity (review-requests + reviews).
# Output: <user>\t<count> per row, up to 3 rows, sorted by count desc.
# Excludes the authenticated user and common bot accounts.
#
# Usage: pr-reviewers.sh [<owner>/<repo>] [<limit>]
#   <owner>/<repo>  Defaults to current repo (gh repo view).
#   <limit>         PR scan window (default 100 — covers ~1–3 months on
#                   typical repos; lower for high-velocity ones).
#
# Notes:
#   - Uses --state all instead of merged: closed/abandoned PRs still indicate
#     who is engaged with reviews on this repo.
#   - Empty output is a valid signal — caller should not fall back to a
#     generic collaborator list with fabricated descriptions.

set -e

REPO="${1:-}"
LIMIT="${2:-100}"

if [[ -z "$REPO" ]]; then
  REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null)
fi

if [[ -z "$REPO" ]]; then
  echo "ERROR: Not in a GitHub repository or gh CLI not authenticated" >&2
  exit 1
fi

SELF=$(gh api user --jq .login 2>/dev/null || echo "")

gh pr list --repo "$REPO" --state all --limit "$LIMIT" \
    --json reviewRequests,reviews 2>/dev/null \
  | jq -r --arg self "$SELF" '
      [ .[]
        | (.reviewRequests[]?.login // empty),
          (.reviews[]?.author.login // empty)
      ]
      | map(select(. != null and . != "" and . != $self))
      | map(select(
          (endswith("[bot]") | not)
          and . != "copilot-pull-request-reviewer"
          and . != "github-actions"
          and . != "dependabot"
          and . != "renovate"
        ))
      | group_by(.)
      | map({user: .[0], count: length})
      | sort_by(-.count)
      | .[0:3]
      | .[] | "\(.user)\t\(.count)"
    '
