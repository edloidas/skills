---
name: issue-analyze
description: >
  Fetch a GitHub issue by number or URL, analyze its scope of work, cross-reference local
  project docs and repo instruction files, check blocking relationships, and produce a
  structured implementation analysis with a task list.
when_to_use: >
  Before starting work on an issue, to understand what has to be built and plan the steps.
  Also on "analyze issue #N", "what does this issue involve", or "is anything blocking this".
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash(gh:*) Bash(git:*) Read Glob Grep
arguments: issue
argument-hint: "<issue-number or URL>"
metadata:
  author: edloidas
---

# Issue Analyze

Fetches a GitHub issue, analyzes its full scope, cross-references local project docs,
checks blocking relationships, and outputs a structured analysis with an implementation
task list. Standalone — no forced next step.

**Reports only; the tree stays byte-identical.** Every call it makes is a read: `gh issue
view`, `gh api` **GET**s, `git rev-parse`, and local file reads. `allowed-tools` cannot
express a method restriction, so its `gh` and `git` grants are wider than that — this
sentence is the limit, not the declaration.

## Phase 1: Resolve & Fetch

### Guard: no argument

If `$ARGUMENTS` is empty, stop:

```
Provide an issue number or URL. Usage: /issue-analyze 42
```

### Detect repo

```bash
gh repo view --json nameWithOwner --jq '.nameWithOwner'
```

Outputs `owner/repo`. Split on `/` to get owner and repo name separately.

### Parse argument

`$ARGUMENTS` is either:
- A bare number: `42`
- A full URL: `https://github.com/owner/repo/issues/42`

For a URL, extract the number from the last path segment. If the URL contains a different
owner/repo than the current repo, use the URL's owner/repo for all API calls.

### Fetch the issue

```bash
gh issue view <N> --repo <owner>/<repo> --json number,title,body,state,labels,assignees,url
```

### Detect current user

```bash
gh api user --jq .login
```

### Guard: closed issue

If `state` is `"closed"`:

```
Issue #<N> is closed — no implementation plan needed.

<url>
```

Stop. Do not output anything else.

### Guard: not assigned to you

If `assignees` is non-empty and none match the current user login, print this line before
all other output:

```
> Note: #<N> is assigned to @<other-user> — you may be looking at someone else's work.
```

Then continue normally.

### Fetch sub-issues

```bash
gh api repos/<owner>/<repo>/issues/<N>/sub_issues 2>/dev/null
```

- Empty array `[]` → no sub-issues, skip
- HTTP 404 → sub-issues feature not enabled on this repo, skip silently
- Non-empty array → for each sub-issue number, fetch:

```bash
gh issue view <sub-N> --repo <owner>/<repo> --json number,title,body,state
```

Collect all sub-issue data. A closed sub-issue is noted in the analysis as already
implemented and generates no implementation task.

End Phase 1 with one line: `Fetched #<N> "<title>" — <state>, <N> sub-issues, assigned to
<user|nobody>.`

## Phase 2: Local Context Search

Find the git root:

```bash
git rev-parse --show-toplevel
```

Check whether any of these local context sources exist. If none do, skip this phase
entirely — do not mention it in output.

- `<git-root>/AGENTS.md`
- `<git-root>/CLAUDE.md`
- `<git-root>/.claude/`
- `<git-root>/.agents/`

### Find doc files

Glob for:
- `<git-root>/AGENTS.md`
- `<git-root>/CLAUDE.md`
- `<git-root>/.claude/*.md`
- `<git-root>/.claude/docs/*.md`
- `<git-root>/.agents/*.md`
- `<git-root>/.agents/docs/*.md`
- `<git-root>/docs/superpowers/**/*.md`

If no files found, skip phase.

### Search for issue number

Search **every** file the globs returned — not a sample of them — for:
- `#<N>` (e.g. `#42`)
- Word-boundary match for bare number (to avoid matching `142` when looking for `42`)

### Extract and search key terms

From the issue title and body, extract:
- Capitalized component/module names (e.g. `TreeView`, `AuthService`)
- camelCase or PascalCase identifiers
- File paths mentioned (e.g. `src/components/Button.tsx`)
- Technical terms: API endpoint names, config keys, function names in backticks

Search every found file for each extracted term. Collect unique (file path, matching line)
pairs. Deduplicate across term searches.

### Result

If nothing found across all searches → omit the Local Context section from output.
If matches found → collect as: `{ file: string, reason: string }[]` for use in Phase 4.

End Phase 2 with one line: `Local context: <N> files searched, <N> matched.` A skipped
phase says `Local context: none present.` — say which, never nothing.

## Phase 3: Dependency Analysis

Query issue relationships via GraphQL. Fetch the issue's tracking relationships:

```bash
gh api graphql -f query='{
  repository(owner: "<owner>", name: "<repo>") {
    issue(number: <N>) {
      trackedInIssues(first: 5) {
        nodes { number title state url }
      }
    }
  }
}'
```

`trackedInIssues` — parent issues or epics that track this issue. If this issue is part
of a larger epic, these are the parents.

Also try blocked-by relationships. GitHub stores these via node-ID-based relationships
(same mechanism as `addBlockedBy` / `removeBlockedBy` mutations). Query them directly as
a **separate** call so a failure here does not affect the `trackedInIssues` result:

```bash
gh api graphql -f query='{
  repository(owner: "<owner>", name: "<repo>") {
    issue(number: <N>) {
      blockedByIssues(first: 10) {
        nodes { number title state url }
      }
      blockingIssues(first: 10) {
        nodes { number title state url }
      }
    }
  }
}' 2>&1 || true
```

`blockedByIssues` — what is blocking this issue (must be resolved first).
`blockingIssues` — what this issue blocks (expects deliverables from this one).

These fields are part of GitHub's issue dependencies preview and are not available on
most repos or plans. When unavailable, `gh api` exits with code 1 and prints an
`undefinedField` GraphQL error on **stdout** (not stderr). Handle this silently:

- The `|| true` above prevents the non-zero exit from surfacing as a tool error.
- If the response contains an `errors` field, or any `undefinedField` / `Field '...'
  doesn't exist` message, treat it as "not available" and skip this section.
- Only parse `data.repository.issue.blockedByIssues` / `blockingIssues` when the
  response has no `errors` field.

If all queries fail or return no data, skip silently.

### Relevance filter

For each dependency found:
- **Open blocker** (blocks this issue and is still open): always include — it constrains
  what can be built. Fetch its title and state. Note what it's expected to deliver.
- **Closed blocker**: skip — already resolved, doesn't affect planning.
- **Parent epic**: include only if it adds implementation context not in the issue itself.
- **No dependencies**: omit the Dependencies section from output entirely.

End Phase 3 with one line naming the queries that did not run and why: `Dependencies: <N>
open blockers, <N> parents` or `Dependencies: blockedBy unavailable on this repo; <N>
parents.`

## Phase 4: Synthesize & Output

### Scope Analysis — quality bar

This is the highest-value section. Write it to be directly useful for implementation
planning — not a summary of the issue text, but an interpretation of it.

A high-quality Scope Analysis:
- Explains what the issue is truly asking for (beyond restating the title)
- Identifies technical scope: what needs to be built or changed, and roughly where
- For epics: weaves sub-issues into a coherent narrative, per the Phase 1 rule on closed
  ones. Example: "This epic covers three areas: authentication (#43, done), session
  management (#44), and token refresh (#45)."
- Surfaces implicit requirements not stated in the issue (e.g., "adding X implies Y also
  needs to handle the new input format")
- Calls out ambiguities or decisions the implementer will face
- States what is explicitly out of scope
- When a blocker is open: explains what cannot be built until it's resolved, and what can
  be built in parallel

Length: 2–5 paragraphs for a normal issue; more for a large epic (one paragraph per
sub-issue area).

### Implementation Tasks — quality bar

- Each task is a concrete, actionable step (not "investigate X" — investigation is part
  of Scope Analysis)
- Ordered logically: setup before implementation, implementation before tests, tests
  before integration
- 3–12 tasks (3–4 is fine for small/trivial issues; 5–12 for normal scope)
- For epics: group tasks under sub-issue headings
- If a blocker is open: mark affected tasks as "blocked by #N" and list them last

### Output format

Print output in this exact structure:

````
> Note: #<N> is assigned to @<user> — you may be looking at someone else's work.
(omit line if current user is among assignees, or if issue has no assignees)

# #<N>: <title>

## Scope Analysis

<analysis paragraphs>

## Local Context
(omit entire section if Phase 2 found nothing)

- `.claude/docs/foo.md` — <one sentence on why it's relevant to this issue>

## Dependencies
(omit entire section if no implementation-relevant open dependencies)

Depends on #<M> (open) — <what that issue provides that this one needs>.
This issue's output expected by #<K> — must deliver <Y>.

## Implementation Tasks

1. <task>
2. <task>
3. <task>

---
<issue URL>
````

### A filled-in analysis

```markdown
# #412: Tooltip clips at the viewport edge

## Scope Analysis

The report is about clipping, but the cause is placement: `Tooltip` picks a side once, on
mount, from an anchor rect that `useAnchorRect` has already clamped to the viewport. A
tooltip anchored near the bottom edge therefore measures as if it fits, renders below, and
is cut off. Fixing the clamp alone is not enough — placement has to be re-resolved after
measuring, which means the flip decision moves out of the mount path.

Implicitly in scope: `Popover` consumes the same hook, so returning an unclamped rect
changes its input too. Explicitly out of scope: `Popover`'s own placement logic, which has
a separate clamp of its own and is not what this issue reports.

One decision the implementer faces: re-measure on scroll and resize, or resolve once after
first paint. The issue does not say, and the second is materially cheaper.

## Local Context

- `.claude/docs/overlays.md` — states the overlay layer owns positioning, not the anchor

## Implementation Tasks

1. Return the raw measured rect from `useAnchorRect`; drop the viewport clamp
2. Resolve placement in `Tooltip` after measurement, flipping when the rect overflows
3. Re-check `Popover`'s use of the hook for a regression from the unclamped rect
4. Add a `Tooltip` test asserting resolved placement near the bottom edge

---
https://github.com/owner/repo/issues/412
```

Then stop. This skill analyzes and reports — it does not create a branch, edit a file, or
start implementing, and it does not offer to. A caller that wants the work done invokes
`issue-flow` or `solve-issue` next; that is the caller's decision, not this skill's.

## Error Handling

| Situation | Action |
|---|---|
| `gh` not authenticated | Stop: "Run `gh auth login` first." |
| Not in a git repo + no URL given | Stop: "Provide a full GitHub URL or run from inside a git repository." |
| Issue number not found (`gh` 404) | Stop: "Issue #<N> not found in <owner>/<repo>." |
| Issue body is empty | Analyze from title only; note in Scope Analysis that the issue has no description |
