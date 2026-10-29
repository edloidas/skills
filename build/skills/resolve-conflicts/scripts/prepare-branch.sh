#!/bin/bash
# prepare-branch.sh
# Points the local PR branch at its remote tip before a rebase, without
# discarding anything: it refuses a dirty tree and a branch with commits the
# remote does not have, and moves the branch only when nothing would be lost.
#
# Usage: prepare-branch.sh <head-branch>
#   Expects `git fetch origin <head-branch>` to have run first.
#
# Output (key=value, one per line):
#   recovery=<sha>   where the local branch pointed before, or "none" if it did
#                    not exist; `git switch -C <head> <sha>` restores it
#   before=<sha>     the remote tip, the value a force-push leases against
#
# Exit codes:
#   0 = branch checked out at origin/<head>
#   1 = usage error or not a git repository
#   2 = work tree has uncommitted or untracked changes
#   3 = local branch has commits origin/<head> does not; listed on stderr
#   4 = origin/<head> does not exist

set -e

HEAD_BRANCH="$1"

if [[ -z "$HEAD_BRANCH" ]]; then
    echo "Usage: prepare-branch.sh <head-branch>" >&2
    exit 1
fi

if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "ERROR: Not a git repository" >&2
    exit 1
fi

REMOTE_REF="refs/remotes/origin/$HEAD_BRANCH"
LOCAL_REF="refs/heads/$HEAD_BRANCH"

if ! BEFORE=$(git rev-parse -q --verify "$REMOTE_REF^{commit}"); then
    echo "ERROR: origin/$HEAD_BRANCH not found. Run: git fetch origin $HEAD_BRANCH" >&2
    exit 4
fi

if [[ -n "$(git status --porcelain)" ]]; then
    echo "ERROR: work tree is not clean; commit, stash, or use a separate worktree" >&2
    git status --short >&2
    exit 2
fi

RECOVERY=none
if RECOVERY=$(git rev-parse -q --verify "$LOCAL_REF^{commit}"); then
    LOCAL_ONLY=$(git rev-list --count "$REMOTE_REF..$LOCAL_REF")
    if [[ "$LOCAL_ONLY" != "0" ]]; then
        echo "ERROR: $HEAD_BRANCH has $LOCAL_ONLY commit(s) not on origin/$HEAD_BRANCH:" >&2
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
