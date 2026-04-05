#!/bin/bash
# list.sh
# Lists Git worktrees for the current repository
#
# Usage: list.sh [--local] [--all]
# Flags: --local  Show worktrees from .worktrees/ inside the repo
#        --all    Show all worktrees via git worktree list
#
# Exit codes: 0=success, 1=not git repo

set -e

# Parse arguments
LOCAL=false
SHOW_ALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --local)
            LOCAL=true
            shift
            ;;
        --all)
            SHOW_ALL=true
            shift
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            echo "Usage: list.sh [--local] [--all]" >&2
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

# Resolve filter directory
if [[ "$LOCAL" == true ]]; then
    FILTER_DIR="$REPO_ROOT/.worktrees"
else
    WORKTREE_ROOT="${GIT_WORKTREES_DIR:-$HOME/.worktrees}"
    FILTER_DIR="$WORKTREE_ROOT/$REPO_NAME"
fi

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

    # Skip worktrees not under our filter directory (unless --all)
    if [[ "$SHOW_ALL" == false && "$WT_PATH" != "$FILTER_DIR"/* ]]; then
        continue
    fi

    if [[ "$LOCAL" == true ]]; then
        DISPLAY_PATH=".worktrees/${WT_PATH##*/.worktrees/}"
    else
        DISPLAY_PATH="${WT_PATH/$HOME/~}"
    fi
    OUTPUT+="$DISPLAY_PATH  $COMMIT  $BRANCH_INFO"$'\n'
    COUNT=$((COUNT + 1))
done < <(git worktree list)

if [[ $COUNT -eq 0 ]]; then
    echo "No worktrees found for $REPO_NAME."
else
    echo "$OUTPUT"
    echo "Total: $COUNT worktree(s)"
fi
