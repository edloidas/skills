#!/bin/bash
# create.sh
# Creates a Git worktree with optional remote fetch and agent settings copying
#
# Usage: create.sh --branch <branch>
#        create.sh --new-branch <branch> --start-point <ref>
# Flags: --local              Store worktree in .worktrees/ inside the repo
#        --no-fetch           Skip git fetch --all
#        --no-copy-settings   Skip agent settings copying
#
# Exit codes: 0=success, 1=not git repo, 2=bad args, 3=branch not found,
#             4=already exists, 5=git error

set -e

# Parse arguments
BRANCH=""
NEW_BRANCH=""
START_POINT=""
LOCAL=false
DO_FETCH=true
COPY_SETTINGS=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --branch)
            BRANCH="$2"
            shift 2
            ;;
        --new-branch)
            NEW_BRANCH="$2"
            shift 2
            ;;
        --start-point)
            START_POINT="$2"
            shift 2
            ;;
        --local)
            LOCAL=true
            shift
            ;;
        --no-fetch)
            DO_FETCH=false
            shift
            ;;
        --no-copy-settings)
            COPY_SETTINGS=false
            shift
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            echo "Usage: create.sh --branch <branch>" >&2
            echo "       create.sh --new-branch <branch> --start-point <ref>" >&2
            exit 2
            ;;
    esac
done

# Validate arguments
if [[ -z "$BRANCH" && -z "$NEW_BRANCH" ]]; then
    echo "ERROR: --branch or --new-branch is required" >&2
    echo "Usage: create.sh --branch <branch>" >&2
    echo "       create.sh --new-branch <branch> --start-point <ref>" >&2
    exit 2
fi

if [[ -n "$NEW_BRANCH" && -z "$START_POINT" ]]; then
    echo "ERROR: --start-point is required with --new-branch" >&2
    exit 2
fi

if [[ -n "$BRANCH" && -n "$NEW_BRANCH" ]]; then
    echo "ERROR: --branch and --new-branch are mutually exclusive" >&2
    exit 2
fi

# Validate git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "ERROR: Not a git repository" >&2
    exit 1
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
REPO_NAME=$(basename "$REPO_ROOT")

# Determine target branch name
TARGET_BRANCH="${BRANCH:-$NEW_BRANCH}"

# Sanitize branch name: replace / with -
SANITIZED=$(echo "$TARGET_BRANCH" | tr '/' '-')

# Resolve worktree path
if [[ "$LOCAL" == true ]]; then
    WORKTREE_PATH="$REPO_ROOT/.worktrees/$SANITIZED"
else
    WORKTREE_ROOT="${GIT_WORKTREES_DIR:-$HOME/.worktrees}"
    WORKTREE_PATH="$WORKTREE_ROOT/$REPO_NAME/$SANITIZED"
fi

# Check if worktree already exists
if [[ -d "$WORKTREE_PATH" ]]; then
    if [[ "$LOCAL" == true ]]; then
        DISPLAY_PATH=".worktrees/$SANITIZED"
    else
        DISPLAY_PATH="${WORKTREE_PATH/$HOME/~}"
    fi
    echo "ERROR: Worktree already exists at $DISPLAY_PATH" >&2
    exit 4
fi

# Fetch remotes
if [[ "$DO_FETCH" == true ]]; then
    echo "Fetching remotes..."
    git fetch --all --quiet
fi

# Verify branch exists (for existing branch mode)
if [[ -n "$BRANCH" ]]; then
    if ! git rev-parse --verify "$BRANCH" > /dev/null 2>&1; then
        echo "ERROR: Branch '$BRANCH' not found" >&2
        echo "Hint: Run 'git fetch --all' or use --new-branch to create it" >&2
        exit 3
    fi
fi

# Verify start point exists (for new branch mode)
if [[ -n "$START_POINT" ]]; then
    if ! git rev-parse --verify "$START_POINT" > /dev/null 2>&1; then
        echo "ERROR: Start point '$START_POINT' not found" >&2
        exit 3
    fi
fi

# Ensure .worktrees is in .gitignore for local mode
if [[ "$LOCAL" == true ]]; then
    # Only modify .gitignore at the real repo root (not inside a worktree)
    if [[ -d "$REPO_ROOT/.git" ]]; then
        GITIGNORE="$REPO_ROOT/.gitignore"
        if [[ ! -f "$GITIGNORE" ]] || ! grep -qE '^/?\.worktrees$' "$GITIGNORE"; then
            echo ".worktrees" >> "$GITIGNORE"
            echo "Added .worktrees to .gitignore"
        fi
    fi
fi

# Create parent directory
mkdir -p "$(dirname "$WORKTREE_PATH")"

# Create worktree
echo "Creating worktree..."
if [[ -n "$BRANCH" ]]; then
    if ! git worktree add "$WORKTREE_PATH" "$BRANCH" 2>&1; then
        echo "ERROR: Failed to create worktree" >&2
        exit 5
    fi
else
    if ! git worktree add -b "$NEW_BRANCH" "$WORKTREE_PATH" "$START_POINT" 2>&1; then
        echo "ERROR: Failed to create worktree" >&2
        exit 5
    fi
fi

# Copy agent settings directories (global mode only)
if [[ "$LOCAL" == false && "$COPY_SETTINGS" == true ]]; then
    for dir in .claude .codex .agents; do
        if [[ -d "$REPO_ROOT/$dir" ]]; then
            echo "Copying $dir/..."
            rsync -a "$REPO_ROOT/$dir/" "$WORKTREE_PATH/$dir/"
        fi
    done
fi

if [[ "$LOCAL" == true ]]; then
    DISPLAY_PATH=".worktrees/$SANITIZED"
else
    DISPLAY_PATH="${WORKTREE_PATH/$HOME/~}"
fi

echo ""
echo "=== Worktree Created ==="
echo "Path:   $DISPLAY_PATH"
echo "Branch: $TARGET_BRANCH"
echo ""
echo "To start working:"
echo "  cd $DISPLAY_PATH"
