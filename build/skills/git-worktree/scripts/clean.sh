#!/bin/bash
# clean.sh
# Removes all worktrees for the current repository
#
# Usage: clean.sh [--local]           # dry-run (default)
#        clean.sh [--local] --apply   # actually remove
#        clean.sh [--local] --force   # force remove (implies --apply)
#
# Exit codes: 0=success, 1=not git repo

set -e

# Parse arguments
LOCAL=false
APPLY=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --local)
            LOCAL=true
            shift
            ;;
        --apply)
            APPLY=true
            shift
            ;;
        --force)
            FORCE=true
            APPLY=true
            shift
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            echo "Usage: clean.sh [--local] [--apply] [--force]" >&2
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

# Prune stale references first
git worktree prune

# Collect worktrees to remove
WORKTREES=()
while IFS= read -r line; do
    WT_PATH=$(echo "$line" | awk '{print $1}')

    # Skip main repo and worktrees outside our filter directory
    if [[ "$WT_PATH" == "$REPO_ROOT" ]]; then
        continue
    fi
    if [[ "$WT_PATH" != "$FILTER_DIR"/* ]]; then
        continue
    fi

    WORKTREES+=("$WT_PATH")
done < <(git worktree list)

if [[ ${#WORKTREES[@]} -eq 0 ]]; then
    echo "No worktrees to clean for $REPO_NAME."
    exit 0
fi

# Show what would be removed
echo "Worktrees to remove (${#WORKTREES[@]}):"
echo ""
for wt in "${WORKTREES[@]}"; do
    if [[ "$LOCAL" == true ]]; then
        DISPLAY=".worktrees/${wt##*/.worktrees/}"
    else
        DISPLAY="${wt/$HOME/~}"
    fi
    echo "  $DISPLAY"
done
echo ""

if [[ "$APPLY" == false ]]; then
    echo "(dry-run) No changes made. Use --apply to remove."
    exit 0
fi

# Remove each worktree
echo "Removing worktrees..."
for wt in "${WORKTREES[@]}"; do
    if [[ "$LOCAL" == true ]]; then
        DISPLAY=".worktrees/${wt##*/.worktrees/}"
    else
        DISPLAY="${wt/$HOME/~}"
    fi
    echo "  Removing: $DISPLAY"
    if [[ "$FORCE" == true ]]; then
        git worktree remove --force "$wt"
    else
        git worktree remove "$wt"
    fi
done

# Prune again after removal
git worktree prune

# Clean empty directories
if [[ "$LOCAL" == true ]]; then
    if [[ -d "$FILTER_DIR" ]] && [[ -z "$(ls -A "$FILTER_DIR" 2>/dev/null)" ]]; then
        rmdir "$FILTER_DIR"
    fi
else
    if [[ -d "$FILTER_DIR" ]] && [[ -z "$(ls -A "$FILTER_DIR" 2>/dev/null)" ]]; then
        rmdir "$FILTER_DIR"
        WORKTREE_ROOT="${GIT_WORKTREES_DIR:-$HOME/.worktrees}"
        if [[ -d "$WORKTREE_ROOT" ]] && [[ -z "$(ls -A "$WORKTREE_ROOT" 2>/dev/null)" ]]; then
            rmdir "$WORKTREE_ROOT"
        fi
    fi
fi

echo ""
echo "Done! Removed ${#WORKTREES[@]} worktree(s)."
