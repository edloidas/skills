---
name: review-comments
description: >
  Analyze PR review comments — fetch inline and general comments, filter resolved threads,
  and produce a triaged report of what to fix and what to skip.
  Use when the user asks to address, check, or review PR feedback and comments.
license: MIT
compatibility: Claude Code, Codex
allowed-tools: Bash Read Glob Grep
argument-hint: "[PR number or empty for auto-detect]"
metadata:
  author: edloidas
---

# Review Comments

## Purpose

Fetch PR review comments (inline and general), analyze each against the code context, and produce a triaged report. Does not auto-fix — outputs analysis only. The "To Fix" section is structured for downstream consumption by `fix-findings`.

## When to Use

Use when the user asks to:
- Address or check PR review comments
- Review feedback left on a pull request
- Triage PR comments before fixing

Trigger phrases: "review comments", "address review", "check PR feedback", "PR comments", "address comments"

## Input Resolution

Determine the target PR:

1. If `$ARGUMENTS` is a number, use it as the PR number
2. Otherwise, detect from the current branch:

```bash
gh pr list --head "$(git branch --show-current)" --json number,title,url --jq '.[0]'
```

3. If no PR is found, report an error:

> No open PR found for the current branch. Specify a PR number: `/review-comments 42`

Once resolved, fetch PR metadata and display: **Reviewing PR #N: Title** (with URL).

## Data Fetching

Fetch from two sources. Extract `owner/repo` from `gh repo view --json nameWithOwner --jq '.nameWithOwner'`.

### Review comments (inline on code)

Use GraphQL to fetch review threads with resolution state:

```bash
gh api graphql -f query='
query($owner: String!, $repo: String!, $pr: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100) {
        nodes {
          isResolved
          isOutdated
          path
          line
          diffSide
          comments(first: 50) {
            nodes {
              author { login }
              body
              createdAt
            }
          }
        }
      }
    }
  }
}' -f owner='<owner>' -f repo='<repo>' -F pr='<number>'
```

**Filter out:** threads where `isResolved` is `true`.

Each unresolved thread becomes one item. The first comment is the root; subsequent comments are the conversation.

### General comments (conversation-level)

```bash
gh api repos/<owner>/<repo>/issues/<number>/comments \
  --jq '[.[] | {author: .user.login, body: .body, created_at: .created_at}]'
```

Each general comment becomes one standalone item (no file/line context).

**Exclude:** bot comments (users with `[bot]` suffix or known CI bots).

## Analysis

Process each item (thread or general comment) sequentially:

1. **Read** the reviewer's feedback — all comments in the thread
2. **Understand context** — use the `path` and `line` from the thread; read the current file around that line if the feedback isn't clear from the comment alone
3. **Verdict** — classify as **fix** or **skip**:
   - **fix**: The reviewer's point is valid. Describe what needs to change.
   - **skip**: The reviewer's point is invalid, already handled, or intentional. Explain why.
4. **Title** — write a concise title summarizing the concern

### Verdict guidelines

Lean toward **fix** when:
- The reviewer identified a genuine bug or logic error
- The suggestion improves correctness, safety, or clarity
- The code doesn't match documented patterns or conventions

Lean toward **skip** when:
- The current code is intentional and the reviewer missed context
- The reviewer's suggestion would introduce a regression or conflict
- The concern is about style preference with no objective improvement
- The issue is already addressed elsewhere in the PR

## Output Format

### Summary line

```
**PR #<number> Review: N comments, X to fix, Y skipped**
```

### Sections

Show "To Fix" first, then "Skipped". Omit empty sections. Numbering is continuous across both sections.

**To Fix items:**

```
**N. Title summarizing the concern**
**@username** on `file.ts:42`
> original comment (including ```suggestion``` blocks verbatim)

**Fix:** What needs to change
```

**Skipped items:**

```
**N. Title summarizing the concern**
**@username** on `file.ts:88`
> original comment

**Skip:** Reason — intentional design choice / incorrect assumption / already handled
```

**General comments** (no file context): show `**@username**` without the `on` part.

**Thread with multiple comments**: show the root comment in the blockquote. If follow-up comments add important context, append them as nested blockquotes:

```
> root comment
>
> > @other-reviewer: follow-up adding context
```

## Rules

1. **Analysis only** — never auto-fix; output is for the user (or `fix-findings`) to act on
2. **Preserve reviewer's words** — blockquote the original comment verbatim, including suggestions
3. **Be honest in skips** — don't dismiss valid feedback; if skipping, give a real technical reason
4. **Read the code** — don't guess from the comment alone; check the actual file when the diff context isn't enough
5. **No scope expansion** — analyze what the reviewer said, don't add your own review findings
6. **Filter resolved** — resolved threads are already handled, skip them entirely

## Keywords

review comments, PR feedback, pull request, address review, triage comments, code review
