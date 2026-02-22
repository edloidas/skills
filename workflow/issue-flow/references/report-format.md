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
Branch: issue-<number> | Base: <base-branch>
```

### Step 3: Committed

```
### [3] Committed
<short-sha> <commit-subject>
<N> files changed (+<insertions> -<deletions>)
```

For multiple commits, list each on its own line.

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

### Step 5: PR Created

```
### [5] PR Created
PR #<pr-number>: <title>
Base: <base> <- issue-<number> | Reviewer: @<login>
<pr-url>
```

### Step 6: Pre-Merge Confirmation

```
### [6] Pre-Merge
PR #<pr-number> → <base> (rebase, <N> commits)
Issue #<number> will be closed
Confirm merge?
```

### Step 6: Waiting for Checks

```
### [6] Waiting for Checks
PR #<pr-number>: <N> checks pending...
```

Print while `wait-checks.sh` is polling. After checks pass, print the merged report below.

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
