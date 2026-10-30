#!/bin/bash
# prepare-branch.sh
# Points the local PR branch at its remote tip before a rebase, without
# discarding anything: it refuses a dirty tree and a branch with commits the
# remote does not have, and moves the branch only when nothing would be lost.
#
# Usage: prepare-branch.sh <head-branch> [remote]
#   <remote> defaults to origin; a fork PR passes the remote of its head repo.
#   Expects `git fetch <remote> <head-branch>` to have run first.
#
# Output (key=value, one per line):
#   recovery=<sha>   where the local branch pointed before, or "none" if it did
#                    not exist; `git switch -C <head> <sha>` restores it
#   before=<sha>     the remote tip, the value a force-push leases against
#   worktree=<path>  on exit 5 only: the other worktree that has <head> checked out
#
# Exit codes:
#   0 = branch checked out at <remote>/<head>
#   1 = usage error or not a git repository
#   2 = work tree has uncommitted or untracked changes
#   3 = local branch has commits <remote>/<head> does not; listed on stderr
#   4 = <remote>/<head> does not exist
#   5 = <head> is checked out in another worktree, which git will not switch to

set -e

HEAD_BRANCH="$1"
REMOTE="${2:-origin}"

if [[ -z "$HEAD_BRANCH" ]]; then
    echo "Usage: prepare-branch.sh <head-branch> [remote]" >&2
    exit 1
fi

if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "ERROR: Not a git repository" >&2
    exit 1
fi

REMOTE_REF="refs/remotes/$REMOTE/$HEAD_BRANCH"
LOCAL_REF="refs/heads/$HEAD_BRANCH"

if ! BEFORE=$(git rev-parse -q --verify "$REMOTE_REF^{commit}"); then
    echo "ERROR: $REMOTE/$HEAD_BRANCH not found. Run: git fetch $REMOTE $HEAD_BRANCH" >&2
    exit 4
fi

CURRENT_TOP=$(git rev-parse --show-toplevel)
WT_PATH=""
while IFS= read -r line; do
    case "$line" in
        "worktree "*) WT_PATH="${line#worktree }" ;;
        "branch $LOCAL_REF")
            if [[ "$(cd "$WT_PATH" 2> /dev/null && pwd -P)" != "$(cd "$CURRENT_TOP" && pwd -P)" ]]; then
                echo "ERROR: $HEAD_BRANCH is checked out in another worktree: $WT_PATH" >&2
                echo "worktree=$WT_PATH"
                exit 5
            fi
            ;;
    esac
done <<< "$(git worktree list --porcelain)"

if [[ -n "$(git status --porcelain)" ]]; then
    echo "ERROR: work tree is not clean; commit, stash, or use a separate worktree" >&2
    git status --short >&2
    exit 2
fi

RECOVERY=none
if RECOVERY=$(git rev-parse -q --verify "$LOCAL_REF^{commit}"); then
    LOCAL_ONLY=$(git rev-list --count "$REMOTE_REF..$LOCAL_REF")
    if [[ "$LOCAL_ONLY" != "0" ]]; then
        echo "ERROR: $HEAD_BRANCH has $LOCAL_ONLY commit(s) not on $REMOTE/$HEAD_BRANCH:" >&2
        git log --oneline "$REMOTE_REF..$LOCAL_REF" >&2
        echo "recovery=$RECOVERY"
        exit 3
    fi
else
    RECOVERY=none
fi

git switch --quiet -C "$HEAD_BRANCH" "$REMOTE_REF"

echo "recovery=$RECOVERY"
echo "before=$BEFORE"
