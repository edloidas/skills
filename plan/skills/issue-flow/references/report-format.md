# Report Format

Each step produces a compact report. Print the report after completing the step.

## Templates

### Step 1: Issue Created

```
### [1] Issue Created
#<number>: <title>
Labels: <labels> | Assignee: @<login> [| Milestone: <name>]
<issue-url>
```

Include `Milestone: <name>` only when a milestone was set.

### Step 2: Branch Created

```
### [2] Branch Created
Branch: issue-<number> | Base: <base-branch> | Fork: <short-sha>
```

`Base:` is a branch **name**; `Fork:` is the merge-base SHA the branch was cut from.
Callers that need to diff against the branch point use `Fork:` — a name does not resolve
as a rev when the base exists only on the remote. Omit `Fork:` only when the base could
not be resolved.

### Step 3: Committed

```
### [3] Committed
<short-sha> <commit-subject>
<N> files changed (+<insertions> -<deletions>)
Squashed <N> commits -> 1
```

Include `Squashed <N> commits -> 1` whenever Consolidate reset and recommitted; omit it when
the branch already held exactly one canonical commit. One line per commit. Step 3 normally ends at a single commit; several lines appear only
in the one case Consolidate leaves them — the user chose "Keep as-is" on commits with
genuinely different subjects.

### Step 4: Pushed

```
### [4] Pushed
Branch: issue-<number> → origin/issue-<number>
```

If rebased:

```
### [4] Pushed (rebased)
Rebased onto origin/<base> | Force-pushed issue-<number>
```

If amended:

```
### [4] Pushed (amended)
Amended <short-sha> <subject> | Force-pushed issue-<number>
```

Both force-push variants name themselves, because the remote branch was rewritten and a
report that reads like an ordinary push hides that.

### Step 5: PR Created

```
### [5] PR Created
PR #<pr-number>: <title>
Base: <base> <- issue-<number> | Reviewer: @<login> | Assignees: @<login>, @<login>
Mergeable: yes
<pr-url>
```

Omit `Reviewer:` when none was set. List every assignee on `Assignees:` — `@me` plus the reviewer when one was set.

`Mergeable:` is mandatory — it is the outcome of the Step 5 mergeability check. Values:

- `yes` — `MERGEABLE` / `CLEAN`
- `yes (<status>)` — mergeable but `mergeStateStatus` is not `CLEAN`, e.g. `yes (blocked — review required)`, `yes (unstable — checks running)`
- `no — conflicts with <base>` — unresolved conflicts; the flow stops here
- `unknown (GitHub still computing)` — settled at neither after 3 polls

### Step 6: Pre-Merge Summary

Print this summary before asking the user to merge. Always use full URLs, not `owner/repo#N` shorthand.

```
### [6] Summary
Issue:  <issue-title> — <issue-url>
PR:     <pr-title> — <pr-url>
Branch: issue-<number> → <base> (rebase, <N> commits)
Commit: <short-sha> <commit-subject> (<N> files, +<insertions>/-<deletions>)
```

### Step 6: Waiting for Checks

```
### [6] Waiting for Checks
PR #<pr-number>: waiting for CI...
```

Print before running `gh pr checks --watch`. After checks pass, print the merged report below.

### Step 6: Merged

```
### [6] Merged
PR #<pr-number> merged into <base>
Branch issue-<number> deleted
Issue #<number> closed
```

## Rules

- Keep reports to 3-6 lines each
- Use `|` to separate inline metadata
- Always include URLs for created resources (issues, PRs)
- Use short SHA (7 chars) for commits
- Name any check that was meant to run and did not, on the report for the step that would have
  run it: `Project: skipped (Projects V2 unavailable)`, `Checks: not confirmed (watch timed out)`

## Worked Example

A full flow on `edloidas/skills` issue #69, every step filled in with real values:

```
### [1] Issue Created
#69: feat: add auto mode to solve-issue
Labels: enhancement | Assignee: @edloidas
https://github.com/edloidas/skills/issues/69

### [2] Branch Created
Branch: issue-69 | Base: master | Fork: 3920634

### [3] Committed
a1c4f0e feat: add auto mode to solve-issue #69
6 files changed (+184 -22)
Squashed 4 commits -> 1

### [4] Pushed
Branch: issue-69 -> origin/issue-69

### [5] PR Created
PR #70: feat: add auto mode to solve-issue #69
Base: master <- issue-69 | Assignees: @edloidas
Mergeable: yes
https://github.com/edloidas/skills/pull/70

### [6] Summary
Issue:  feat: add auto mode to solve-issue - https://github.com/edloidas/skills/issues/69
PR:     feat: add auto mode to solve-issue #69 - https://github.com/edloidas/skills/pull/70
Branch: issue-69 -> master (rebase, 1 commit)
Commit: a1c4f0e feat: add auto mode to solve-issue #69 (6 files, +184/-22)

### [6] Merged
PR #70 merged into master
Branch issue-69 deleted
Issue #69 closed
```

`Reviewer:` is absent from `[5]` because this is a personal repo, where the reviewer prompt is
skipped — that is the expected shape, not a missing field.
