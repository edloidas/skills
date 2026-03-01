# issue-analyze Skill Design

**Date:** 2026-03-01
**Status:** Approved

## Overview

A workflow skill that fetches a GitHub issue by number or URL, analyzes its scope, cross-references local project documentation, checks blocking relationships, and produces a structured implementation analysis with a task list. Standalone output — no forced transition to planning.

## Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Architecture | Sequential single-pass | Simple, predictable, easier to debug |
| Sub-issue depth | 1 level | Covers epics; recursive adds complexity without clear value |
| Local context search | Issue number + keywords | Widest relevant net without semantic search overhead |
| Skill end state | Standalone | User decides what to do next |
| Model | `claude-sonnet-4-6` | Complex synthesis task; consistent with other workflow skills |

## Location

`workflow/issue-analyze/SKILL.md`

## Arguments

`$ARGUMENTS` — issue number (`42`) or full GitHub URL (`https://github.com/owner/repo/issues/42`).

## Phase Breakdown

### Phase 1 — Resolve & Fetch

1. Detect current repo: `gh repo view --json nameWithOwner,url`
2. Parse `$ARGUMENTS`: extract issue number from URL if needed
3. Fetch issue: `gh issue view <N> --json number,title,body,state,labels,assignees,url`
4. Detect current user: `gh api user --jq .login`
5. Guard: if issue is **closed** → print notice + URL, stop
6. Guard: if no assignee matches current user → print one-line heads-up (continue anyway)
7. Check sub-issues: `gh api repos/<owner>/<repo>/issues/<N>/sub_issues`
8. If sub-issues exist, fetch each: `gh issue view <sub-N> --json number,title,body,state`

### Phase 2 — Local Context Search

Target directory: repo working directory (current dir or detected from git root).

1. Look for `.claude/` directory — skip entirely if absent
2. Glob `.claude/*.md` and `.claude/docs/*.md`
3. Search for issue number (`#N`, bare `N`) across all found files
4. Extract key terms from issue title + body: component names, feature areas, mentioned file paths, technical terms
5. Search for those terms across the same files
6. Collect: file path + matching lines (deduplicated)

### Phase 3 — Dependency Analysis

Using GraphQL (same approach as `issue-flow/references/github-relationships.md`):

1. Fetch node ID for the issue
2. Query blocking relationships (what this blocks, what blocks this)
3. For each dependency, fetch its title + state
4. Determine implementation relevance:
   - Blocked-by open issues: relevant (may constrain what can be built)
   - Blocking issues: relevant if they clarify expected deliverables
   - Closed dependencies: informational only, skip unless they explain scope

### Phase 4 — Synthesize & Output

Output format:

```
> Note: #N is assigned to @other-user — you may be working on someone else's issue.
(only if current user is not among assignees)

# #N: <title>

## Scope Analysis

<Rich, high-quality analysis:
  - What the issue is truly asking for (not just restating title)
  - Technical scope: what needs to be built or changed
  - For epics: narrative coverage of sub-issues, noting which are done
  - Edge cases and open questions the issue raises
  - Explicit out-of-scope boundaries
  - Anything the blocker/dependency context adds to understanding>

## Local Context
(section omitted entirely if nothing found)

- `.claude/docs/foo.md` — <why it's relevant>

## Dependencies
(section omitted entirely if no implementation-relevant deps)

Depends on #N (open) — provides X, required here.
This issue's output expected by #M — must deliver Y.

## Implementation Tasks

1. ...
2. ...
3. ...

---
<issue URL>
```

## Tool Requirements

```yaml
allowed-tools: Bash(gh:*) Bash(git:*) Read Glob Grep
```

## Error Handling

- `gh` not authenticated → stop, tell user to run `gh auth login`
- Not in a git repo → try to parse URL for owner/repo; fail if URL not given
- Sub-issues API returns 404 → skip sub-issue fetch silently (feature not enabled on repo)
- No `.claude/` directory → skip local context phase silently
- GraphQL blocked-by returns no data → skip dependencies section

## Scope Analysis Quality Bar

This is the highest-value output. It must:
- Go beyond restating the issue description
- Identify implicit requirements not stated in the issue
- Call out ambiguities or decisions the implementer will need to make
- Connect sub-issues into a coherent narrative (for epics)
- Incorporate blocker/dependency context when it shapes what to build
- Note what this issue deliberately does NOT cover
