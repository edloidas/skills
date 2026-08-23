# Issue Selection

The ranking pipeline behind **Step 0: Select Issue**. Gathers local git state, plan
files, open PRs, and the issue backlog, ranks candidates into tiers, and presents the
top picks.

Run the phases in order. Each short-circuit skips straight to **Output**.

Questions here follow **SKILL.md → Conventions → Asking the User**: use the host's
structured-choice tool where it exists, otherwise the same options as a numbered list in
chat. Every command below is a read — Step 0 writes nothing.

## Phase 1: Local Context

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

If `git log @{u}..HEAD` fails there is no upstream — the branch has never been pushed.
Skip it.

### Feature branch detection

If the current branch is not `main`, `master`, `develop`, or `next`, treat it as a
feature branch and extract the issue number (first match wins):

- `feat/<N>-*`, `fix/<N>-*`, `chore/<N>-*`, `refactor/<N>-*` — prefix style
- `issue-<N>-*` or `issue-<N>` — issue prefix style
- `<N>-*` — bare number prefix

`<N>` is one or more digits. Store as `<branch-issue>`.

### Check for an open PR on the current branch

```bash
gh pr list --head "$(git branch --show-current)" --state open --json number,title,url --jq '.[0]'
```

Store as `<current-pr>` if one exists.

### Short-circuit: feature branch with open PR

On a feature branch **and** `<current-pr>` exists → skip Phases 2–4 and ask via
`AskUserQuestion`:

1. `Issue #<N>` `(Recommended)` — `Unfinished work: PR #<pr-number> "<pr-title>". Continue this before picking a new issue.`
2. `New issue` — `Skip current work and pick a different issue.`

Option 1 → show the PR summary and stop. Option 2 → continue from Phase 2.

### Recently merged on base

```bash
git log main --oneline -10 --merges 2>/dev/null || git log master --oneline -10 --merges 2>/dev/null
```

Informational only — identifies recently completed work. Not ranked.

## Phase 2: Plan Files

### Find plan files

Glob for:

- `<git-root>/.claude/plan/*.md`
- `<git-root>/.claude/PRD.md`
- `<git-root>/.claude/SPEC.md`

If none are found, skip this phase.

### Parse issue references

Grep the found files for:

- `#<N>` — hash-number references, on a word boundary so URLs and colour codes like
  `#fff` do not match
- `org/repo#<N>` — cross-repo shorthand
- Full issue URLs: `https://github.com/<owner>/<repo>/issues/<N>`

Collect unique numbers.

### Cross-reference with GitHub

Per extracted number, keep only the ones still open:

```bash
gh issue view <N> --json number,title,state,labels,milestone,assignees --jq 'select(.state == "OPEN")'
```

Store survivors as `<plan-issues>`, tagged `source: "plan"`.

### Short-circuit: clear next issue

If `<plan-issues>` holds exactly one unstarted issue — no open PR, no branch matching
its number — skip Phase 4. That is the recommendation.

## Phase 3: In-Progress Work

### Open PRs by the current user

```bash
gh pr list --author @me --state open --json number,title,headRefName,body,url
```

### Extract linked issues

Per PR, pull issue numbers from:

- The branch name (same patterns as Phase 1)
- Body keywords: `Closes #N`, `Fixes #N`, `Resolves #N`
- Bare `#N` references in the body — lower confidence

Store as `<pr-issues>`, tagged `source: "pr"`.

### Short-circuit: single open PR

Exactly one open PR → skip Phase 4 and present that issue as the current focus, noting
the existing PR.

## Phase 4: Open Issues

### Assigned issues

```bash
gh issue list --assignee @me --state open --limit 30 \
  --json number,title,labels,milestone,createdAt,body,assignees
```

Store as `<assigned-issues>`.

### Unassigned issues (conditional)

Only when `<assigned-issues>` has fewer than 3 items:

```bash
gh issue list --state open --limit 20 \
  --json number,title,labels,milestone,createdAt,body,assignees \
  --jq '[.[] | select(.assignees | length == 0)]'
```

Store as `<unassigned-issues>`.

### Blocked status

Per candidate, check for open blockers. Primary method:

```bash
gh api graphql -f query='{
  repository(owner: "<owner>", name: "<repo>") {
    issue(number: <N>) {
      trackedInIssues(first: 5) { nodes { number title state } }
      closedByPullRequestsReferences(first: 5) { nodes { number title state } }
    }
  }
}'
```

If GraphQL fails, fall back to body text: `blocked by #<M>`, `depends on #<M>`,
`waiting on #<M>`.

An issue is blocked when any referenced blocker is still open. Flag it `blocked: true`
and keep the blocker numbers.

## Phase 5: Ranking

| Tier | Source                  | Description                                                  |
| ---- | ----------------------- | ------------------------------------------------------------ |
| 1    | Plan-referenced         | Found in `.claude/plan/`, PRD, or SPEC                       |
| 2    | Open PR                 | Linked to your open PR — continue work                        |
| 3    | Assigned + milestone    | Assigned to you with a milestone deadline                     |
| 4    | Assigned                | Assigned to you, no milestone                                 |
| 5    | Unassigned + referenced | Not assigned, referenced by a recently closed issue           |
| 6    | Unassigned + recent     | Not assigned, created recently, no plan reference             |

Within a tier: milestone deadline first (earliest), then creation date (oldest first).

Blocked issues rank last within their tier. They stay candidates, presented with
blocker context.

An issue appearing in several sources takes the highest tier (lowest number) and merges
metadata from all of them.

## Phase 6: Ambiguity Gate

Fires only when **all** hold: no plan files, no open PRs by the current user, and more
than 5 candidates share the top tier.

Fewer than 25 unblocked candidates → skip the prompt, rank on the available signals
(labels, milestone, creation date, assignment) and go to Output.

25 or more → ask via `AskUserQuestion`:

- **question**: "I found N open issues but no plan files to guide priority. How should I narrow down?"
- **Option 1** — `Scan all` `(Recommended)` — `Review all open issues and rank by signals.`
- **Option 2** — `By label` — `Filter by a specific label first.`
- **Option 3** — `By milestone` — `Filter by milestone first.`
- **Option 4** — `Skip` — `Show top picks from the full list without filtering.`

**By label** → `gh label list --json name --jq '.[].name'`, ask which, re-fetch filtered
and re-rank. **By milestone** → `gh api repos/<owner>/<repo>/milestones --jq '.[].title'`,
same procedure.

## Output

Present the top candidates via `AskUserQuestion`.

**Header:** `Issue #<N>` — must be 12 characters or fewer.

**Description per option:**

```
<issue-title>
<labels> · <milestone or "no milestone"> · <created date>
<why this issue ranked high>
```

Rules:

- At most 4 options
- First option is `(Recommended)` — the highest-ranked issue
- Last option is `None` — `Skip issue selection`
- A single candidate is still presented, with the `None` alternative
- Blocked candidates carry a note: `Blocked by #<M> (open)`

### After selection

Invoke the `issue-analyze` skill on `<N>` immediately. Do not print a summary first —
the analysis is the output. If the host cannot chain skills, or `issue-analyze` is not
installed, fall back to a brief handoff: issue number, title, and why it ranked first.

`None` → print:

```
No issue selected. You can browse issues manually:
<repo issues URL>
```

## Error Handling

| Situation                             | Action                                                  |
| ------------------------------------- | ------------------------------------------------------- |
| Zero open issues                      | Stop: `No open issues found in <owner>/<repo>.`         |
| All candidates blocked                | Present anyway, with blocker notes on each              |
| GraphQL query fails                   | Skip silently, fall back to text pattern matching       |
| Plan files found but no issue refs    | Skip Phase 2, continue to Phase 3                       |
| Feature branch with open PR           | Short-circuit after Phase 1                             |
| No plan files, no PRs, none assigned  | Ambiguity gate (Phase 6)                                |
