# issue-analyze Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a `workflow/issue-analyze` skill that fetches a GitHub issue, analyzes its scope, cross-references local docs, checks dependencies, and outputs a rich implementation analysis with a task list.

**Architecture:** Sequential single-pass skill. Four phases run in order: fetch issue + sub-issues, search local `.claude/` docs, query blocking relationships via GraphQL, synthesize all data into a structured markdown output. No subagents. Standalone — does not transition to any other skill.

**Tech Stack:** `gh` CLI, GitHub REST API, GitHub GraphQL API, `Glob`/`Grep` tools for local doc search.

---

### Task 1: Create skill directory and write SKILL.md frontmatter

**Files:**
- Create: `workflow/issue-analyze/SKILL.md`

**Step 1: Create directory**

```bash
mkdir workflow/issue-analyze
```

**Step 2: Write `workflow/issue-analyze/SKILL.md`**

Write exactly this content — body will be added in subsequent tasks:

```markdown
---
name: issue-analyze
description: >
  Fetches a GitHub issue by number or URL, analyzes its scope of work, cross-references
  local project docs in .claude/, checks blocking relationships, and produces a structured
  implementation analysis with a task list. Use before starting work on any issue to
  understand what needs to be built and plan implementation steps.
license: MIT
compatibility: Claude Code
model: claude-sonnet-4-6
allowed-tools: Bash(gh:*) Bash(git:*) Read Glob Grep
arguments: "issue-number"
argument-hint: "[issue-number or URL]"
metadata:
  author: edloidas
---

# Issue Analyze

Fetches a GitHub issue, analyzes its full scope, cross-references local project docs,
checks blocking relationships, and outputs a structured analysis with an implementation
task list. Standalone — no forced next step.
```

**Step 3: Commit**

```bash
git add workflow/issue-analyze/SKILL.md
git commit -m "feat: scaffold issue-analyze skill"
```

---

### Task 2: Write Phase 1 — Resolve & Fetch

**Files:**
- Modify: `workflow/issue-analyze/SKILL.md`

**Step 1: Append Phase 1 content to SKILL.md**

Append after the intro paragraph:

````markdown

## Phase 1: Resolve & Fetch

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

Collect all sub-issue data. Closed sub-issues are noted in the analysis as already done
but do not generate implementation tasks.
````

**Step 2: Verify file looks correct**

```bash
head -80 workflow/issue-analyze/SKILL.md
```

**Step 3: Commit**

```bash
git add workflow/issue-analyze/SKILL.md
git commit -m "feat: add phase 1 resolve and fetch to issue-analyze"
```

---

### Task 3: Write Phase 2 — Local Context Search

**Files:**
- Modify: `workflow/issue-analyze/SKILL.md`

**Step 1: Append Phase 2 content**

````markdown

## Phase 2: Local Context Search

Find the git root:

```bash
git rev-parse --show-toplevel
```

Check whether `<git-root>/.claude/` exists. If absent, skip this phase entirely — do not
mention it in output.

### Find doc files

Use `Glob` tool to find:
- `<git-root>/.claude/*.md`
- `<git-root>/.claude/docs/*.md`

If no files found, skip phase.

### Search for issue number

Use `Grep` to search all found files for:
- `#<N>` (e.g. `#42`)
- Word-boundary match for bare number (to avoid matching `142` when looking for `42`)

### Extract and search key terms

From the issue title and body, extract:
- Capitalized component/module names (e.g. `TreeView`, `AuthService`)
- camelCase or PascalCase identifiers
- File paths mentioned (e.g. `src/components/Button.tsx`)
- Technical terms: API endpoint names, config keys, function names in backticks

Use `Grep` to search all found files for each extracted term. Collect unique
(file path, matching line) pairs. Deduplicate across term searches.

### Result

If nothing found across all searches → omit the Local Context section from output.
If matches found → collect as: `{ file: string, reason: string }[]` for use in Phase 4.
````

**Step 2: Commit**

```bash
git add workflow/issue-analyze/SKILL.md
git commit -m "feat: add phase 2 local context search to issue-analyze"
```

---

### Task 4: Write Phase 3 — Dependency Analysis

**Files:**
- Modify: `workflow/issue-analyze/SKILL.md`

**Step 1: Append Phase 3 content**

````markdown

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

Also try blocked-by relationships (may not be available on all repos):

```bash
gh api graphql -f query='{
  repository(owner: "<owner>", name: "<repo>") {
    issue(number: <N>) {
      blockedByIssues: references(first: 10) {
        nodes { number title state url }
      }
    }
  }
}' 2>/dev/null
```

If either query fails or returns no data, skip silently.

### Relevance filter

For each dependency found:
- **Open blocker** (blocks this issue and is still open): always include — it constrains
  what can be built. Fetch its title and state. Note what it's expected to deliver.
- **Closed blocker**: skip — already resolved, doesn't affect planning.
- **Parent epic**: include only if it adds implementation context not in the issue itself.
- **No dependencies**: omit the Dependencies section from output entirely.
````

**Step 2: Commit**

```bash
git add workflow/issue-analyze/SKILL.md
git commit -m "feat: add phase 3 dependency analysis to issue-analyze"
```

---

### Task 5: Write Phase 4 — Synthesize & Output

**Files:**
- Modify: `workflow/issue-analyze/SKILL.md`

**Step 1: Append Phase 4 content**

````markdown

## Phase 4: Synthesize & Output

### Scope Analysis — quality bar

This is the highest-value section. Write it to be directly useful for implementation
planning — not a summary of the issue text, but an interpretation of it.

A high-quality Scope Analysis:
- Explains what the issue is truly asking for (beyond restating the title)
- Identifies technical scope: what needs to be built or changed, and roughly where
- For epics: weaves sub-issues into a coherent narrative. Example: "This epic covers three
  areas: authentication (#43, done), session management (#44), and token refresh (#45)."
  Closed sub-issues are noted as already implemented and excluded from tasks.
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
- 5–12 tasks for a normal issue
- For epics: group tasks under sub-issue headings
- If a blocker is open: mark affected tasks as "blocked by #N" and list them last

### Output format

Print output in this exact structure:

```
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
```

## Error Handling

| Situation | Action |
|---|---|
| `gh` not authenticated | Stop: "Run `gh auth login` first." |
| Not in a git repo + no URL given | Stop: "Provide a full GitHub URL or run from inside a git repository." |
| Sub-issues API returns 404 | Skip silently |
| No `.claude/` directory | Skip local context phase silently |
| GraphQL returns error or empty data | Skip dependencies section silently |
| Issue body is empty | Analyze from title only; note in Scope Analysis that the issue has no description |
````

**Step 2: Verify full file**

```bash
wc -l workflow/issue-analyze/SKILL.md
```

Expected: under 300 lines.

**Step 3: Commit**

```bash
git add workflow/issue-analyze/SKILL.md
git commit -m "feat: add phase 4 output synthesis to issue-analyze"
```

---

### Task 6: Update README.md

**Files:**
- Modify: `README.md:109` (workflow skills table, insert `issue-analyze` between `issue-flow` and `issue-writer` — alphabetical order)

**Step 1: Insert row into workflow table**

The table is sorted alphabetically. `issue-analyze` goes between `issue-flow` and `issue-writer`. Add this row:

```markdown
| [issue-analyze](./workflow/issue-analyze/)                  | Analyze issue scope and produce an implementation task list               | Claude        |
```

**Step 2: Verify table alignment looks correct**

```bash
grep -A2 -B2 "issue-analyze" README.md
```

**Step 3: Commit**

```bash
git add README.md
git commit -m "docs: add issue-analyze to workflow skills table"
```

---

### Task 7: Verify skill

**Step 1: Check frontmatter name matches directory**

```bash
grep "^name:" workflow/issue-analyze/SKILL.md
```

Expected output: `name: issue-analyze`

**Step 2: Check line count is within recommended limit**

```bash
wc -l workflow/issue-analyze/SKILL.md
```

Expected: under 300 lines (CLAUDE.md recommends under 500 lines / ~5000 tokens for skill body).

**Step 3: Run skill-audit if available**

Invoke the `skill-audit` skill pointing at `workflow/issue-analyze/`. If skill-audit is not available, skip this step.

**Step 4: Verify directory structure**

```bash
ls -la workflow/issue-analyze/
```

Expected:
```
SKILL.md
```

No extra files needed — all phases are self-contained in SKILL.md using inline `gh` commands and built-in tools.
