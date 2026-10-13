# Local clones

Every pull request in the queue is read from the reviewer's own clone of its repository. That
clone is the reviewer's working copy — usually on their own branch, sometimes on a branch that is
the head of a pull request in the queue. This file is the only home of the rules for touching it;
every dispatched prompt points here.

## Find the clone

For each repository in the queue, look for a clone in this order and stop at the first hit: any
path the reviewer named in this run, the current working directory, a child of it named after the
repository (running from a folder of clones), and a sibling of it named after the repository. A
candidate counts only if one of its remotes in `git remote -v` names that repository — in a fork
setup that is usually `upstream`, not `origin`. That remote is `<remote>` in every command below.
A repository with no clone is analysed from `gh pr diff` and `gh api` alone, gets no checks and no
fold, and the report says so on its row; nothing is cloned without asking.

Record, per clone, before any agent starts:

```
<repo>  <path>  remote=<name>  branch=<current>  clean=<yes|no>  stashes=<n>
```

A dirty tree is never cleaned. Its repository is analysed read-only, nothing in it is checked out,
and the report names it.

## Read without checking out

Analysis never needs a checkout. Fetch each pull request's head as its own ref — this works the
same for a branch in the base repository and for a fork — and read through refs:

```bash
git fetch <remote> <base> "pull/<N>/head:refs/remotes/<remote>/pr/<N>"
git fetch <remote> <old head sha>                            # recheck only: the head you reviewed
git show <remote>/pr/<N>:<path>
git diff <remote>/<base>...<remote>/pr/<N>
git range-diff <old-head>...<new-head>                     # what an author's force-push changed
git merge-tree --write-tree <remote>/<base> <remote>/pr/<N>    # does it still apply to the base
```

`git merge-tree` exits 0 with a tree id when the merge is clean, and 1 with the conflicting paths
when it is not; report `clean` or `conflicts (<files>, <nature>)`. `--write-tree` needs git 2.38
or later; with an older git, report `mergeStateStatus` and say so. Because reads take no checkout,
any number of agents may analyse pull requests of the same repository at once.

## Checkout lease

Running checks, reproducing a crash, or committing a fix needs the working tree. Exactly one agent
holds a clone's working tree at a time. The orchestrator grants the lease when it dispatches — the
prompt says `Lease: yours` or `Lease: none` — to at most one agent per clone per wave, and in
Phase 5 holds it itself. It never grants the lease for a pull request whose head lives in a fork:
a fork's code is read, never executed. The holder:

1. Confirms the tree is clean and records the branch it found.
2. Works on a disposable local branch: `git checkout -B triage/<N> <remote>/pr/<N>` for analysis,
   `fold/<N>` for a fold that will be pushed (`acting.md`).
3. Reverts every tracked file its own commands rewrote that the task did not ask to change — a
   package manager rewriting the lockfile is the usual one.
4. Returns to the recorded branch with a clean tree before releasing the lease, and reinstalls
   dependencies there when it installed different ones.

Leave the reviewer's own changes, stashes and branches exactly as found, and never create a
worktree: the reviewer's clone is the only place work happens, so nothing is left behind in a
directory nobody looks at.

## The reviewer's branch is a pull request head

When the recorded branch is the head of a pull request in the queue, it may hold the reviewer's own
unpushed work or only an older copy of the author's commits. Nothing in this skill moves it — reads
go through `<remote>/pr/<N>`, folds through `fold/<N>` — so leave it where it is and report how it
compares:

```bash
git rev-list --left-right --count <branch>...<remote>/pr/<N>
```

A local branch behind or diverged from the pull request is listed under *Local* in the report,
with the command that would update it, for the reviewer to run. The `triage/<N>` and `fold/<N>`
branches are kept for later reads and listed there too.
