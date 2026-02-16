#!/bin/bash
# list.sh
# Lists Git worktrees for the current repository
#
# Usage: list.sh [--all]
# Flags: --all    Include the main repo working directory
#
# Exit codes: 0=success, 1=not git repo

set -e

# Parse arguments
SHOW_ALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            SHOW_ALL=true
            shift
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            echo "Usage: list.sh [--all]" >&2
            exit 1
            ;;
    esac
done

# Validate git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "ERROR: Not a git repository" >&2
    exit 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
REPO_NAME=$(basename "$REPO_ROOT")

# Resolve storage root
WORKTREE_ROOT="${GIT_WORKTREES_DIR:-$HOME/.worktrees}"
REPO_DIR="$WORKTREE_ROOT/$REPO_NAME"

# Parse worktree list
COUNT=0
OUTPUT=""

while IFS= read -r line; do
    # Each worktree entry has format: /path/to/worktree  abc1234 [branch-name]
    # or: /path/to/worktree  abc1234 (detached HEAD)
    # or: /path/to/worktree  0000000 (bare)

    WT_PATH=$(echo "$line" | awk '{print $1}')
    COMMIT=$(echo "$line" | awk '{print $2}')
    BRANCH_INFO=$(echo "$line" | sed 's/^[^ ]* *[^ ]* *//')

    # Skip main repo entry unless --all
    if [[ "$SHOW_ALL" == false && "$WT_PATH" == "$REPO_ROOT" ]]; then
        continue
    fi

    # Skip worktrees not under our storage directory (unless --all)
    if [[ "$SHOW_ALL" == false && "$WT_PATH" != "$REPO_DIR"/* ]]; then
        continue
    fi

    DISPLAY_PATH="${WT_PATH/$HOME/~}"
    OUTPUT+="$DISPLAY_PATH  $COMMIT  $BRANCH_INFO"$'\n'
    COUNT=$((COUNT + 1))
done < <(git worktree list)

if [[ $COUNT -eq 0 ]]; then
    echo "No worktrees found for $REPO_NAME."
else
    echo "$OUTPUT"
    echo "Total: $COUNT worktree(s)"
fi
