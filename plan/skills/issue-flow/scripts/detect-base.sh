#!/bin/bash
# detect-base.sh
# Detect the correct base branch for branching and PR targeting.
#
# Algorithm:
#   1. Get default branch from GitHub (main/master)
#   2. If current branch is a base-like branch (main/master/next/epic-*), use it directly
#   3. If current branch is issue-*, find the epic-* branch it was cut from by
#      ordering fork points by ancestry, with the default branch as the floor
#   4. If no epic beats the default branch, use the default branch
#
# Limitation: when two epic branches share the exact same fork point, git cannot
# tell which one the branch was cut from. The first enumerated wins.
#
# Output (last line): a BRANCH NAME, never a rev.
#   The name may not resolve as a rev — an epic branch can exist only on the
#   remote, in which case `git log <base>..HEAD` fails with "unknown revision".
#   Callers that need a rev must resolve it themselves:
#     baseref=$(git rev-parse --verify --quiet "origin/$base" \
#               || git rev-parse --verify --quiet "$base")
#   Callers that need a name (git checkout, gh pr create --base) use it as-is.
#
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

# If current branch is a base-like branch, use it directly
if [[ "$CURRENT_BRANCH" == "main" || "$CURRENT_BRANCH" == "master" || "$CURRENT_BRANCH" == "next" || "$CURRENT_BRANCH" == epic-* ]]; then
  echo "Using current branch as base: $CURRENT_BRANCH" >&2
  echo "$CURRENT_BRANCH"
  exit 0
fi

# If on an issue-* branch, find the epic-* branch it was cut from.
#
# Deliberately NOT `merge-base --is-ancestor origin/<epic> HEAD`: that asks
# "is the epic tip contained in my branch", which goes false the moment the
# epic gains a commit after you branched off it, silently demoting the base to
# the default branch. The real question is "which branch did I fork from", so
# compare fork points and pick the one furthest down the history.
#
# Ordering is by ancestry, not commit timestamp. Timestamps tie whenever two
# commits land in the same second, and a tie made the epic lose to the floor.
if [[ "$CURRENT_BRANCH" == issue-* ]]; then
  git fetch origin --quiet 2>/dev/null || true

  resolve_ref() {
    git rev-parse --verify --quiet "origin/$1" || git rev-parse --verify --quiet "$1"
  }

  fork_point() {
    local ref
    ref=$(resolve_ref "$1") || return 1
    [[ -n "$ref" ]] || return 1
    git merge-base "$ref" HEAD 2>/dev/null
  }

  # The default branch is the floor. An epic wins only when its fork point is
  # strictly a descendant of the default branch's fork point — i.e. the branch
  # really did leave the default branch by way of that epic.
  BEST_EPIC=""
  BEST_FORK=$(fork_point "$DEFAULT_BRANCH" || true)

  # Both remote and local epic branches — an epic may exist only locally.
  while IFS= read -r ref; do
    EPIC_BRANCH="${ref#refs/remotes/origin/}"
    EPIC_BRANCH="${EPIC_BRANCH#refs/heads/}"
    [[ -n "$EPIC_BRANCH" ]] || continue

    FORK=$(fork_point "$EPIC_BRANCH") || continue
    [[ -n "$FORK" ]] || continue

    if [[ -z "$BEST_FORK" ]]; then
      BEST_FORK="$FORK"
      BEST_EPIC="$EPIC_BRANCH"
      continue
    fi

    # Strictly newer: BEST_FORK is an ancestor of FORK, and they differ.
    if [[ "$FORK" != "$BEST_FORK" ]] && git merge-base --is-ancestor "$BEST_FORK" "$FORK" 2>/dev/null; then
      BEST_FORK="$FORK"
      BEST_EPIC="$EPIC_BRANCH"
    fi
  done < <(git for-each-ref --format='%(refname)' 'refs/remotes/origin/epic-*' 'refs/heads/epic-*' 2>/dev/null)

  if [[ -n "$BEST_EPIC" ]]; then
    echo "Detected epic branch: $BEST_EPIC" >&2
    echo "$BEST_EPIC"
    exit 0
  fi
fi

echo "Using default branch: $DEFAULT_BRANCH" >&2
echo "$DEFAULT_BRANCH"
