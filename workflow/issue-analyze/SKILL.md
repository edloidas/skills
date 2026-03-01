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
