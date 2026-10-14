#!/bin/bash
# stack-sync.sh
# Keeps a stacked branch sitting on its parent. Step 2 records, for a branch cut
# from a named parent:
#   branch.<name>.issueFlowBase     the parent branch
#   branch.<name>.issueFlowBaseTip  the parent commit this branch sits on
# That recorded tip, not a merge-base, is the fork point: once the parent is
# amended and force-pushed, a merge-base reaches below the parent and counts its
# old commits as this branch's own, and Consolidate would squash them in.
#
# Run on the stacked branch before Consolidate, before any rebase onto the base,
# and before a push:
#   parent unchanged, or only gained commits -> nothing moves                 (kept)
#   parent rewritten                         -> rebase --onto the new tip      (rebased)
#   parent merged and gone from the remote   -> rebase --onto the default
#                                               branch, forget the record     (landed)
# After rebased or landed the branch differs from its remote: force-push it with
# a lease.
#
# Output, one KEY=VALUE per line, STACK always last:
#   BASE=<branch the PR targets>    FORK=<sha this branch's own commits start after>
#   STACK=none | kept | rebased | landed
#   none = no record; the caller uses detect-base.sh and merge-base as usual.
#
# Exit codes: 0 = done, 1 = not a git repo, origin unreachable, or the recorded
#             tip is no longer in the branch, 3 = the rebase conflicts (aborted,
#             nothing changed), 4 = a rebase is needed but the tree has uncommitted
#             changes, 5 = the parent left the remote without being merged

if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "ERROR: Not inside a git repository" >&2
  exit 1
fi

cur=$(git branch --show-current 2>/dev/null)
base=""
if [ -n "$cur" ]; then
  base=$(git config --get "branch.$cur.issueFlowBase" 2>/dev/null) || base=""
fi
if [ -z "$base" ]; then
  echo "STACK=none"
  exit 0
fi
tip=$(git config --get "branch.$cur.issueFlowBaseTip" 2>/dev/null) || tip=""

rc=0
git ls-remote --exit-code --heads origin "refs/heads/$base" > /dev/null 2>&1 || rc=$?
case "$rc" in
  0) state=present ;;
  2) state=gone ;;
  *)
    echo "ERROR: cannot reach origin to check the parent branch $base" >&2
    exit 1
    ;;
esac

# A tip this branch no longer contains cannot be told apart from a rewritten
# parent, and guessing wrong squashes the parent in: stop. A record with no tip
# falls back to the merge-base, which is right until the parent is rewritten.
if [ -n "$tip" ] && ! git merge-base --is-ancestor "$tip" HEAD 2>/dev/null; then
  echo "ERROR: the recorded tip of $base is no longer in $cur — re-record the tip it now sits on" >&2
  exit 1
fi
if [ -z "$tip" ]; then
  if [ "$state" = present ]; then
    git fetch --quiet origin "$base" 2>/dev/null || true
    tip=$(git merge-base "origin/$base" HEAD 2>/dev/null) || tip=""
  fi
  if [ -z "$tip" ]; then
    echo "ERROR: no fork point recorded for $cur and none can be derived from $base" >&2
    exit 1
  fi
  echo "No recorded tip for $cur; using the merge-base with $base" >&2
fi

rebase_onto() {
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "ERROR: $cur must move onto $1, but the tree has uncommitted changes — commit or stash them first" >&2
    exit 4
  fi
  if ! git rebase --quiet --onto "$1" "$tip" > /dev/null 2>&1; then
    git rebase --abort > /dev/null 2>&1 || true
    echo "ERROR: rebasing $cur onto $1 conflicts; the rebase was aborted and nothing changed" >&2
    exit 3
  fi
}

if [ "$state" = present ]; then
  git fetch --quiet origin "$base" || {
    echo "ERROR: cannot fetch $base" >&2
    exit 1
  }
  new=$(git rev-parse "origin/$base")
  if [ "$new" = "$tip" ] || git merge-base --is-ancestor "$tip" "$new"; then
    echo "BASE=$base"
    echo "FORK=$tip"
    echo "STACK=kept"
    exit 0
  fi
  rebase_onto "origin/$base"
  git config "branch.$cur.issueFlowBaseTip" "$new"
  echo "Parent $base was rewritten; moved $cur onto its new tip" >&2
  echo "BASE=$base"
  echo "FORK=$new"
  echo "STACK=rebased"
  exit 0
fi

merged=$(gh pr list --head "$base" --state merged --json number --jq length 2>/dev/null) || {
  echo "ERROR: parent $base is gone and gh cannot tell whether it was merged" >&2
  exit 1
}
if [ "${merged:-0}" = 0 ]; then
  echo "ERROR: parent $base left the remote without being merged" >&2
  exit 5
fi

default=$(gh repo view --json defaultBranchRef -q '.defaultBranchRef.name' 2>/dev/null) || default=""
if [ -z "$default" ]; then
  default=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||') || default=""
fi
if [ -z "$default" ]; then
  echo "ERROR: parent $base is gone and the default branch cannot be determined" >&2
  exit 1
fi
git fetch --quiet origin "$default" || {
  echo "ERROR: cannot fetch $default" >&2
  exit 1
}
rebase_onto "origin/$default"
git config --unset "branch.$cur.issueFlowBase"
git config --unset "branch.$cur.issueFlowBaseTip" 2>/dev/null || true
echo "Parent $base is gone from the remote; moved $cur onto $default and forgot the record" >&2
echo "BASE=$default"
echo "FORK=$(git rev-parse "origin/$default")"
echo "STACK=landed"
