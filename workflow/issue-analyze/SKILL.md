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
