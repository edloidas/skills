# Stacked Branches

A stacked branch is cut from another issue's branch instead of the default branch, and its pull
request targets that parent. It exists only when the user names the parent — "start work on #42
from issue-41" — never by detection.

## Step 2: record the parent

1. The parent must be on the remote: `git ls-remote --exit-code --heads origin refs/heads/<base>`.
   Exit 2 stops with `Base branch <base> is not on the remote — push it first.`
2. A dirty tree is carried onto the new branch from wherever it is. When the current branch is not
   `<base>`, stop with `Switch to <base> first — the uncommitted work would land on the wrong parent.`
3. Create `issue-<number>` off `<base>` as Step 2 always does, then record both keys:

```bash
git config branch.issue-<number>.issueFlowBase <base>
git config branch.issue-<number>.issueFlowBaseTip "$(git rev-parse origin/<base>)"
```

"Switch to existing branch" records them too when they are missing, with the tip the branch
actually sits on: `git merge-base origin/<base> HEAD`. From here `detect-base.sh`
returns the parent, and `scripts/stack-sync.sh` keeps the branch sitting on it.

## Every later step: sync first

On a branch with `issueFlowBase` set, run `bash "<skill-dir>/scripts/stack-sync.sh"` before
Consolidate, before any rebase onto the base, and before a push. Never `git rebase origin/<base>`
on a stacked branch: when the parent was amended and force-pushed, that replays the parent's old
commits, and Consolidate then squashes them into this one.

| Result | Meaning | Then |
| ------ | ------- | ---- |
| `STACK=kept` | Parent unchanged or only gained commits | Use `FORK=` as the fork point |
| `STACK=rebased` | Parent was rewritten; the branch moved onto its new tip | Use `FORK=`; force-push with a lease, per Leasing a force-push |
| `STACK=landed` | Parent merged and left the remote; the branch moved onto the default branch and the record is gone | Use `FORK=` and `BASE=`; force-push with a lease. GitHub has retargeted the PR |
| exit 3 | The move conflicts; it was aborted and nothing changed | Invoke `resolve-conflicts` for `git rebase --onto <new base> <recorded tip>`, or stop and report |
| exit 4 | A move is needed and the tree is dirty | Stop: the caller commits or stashes first |
| exit 1 | Origin unreachable, or the recorded tip is no longer in the branch | Stop; never fall back to the default branch, since the next write is a squash. A tip that left the branch means someone rebased it by hand: re-record the tip it now sits on |
| exit 5 | The parent left the remote without merging | Stop and report: the parent PR was closed, so this branch has no base to land on until the user picks one |

`STACK=none` means no record: the branch is not stacked, and the normal path applies.

Under **Slice Delivery** a move rewrites the earlier slice commits. That is safe because Consolidate
derives `from` from `git log` on every call; never carry a slice SHA across a sync.

## Step 5 and Step 6

The PR targets `BASE=`. Merging a stacked pull request into its parent closes no issue — close it
per Step 6 → **Merge**, as for any non-default base. A branch stacked above one that just changed
moves on its own next sync; nothing here rewrites another issue's branch.
