# Issue Selection

The ranking pipeline behind **Step 0: Select Issue**. Gathers local git state, plan
files, open PRs, and the issue backlog, ranks candidates into tiers, and presents the
top picks.

Run the phases in order. A short-circuit skips the remaining discovery phases and goes
to **Output**; it does not skip the selection itself.

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

On a feature branch **and** `<current-pr>` exists → skip Phases 2–4.

First check that the branch name yielded a `<branch-issue>` number. If it did not, there
is nothing to select and nothing to analyse: report the open PR and stop. Do not ask the
question below — its first option is labelled `Issue #<N>` and there is no `<N>`.

With a number in hand, ask via `AskUserQuestion`:

1. `Issue #<N>` `(Recommended)` — `Unfinished work: PR #<pr-number> "<pr-title>". Continue this before picking a new issue.`
2. `New issue` — `Skip current work and pick a different issue.`

Option 1 → this **is** a selection, so treat it as one: report the PR context, then go to
**Output → After selection** like any other pick. Callers are told selection always ends
in an analysis, and one that stopped at a PR summary would leave them running with no
scope analysis and no resolved issue title.

Option 2 → continue from Phase 2.

### Recently merged on base

```bash
git log main --oneline -10 --merges 2>/dev/null || git log master --oneline -10 --merges 2>/dev/null
```

Informational only — identifies recently completed work. Not ranked.

## Phase 2: Plan Files

### Find plan files

Glob for:

- `<git-root>/docs/superpowers/*.md` — specs and plans
- `<git-root>/.claude/plan/*.md`, `<git-root>/.claude/plans/*.md`
- `<git-root>/.agents/plan/*.md`
- `<git-root>/.claude/PRD.md`, `<git-root>/.claude/SPEC.md`
- `<git-root>/docs/PRD.md`, `<git-root>/docs/SPEC.md`

Where the repo's own instructions file names a plan directory, prefer that over the list
above — it is the authoritative answer for that repo. If nothing is found, skip this
phase; Tier 1 then never fires, which is expected in a repo that keeps no plans.

The `.claude/` entries are one host's convention, not the only one. Do not treat their
absence as "no plans exist".

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

Per candidate, check for open blockers. The field is `blockedByIssues` — the same
relationship SKILL.md's **Blocked-By** section writes with `addBlockedBy`. Issue it as a
**separate** best-effort call, since it is part of GitHub's issue-dependencies preview
and is unavailable on most repos and plans:

```bash
gh api graphql -f query='{
  repository(owner: "<owner>", name: "<repo>") {
    issue(number: <N>) {
      blockedByIssues(first: 10) { nodes { number title state } }
    }
  }
}' 2>&1 || true
```

When the field is unavailable, `gh api` exits 1 and prints an `undefinedField` GraphQL
error on **stdout**. The `|| true` keeps that from surfacing as a tool error; treat any
response carrying an `errors` field as "not available" and parse
`data.repository.issue.blockedByIssues` only when it does not.

Do **not** read `trackedInIssues` or `closedByPullRequestsReferences` as blockers.
Neither is one: `trackedInIssues` is the parent or epic that *tracks* the issue (see
`issue-analyze`, which documents the same field), and an open PR that would close the
issue is the opposite of a blocker. Treating them as blockers flags every child of an
open epic as blocked and buries the whole epic at the bottom of the ranking.

If the query is unavailable, fall back to body text: `blocked by #<M>`,
`depends on #<M>`, `waiting on #<M>`.

An issue is blocked when any referenced blocker is still open. Flag it `blocked: true`
and keep the blocker numbers.

## Phase 5: Ranking

| Tier | Source                  | Description                                                  |
| ---- | ----------------------- | ------------------------------------------------------------ |
| 1    | Plan-referenced         | Found in a plan, PRD, or SPEC file (see Phase 2)             |
| 2    | Open PR                 | Linked to your open PR — continue work                        |
| 3    | Assigned + milestone    | Assigned to you with a milestone deadline                     |
| 4    | Assigned                | Assigned to you, no milestone                                 |
| 5    | Unassigned + recent     | Not assigned, created recently, no plan reference             |

Within a tier: milestone deadline first (earliest), then creation date (oldest first).

Blocked issues rank last within their tier. They stay candidates, presented with
blocker context.

An issue appearing in several sources takes the highest tier (lowest number) and merges
metadata from all of them.

## Phase 6: Ambiguity Gate

Fires only when **all** hold: no plan files, no open PRs by the current user, and
25 or more unblocked candidates share the top tier.

Below that, rank on the available signals (labels, milestone, creation date, assignment)
and go to Output without asking. Narrowing 6 candidates by label costs the user a
question and saves nothing.

When it fires, ask via `AskUserQuestion`:

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

**Header:** `Issue #<N>` — must be 12 characters or fewer. That holds to four digits;
for a longer number drop the word and use `#<N>` alone.

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
| No plan files, no PRs, 25+ candidates | Ambiguity gate (Phase 6)                                |
