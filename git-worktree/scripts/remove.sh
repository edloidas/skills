#!/bin/bash
# remove.sh
# Removes a Git worktree in a single pass
#
# Usage: remove.sh --branch <branch>
#        remove.sh --path <path>
# Flags: --force    Force remove with uncommitted changes
#
# Exit codes: 0=success, 1=not git repo, 2=bad args, 3=not found,
#             4=has uncommitted changes

set -e

# Parse arguments
BRANCH=""
WORKTREE_PATH=""
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --branch)
            BRANCH="$2"
            shift 2
            ;;
        --path)
            WORKTREE_PATH="$2"
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            echo "Usage: remove.sh --branch <branch>" >&2
            echo "       remove.sh --path <path>" >&2
            exit 2
            ;;
    esac
done

# Validate arguments
if [[ -z "$BRANCH" && -z "$WORKTREE_PATH" ]]; then
    echo "ERROR: --branch or --path is required" >&2
    echo "Usage: remove.sh --branch <branch>" >&2
    echo "       remove.sh --path <path>" >&2
    exit 2
fi

# Validate git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "ERROR: Not a git repository" >&2
    exit 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
REPO_NAME=$(basename "$REPO_ROOT")

# Resolve storage root
WORKTREE_ROOT="${GIT_WORKTREES_DIR:-$HOME/.worktrees}"

# Resolve worktree path from branch name
if [[ -n "$BRANCH" ]]; then
    SANITIZED=$(echo "$BRANCH" | tr '/' '-')
    WORKTREE_PATH="$WORKTREE_ROOT/$REPO_NAME/$SANITIZED"
fi

# Expand ~ in path
WORKTREE_PATH="${WORKTREE_PATH/#\~/$HOME}"

# Check if worktree exists in git's tracking
if ! git worktree list --porcelain | grep -q "^worktree $WORKTREE_PATH$"; then
    DISPLAY_PATH="${WORKTREE_PATH/$HOME/~}"
    echo "ERROR: No worktree found at $DISPLAY_PATH" >&2
    exit 3
fi

DISPLAY_PATH="${WORKTREE_PATH/$HOME/~}"

# Remove worktree (single pass — handles both git unlinking and directory deletion)
echo "Removing worktree at $DISPLAY_PATH..."
if [[ "$FORCE" == true ]]; then
    git worktree remove --force "$WORKTREE_PATH"
else
    if ! git worktree remove "$WORKTREE_PATH" 2>&1; then
        echo "ERROR: Worktree has uncommitted changes. Use --force to remove anyway." >&2
        exit 4
    fi
fi

# Prune stale references
git worktree prune

# Clean empty parent directories
REPO_DIR="$WORKTREE_ROOT/$REPO_NAME"
if [[ -d "$REPO_DIR" ]] && [[ -z "$(ls -A "$REPO_DIR" 2>/dev/null)" ]]; then
    rmdir "$REPO_DIR"
    # Also remove root if empty
    if [[ -d "$WORKTREE_ROOT" ]] && [[ -z "$(ls -A "$WORKTREE_ROOT" 2>/dev/null)" ]]; then
        rmdir "$WORKTREE_ROOT"
    fi
fi

echo "Worktree removed successfully."
