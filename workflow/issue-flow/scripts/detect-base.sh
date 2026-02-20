#!/bin/bash
# detect-base.sh
# Detect the correct base branch for branching and PR targeting.
#
# Algorithm:
#   1. Get default branch from GitHub (main/master)
#   2. If current branch is issue-*, check for epic-* ancestor branches
#   3. Among matching epic branches, pick the one with the most recent merge-base
#   4. If no epic match, use default branch
#
# Output (last line): base branch name
# Exit codes: 0 = found, 1 = not git repo, 2 = no remote

set -e

if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "ERROR: Not inside a git repository" >&2
  exit 1
fi

# Get default branch from GitHub
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null) || true

if [[ -z "$DEFAULT_BRANCH" ]]; then
  # Fallback: detect from remote HEAD
  DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||') || true
fi

if [[ -z "$DEFAULT_BRANCH" ]]; then
  echo "ERROR: Could not determine default branch — no remote configured?" >&2
  exit 2
fi

CURRENT_BRANCH=$(git branch --show-current 2>/dev/null)

# Only check for epic branches if on an issue-* branch
if [[ "$CURRENT_BRANCH" == issue-* ]]; then
  git fetch origin --quiet 2>/dev/null || true

  BEST_EPIC=""
  BEST_TIMESTAMP=0

  # Check all remote epic-* branches
  while IFS= read -r ref; do
    EPIC_BRANCH="${ref#refs/remotes/origin/}"

    # Check if epic branch is an ancestor of current branch
    if git merge-base --is-ancestor "origin/$EPIC_BRANCH" HEAD 2>/dev/null; then
      MERGE_BASE=$(git merge-base "origin/$EPIC_BRANCH" HEAD 2>/dev/null) || continue
      TIMESTAMP=$(git log -1 --format='%ct' "$MERGE_BASE" 2>/dev/null) || continue

      if (( TIMESTAMP > BEST_TIMESTAMP )); then
        BEST_TIMESTAMP=$TIMESTAMP
        BEST_EPIC="$EPIC_BRANCH"
      fi
    fi
  done < <(git for-each-ref --format='%(refname)' 'refs/remotes/origin/epic-*' 2>/dev/null)

  if [[ -n "$BEST_EPIC" ]]; then
    echo "Detected epic branch: $BEST_EPIC" >&2
    echo "$BEST_EPIC"
    exit 0
  fi
fi

echo "Using default branch: $DEFAULT_BRANCH" >&2
echo "$DEFAULT_BRANCH"
