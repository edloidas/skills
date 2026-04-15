---
name: next-issue
description: >
  Find the most relevant next GitHub issue to work on.
  Analyzes plan files, current branch, open PRs, and open issues
  to recommend what to pick up next. Use when the user asks which
  issue to work on, what's next, or wants to pick an issue from the backlog.
license: MIT
model: claude-sonnet-4-6
compatibility: Claude Code, Codex
allowed-tools: Bash(gh:*) Bash(git:*) Read Glob Grep AskUserQuestion
metadata:
  author: edloidas
---

# Next Issue

Recommends the most relevant GitHub issue to work on next. Gathers local git
state, plan files, open PRs, and the issue backlog, then ranks candidates and
presents the top picks. After the user selects an issue, automatically runs
`issue-analyze` on it to produce a full implementation analysis.

## Prerequisites

### Authenticate

```bash
gh auth status
```

If not authenticated, stop: `Run 'gh auth login' first.`

### Detect repo

```bash
gh repo view --json nameWithOwner --jq '.nameWithOwner'
```

Outputs `owner/repo`. If this fails, stop: `Not inside a GitHub repository.`

### Detect current user

```bash
gh api user --jq .login
```

Store as `<me>`.

## Phase 1: Local Context

Gather information about the current working state.

### Current branch and recent commits

```bash
git branch --show-current
git log --oneline -10
```

### Uncommitted and unpushed work

```bash
git status --short
git log @{u}..HEAD --oneline 2>/dev/null
```

If `git log @{u}..HEAD` fails (no upstream), skip — the branch has never been
pushed.

### Feature branch detection

If the current branch is not `main`, `master`, `develop`, or `next`, treat it
as a feature branch. Extract the issue number from the branch name using these
patterns (first match wins):

- `feat/<N>-*`, `fix/<N>-*`, `chore/<N>-*`, `refactor/<N>-*` — prefix style
- `issue-<N>-*` — issue prefix style
- `<N>-*` — bare number prefix

Where `<N>` is one or more digits. Store the extracted number as
`<branch-issue>`.

### Check for open PR on current branch

```bash
gh pr list --head "$(git branch --show-current)" --state open --json number,title,url --jq '.[0]'
```

If a PR exists, store it as `<current-pr>`.

### Short-circuit: feature branch with open PR

If on a feature branch AND `<current-pr>` exists, skip Phases 2–4. Present
this as the default recommendation. Use `AskUserQuestion` when available;
otherwise ask directly in chat:

- **Option 1:** `Issue #<N>` `(Recommended)` — `You have unfinished work: PR #<pr-number> "<pr-title>". Continue this before picking a new issue.`
- **Option 2:** `New issue` — `Skip current work and pick a different issue (continues to Phase 2)`

If the user picks Option 1, show the PR summary and stop. If the user picks
Option 2, continue the pipeline from Phase 2.

### Recently merged on base branch

```bash
git log main --oneline -10 --merges 2>/dev/null || git log master --oneline -10 --merges 2>/dev/null
```

Use to identify recently completed work (informational, not ranked).

## Phase 2: Plan Files

### Find plan files

Use `Glob` to search for:

- `<git-root>/.claude/plan/*.md`
- `<git-root>/.claude/PRD.md`
- `<git-root>/.claude/SPEC.md`

If no files found, skip this phase.

### Parse issue references

Use `Grep` to search all found plan files for:

- `#<N>` — hash-number references (word boundary, avoid matching inside URLs
  or color codes like `#fff`)
- `org/repo#<N>` — cross-repo shorthand references
- Full GitHub issue URLs: `https://github.com/<owner>/<repo>/issues/<N>`

Collect all unique issue numbers.

### Cross-reference with GitHub

For each extracted issue number, check if it is still open:

```bash
gh issue view <N> --json number,title,state,labels,milestone,assignees --jq 'select(.state == "OPEN")'
```

Discard closed issues. Store remaining as `<plan-issues>` with a
`source: "plan"` tag.

### Short-circuit: clear next issue

If `<plan-issues>` contains exactly one unstarted issue (no open PR, no branch
matching its number), skip Phase 4 — this is the next issue to recommend.

## Phase 3: In-Progress Work

### Open PRs by current user

```bash
gh pr list --author @me --state open --json number,title,headRefName,body,url
```

### Extract linked issues

From each PR, extract linked issue numbers from:

- Branch name patterns (same as Phase 1 feature branch detection)
- PR body keywords: `Closes #N`, `Fixes #N`, `Resolves #N`
- Bare `#N` references in PR body (lower confidence)

Store linked issue numbers as `<pr-issues>` with a `source: "pr"` tag.

### Short-circuit: single open PR

If exactly one open PR exists, skip Phase 4. Present that issue/PR as the
current focus with a note about the existing PR.

## Phase 4: Open Issues

### Fetch assigned issues

```bash
gh issue list --assignee @me --state open --limit 30 \
  --json number,title,labels,milestone,createdAt,body,assignees
```

Store results as `<assigned-issues>`.

### Fetch unassigned issues (conditional)

If `<assigned-issues>` has fewer than 3 items, also fetch unassigned issues:

```bash
gh issue list --state open --limit 20 \
  --json number,title,labels,milestone,createdAt,body,assignees \
  --jq '[.[] | select(.assignees | length == 0)]'
```

Store results as `<unassigned-issues>`.

### Check blocked status

For each candidate issue, check if it is blocked.

**Primary method — GraphQL:**

```bash
gh api graphql -f query='{
  repository(owner: "<owner>", name: "<repo>") {
    issue(number: <N>) {
      trackedInIssues(first: 5) {
        nodes { number title state }
      }
      closedByPullRequestsReferences(first: 5) {
        nodes { number title state }
      }
    }
  }
}'
```

**Fallback — text patterns:**

If GraphQL fails, search the issue body for text indicators:

- `blocked by #<M>`
- `depends on #<M>`
- `waiting on #<M>`

An issue is considered blocked if any referenced blocker is still open. Mark
blocked issues with a `blocked: true` flag and store the blocker numbers.

## Phase 5: Ranking

Assign each candidate issue a priority tier:

| Tier | Source | Description |
|------|--------|-------------|
| 1 | Plan-referenced | Issue found in `.claude/plan/`, PRD, or SPEC |
| 2 | Open PR | Issue linked to your open PR (continue work) |
| 3 | Assigned + milestone | Assigned to you with a milestone deadline |
| 4 | Assigned | Assigned to you, no milestone |
| 5 | Unassigned + referenced | Not assigned but referenced by a recently closed issue |
| 6 | Unassigned + recent | Not assigned, created recently, no plan reference |

### Within-tier ordering

1. Milestone deadline — earliest first
2. Creation date — oldest first

### Blocked issues

Blocked issues are ranked last within their tier. They remain candidates but
are presented with blocker context.

### Deduplication

An issue may appear in multiple sources (plan + assigned, PR + assigned). Use
the highest tier (lowest number) and merge metadata from all sources.

## Phase 6: Ambiguity Gate

### Trigger condition

The ambiguity gate triggers when ALL of these are true:

- No plan files found (Phase 2 skipped)
- No open PRs by current user
- More than 5 candidate issues share the same highest tier

### Auto-scan when candidate count is small

If the total number of unblocked candidate issues is **fewer than 25**, skip
the `AskUserQuestion` prompt and automatically scan all of them — rank by
available signals (labels, milestone, creation date, assignment) and proceed
directly to the Output phase with the top picks.

### Narrow scope (25+ candidates)

If there are **25 or more** unblocked candidate issues, ask how to narrow the
search. Use `AskUserQuestion` when available; otherwise ask directly in chat:

- **question**: "I found N open issues but no plan files to guide priority. How should I narrow down?"
- **Option 1:** `Scan all` `(Recommended)` — `Review all open issues and rank by signals`
- **Option 2:** `By label` — `Filter issues by a specific label first`
- **Option 3:** `By milestone` — `Filter issues by milestone first`
- **Option 4:** `Skip` — `Do not filter, show top picks from full list`

If user picks **By label**, fetch available labels and ask for selection:

```bash
gh label list --json name --jq '.[].name'
```

Then re-fetch issues filtered by the chosen label and re-rank.

If user picks **By milestone**, fetch milestones and ask for selection:

```bash
gh api repos/<owner>/<repo>/milestones --jq '.[].title'
```

Then re-fetch issues filtered by the chosen milestone and re-rank.

## Output

### Present top candidates

After ranking, present the top candidates. Use `AskUserQuestion` when
available; otherwise present up to 4 numbered options in normal chat and ask
the user to choose one.

**Header format:** `Issue #<N>` (must be 12 characters or fewer)

**Description format per option:**

```
<issue-title>
<labels> · <milestone or "no milestone"> · <created date>
<signal explanation: why this issue ranked high>
```

**Rules:**

- Maximum 4 options
- First option is `(Recommended)` — the highest-ranked issue
- Last option is `None` — `Skip issue selection`
- If only one candidate exists, still present it with the `None` alternative
- Blocked issues include a note: `Blocked by #<M> (open)`

### After selection

When the user picks an issue, immediately invoke `issue-analyze` for `#<N>` if
that skill is available in the current agent runtime. Do not output a short
summary first — let `issue-analyze` provide the full structured analysis. If
`issue-analyze` is unavailable, fall back to a brief handoff summary with the
selected issue number, title, and why it ranked first.

If the user picks `None`, output:

```
No issue selected. You can browse issues manually:
<repo issues URL>
```

## Error Handling

| Situation | Action |
|---|---|
| `gh` not authenticated | Stop: `Run 'gh auth login' first.` |
| Not in a git repo | Stop: `Not inside a GitHub repository.` |
| Zero open issues | Stop: `No open issues found in <owner>/<repo>.` |
| All candidates blocked | Present anyway with blocker notes on each |
| GraphQL query fails | Skip silently, fall back to text pattern matching |
| Plan files found but no issue refs | Skip Phase 2, continue to Phase 3 |
| Feature branch with open PR | Short-circuit after Phase 1 |
| No plan files, no PRs, no assigned | Trigger Ambiguity Gate (Phase 6) |
