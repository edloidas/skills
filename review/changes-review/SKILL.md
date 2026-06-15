---
name: changes-review
description: >
  Deep logic analysis of code changes. Runs repo-native tooling and convention
  checks first, then reviews logic errors, behavior gaps, and missing
  requirements that automated checks miss. Uses Claude plugin subagents in
  Claude Code and built-in subagents in Codex.
license: MIT
compatibility: Claude Code, Codex
allowed-tools: Bash Read Glob Grep Edit Write Task AskUserQuestion
argument-hint: "[commits, path, range, or empty] [--no-build] [--no-issue]"
metadata:
  author: edloidas
---

# Review Code Changes

## Purpose

Perform deep logic analysis of changed files. Delegates tooling checks and convention validation to specialized agents, then focuses on finding logic errors, behavior gaps, and missing business requirements that automated tools cannot detect.

## Compatibility

This skill may mutate the working tree when the project exposes a repo-native
autofix-capable lint or check command. Expose it to Codex only as an explicitly
invoked skill.

Host-specific dispatch:
- **Claude Code**: use the bundled `review:review-build` and
  `review:review-rules` plugin agents
- **Codex**: read `references/review-build-prompt.md` and
  `references/review-rules-prompt.md`, then dispatch built-in subagents with the
  same target file list
- **Fallback**: if the host cannot spawn subagents, run the tooling and
  convention passes inline before the logic review

## When to Use This Skill

Use when the user asks to:
- Review code changes before commit
- Analyze recent commits for issues
- Check changes in specific files or directories
- Review a commit range

Trigger phrases: "review changes", "review my code", "check changes", "analyze commits", "code review"

## Dependencies

This skill runs two supporting passes before the logic review:

| Subagent | Type | Purpose |
|----------|------|---------|
| Tooling pass | Mutating when autofix exists | Runs project checks and the best repo-native fix-capable lint/check command if one exists, returns TOOLING_REPORT |
| Convention pass | Read-only | Checks files against project conventions, returns CONVENTION_REPORT |

**Fallback:** If either agent fails, proceed with the other's report and note the gap in output. If both fail, perform logic analysis standalone and note that tooling/convention checks were skipped.

## Commands

| Command | Description |
|---------|-------------|
| `/changes-review` | All changes (staged + unstaged), or last commit if clean |
| `/code:review-changes last N commits` | Changes in last N commits |
| `/code:review-changes path/` | Changes in directory |
| `/code:review-changes file.ext` | Specific file |
| `/code:review-changes HEAD~N..HEAD` | Commit range |
| `/code:review-changes --no-build` | Skip the tooling/build pass (combinable with any scope above) |
| `/code:review-changes --no-issue` | Skip the issue/PR context pass (combinable with any scope above) |

**Skip-build flag:** Pass `--no-build` (or `--skip-build`) anywhere in the arguments to bypass
the tooling pass. Natural-language equivalents are also accepted when the user phrases the
request directly: "no build", "skip build", "without build", "don't run build", "skip tooling".
When matched, omit the flag/phrase from the scope before resolving paths or commit ranges.

**Skip-issue flag:** Pass `--no-issue` (or `--skip-issue`) anywhere in the arguments to bypass
issue/PR context fetching. Natural-language equivalents: "no issue", "skip issue",
"without issue", "no PR", "skip PR", "no context", "don't fetch issue". When matched, omit
the flag/phrase from the scope before resolving paths or commit ranges.

**Issue context is auto-detected.** Unless `--no-issue` is set, the skill always tries to
resolve an issue/PR for the current branch — no user input required. See "Issue context
pass" in Step 2 for the detection chain. If nothing resolves, the pass produces no output
and the audit step is skipped.

## Workflow

### Phase 1: Gather Context

**Step 1: Determine Scope**

```bash
git diff --name-status
git diff --cached --name-status
# If clean, use last commit:
git diff --name-status HEAD~1..HEAD
```

Filter out: `*-lock.*`, `dist/`, `build/`, `.next/`, `*.d.ts`, `*.min.js`, `*.map`

**Trivial diffs:** If ONLY version bumps, formatting, lock files → "Trivial changes only. No review needed." and stop.

**Step 2: Run Tooling + Convention + Issue Context Passes (parallel)**

Use the same target file list for the tooling and convention passes.

If the user passed `--no-build` (or any natural-language skip-build phrase from the
"Skip-build flag" note above), skip the tooling pass entirely. Run only the convention
pass, set `TOOLING_REPORT = SKIPPED (user requested --no-build)`, and continue.

Always dispatch the issue context pass (see below) unless the user passed `--no-issue` (or
any natural-language skip-issue phrase from the "Skip-issue flag" note above). When skipped,
set `ISSUE_CONTEXT = SKIPPED (user requested --no-issue)` and continue. Otherwise the pass
auto-detects an issue/PR from the current branch and exits silently when nothing resolves.

**Claude Code path**

- Dispatch `review:review-build` with a prompt that includes:
  - the resolved scope
  - the target file list
  - "Use the repo's preferred quick checks and run the best fix-capable lint or
    check command if one exists. Return TOOLING_REPORT."
- Dispatch `review:review-rules` with a prompt that includes:
  - the same target file list
  - "Check these files against project conventions and return
    CONVENTION_REPORT."

**Codex path**

- Read `references/review-build-prompt.md`
- Use it as the prompt body for a built-in `worker` subagent and append:
  - the resolved scope
  - the target file list
- Read `references/review-rules-prompt.md`
- Use it as the prompt body for a built-in `explorer` subagent and append:
  - the same target file list

Wait for all dispatched reports before proceeding.

**Issue context pass**

Dispatch a parallel subagent (Claude Code: `general-purpose`; Codex: `explorer`) that
runs `scripts/fetch-issue-context.sh` from this skill directory with no arguments.

The script auto-detects an issue/PR for the current branch in this order:
1. Open PR for the current branch (and its linked closing issue, if any)
2. Branch name matching `issue-<N>`
3. `#<N>` in the last commit message

Capture stdout as `ISSUE_CONTEXT`. Empty stdout means nothing resolved — treat as no
context, skip the requirements audit, and do not surface this in the final review.

**Step 2.5: Refresh Diff After Autofix**

Skip this step entirely when the tooling pass was skipped via `--no-build`.

If the tooling pass reports autofixes or otherwise changed files:
- rerun the scope detection commands
- rebuild the target file list from the post-fix diff
- use the refreshed diff for all remaining analysis
- mention in the final review that findings were produced after repo-native
  autofixes were applied

**Step 3: Identify Reference**

If replacing existing functionality:
- Search for similar class/component names
- Note pattern reference (modern example) and business logic reference (legacy being replaced)

### Phase 2: Logic Analysis

**Focus on what tooling CANNOT find:**
- Logic errors and incorrect behavior
- Missing business requirements
- Behavior gaps vs reference
- Error recovery failures
- Edge cases

**Requirements audit (when `ISSUE_CONTEXT` is non-empty):**

Read `ISSUE_CONTEXT` and cross-check it against the diff:
- Issue description → does the diff implement what's asked? Missing behavior → flag.
- Out-of-scope items mentioned in description or comments → respected? Violation → flag.
- Unresolved review threads → addressed in the current diff? If not, surface as a finding
  referencing the file:line and reviewer.
- PR conversation comments → any pending decisions or scope changes the diff ignores?

When `ISSUE_CONTEXT` is empty or `SKIPPED`, skip this audit silently.

**Reference Reading (if applicable):**

1. Read legacy implementation COMPLETELY
2. Create behavior checklist:
```
REFERENCE CHECKLIST: [FileName.ts]
- User actions: What can user DO?
- Validations: What checks happen?
- Functions: open(), close(), execute(), cancel()
- Error recovery: What happens on failure?
```

**Logic Audits:**

**Function Parity:**
```
FUNC [name]:
- ref_guards: [condition1, condition2, ...]
- new_guards: [condition1, ...]
- MISSING: [condition2] ← flag if absent
```

**Dead Code Check:**
```
VAR [name]: declared at :line, used in logic: [Y/N]
```

**Error Recovery:**
```
ERROR_FLOW [action]:
- Dialog closes: [before/after try-catch]
- On error: [stays open / already closed]
- Can retry: [Y/N]
```

### Phase 3: Aggregate & Output

Combine from:
1. **TOOLING_REPORT** (review-build) → Type errors, lint, build/test failures. When skipped via `--no-build`, note "Tooling pass skipped per user request" in the summary instead.
2. **CONVENTION_REPORT** (review-rules) → Pattern violations
3. **ISSUE_CONTEXT** (issue-context pass, when non-empty) → Requirements coverage, unresolved PR feedback, open questions. Omit silently when empty.
4. **Logic Analysis** (this review) → Behavior gaps, missing features

## Output Format

**Summary Line:**
`**Review: X critical, Y moderate, Z suggestions in N files**`

**Sections (only include if findings exist):**

### Critical Issues
Use when: Build fails, user workflow blocked, data loss risk, can't retry after error, security hole

```
**N. Title** (`file.ext:line`)
**Problem**: What's wrong
**Impact**: What breaks
**Fix**: Specific solution
```

### Moderate Issues
Use when: Edge case fails, missing feature vs reference, behavior differs

### Suggestions
Use when: Style inconsistency, convention violation, missing helper

**Priority Table:**

| # | Task | Severity | Complexity | Location |
|---|------|----------|------------|----------|
| 1 | ... | Critical | Low | `file:line` |

Complexity: Low · Medium · High

## Phase 4: Post-Review Actions

After presenting the review, offer next actions. **Skip this phase entirely when there are no findings** — trivial or clean reviews just end.

In Claude Code, prompt with `AskUserQuestion`. Where the host cannot prompt interactively (e.g. Codex), list the same options as plain text and act on the user's reply.

**Top-level prompt (single choice):**

- **Fix findings** — apply fixes to the working tree
- **Comment in PR** — draft inline review comments on the branch's PR. Offer this option only when the issue-context pass resolved a PR; otherwise omit it.
- **Skip** — stop; the user takes it from here

Keep it single-choice. The user can re-run the skill to take another action.

### Fix findings

Build the severity options **adaptively from the tiers present this run** — never offer an empty bucket:

- `Critical only` — when any critical exists
- `Critical + Moderate` — when both exist
- `Everything` — all present tiers
- `Pick numbers…` — the user names finding numbers from the priority table

Apply the selected fixes, then:
- run the repo-native verify command (skip under `--no-build`)
- report what changed and the check result

### Comment in PR

Resolve the PR from the issue-context pass (Phase 1), then:

1. **Target a pending review.** If a pending review by the current user already exists on the PR, append to it; otherwise create a new pending review. **Leave it UNSUBMITTED** — the user reviews and submits.
2. **Choose which findings to comment.** If the user already named findings or severities in their request to this skill, honor that without asking. Otherwise prompt, defaulting to: **Critical preselected (always include), Moderate optional, Suggestions off by default**, plus an option to specify finding numbers.
3. **Write each comment** anchored to its `file:line`, following `## PR Comment Style`. Every comment body **starts with `✴️ `**.
4. Report the pending review link and that it is left unsubmitted.

Post with the host's PR tooling — e.g. `gh api .../pulls/{n}/reviews` to create a pending review, or GraphQL `addPullRequestReviewThread` against an existing pending review's node id to append to it.

## PR Comment Style

Applies to every PR comment the skill drafts. Each body starts with `✴️ ` — the only emoji allowed — so generated comments are easy to spot.

**Order — what, then why, then fix:**

1. **What** — the problem, in plain language: what happens.
2. **Why** — the impact: why it matters (e.g. "makes the UX worse", "nothing gets seeded").
3. **Fix** — a suggestion at the end, pointing to the specific symbol, line, or file.

Write it as flowing prose, not labeled "Problem / Impact / Fix" scaffolding.

**Rules:**

- Be concise; don't inflate. Calibrate severity honestly ("not a hard error, but worse UX"). Length follows the finding — short by default, longer only when it needs it.
- Direct, but never blame the developer. Assuming an oversight is fine; no fixed phrase is required.
- Phrase asks neutrally: "Please implement…", "we need to…", or "`X` should…". Use "we / our" for shared conventions where it fits, but don't force it.
- Backtick all code, symbols, and file names. You may link files and issues as markdown: `[text](url)`.
- No emojis in the body beyond the leading `✴️`. Tone: collaborative, direct, no fluff.

**Examples:**

Critical — a bug that blocks the user:

> ✴️ The dialog closes before `send()` resolves. If the request throws, the user can't resubmit and the error is lost — not a hard error, but worse UX. Move `dialog.close()` after the request succeeds.

Moderate — fragile behavior:

> ✴️ `Promise.all` rejects on the first failed request, so every successfully-fetched result is thrown away too and nothing gets seeded. This looks like an oversight — please collect the rest (`Promise.allSettled`) and handle the failures.

Suggestion — convention:

> ✴️ Async `sendAndParse` sits in a store file, which goes against `stores.md`. Async work should move to a service that subscribes and populates the fact store, like the other services do.

## Rules

- **Run tooling and conventions first** - Get both reports before logic analysis
- **Use repo-native commands** - Prefer documented project scripts and checks over hardcoded tool commands
- **Autofix when available** - Run the best fix-capable lint/check command once if the repo exposes one
- **Re-diff after mutation** - Review the post-fix state, not the stale pre-fix diff
- **Focus on logic** - Supporting passes handle type, lint, and convention checks
- **Read reference completely** - Don't stop when patterns look familiar
- **Diff line-by-line** - "Similar" is not "same"
- **Verify usage** - Variables must be used in logic
- **Flag differences** - Don't rationalize them
- **Present findings first** - Output the review, then run Phase 4 to offer actions (fix or PR comments). Never fix or comment before the user chooses.
- **Mark drafted PR comments** - Every comment the skill writes starts with `✴️ ` and follows PR Comment Style

**Anti-pattern:** Rationalization

WRONG: "Simpler is OK"
RIGHT: "Missing feature: [what] - reference has this"

WRONG: "Both patterns are valid"
RIGHT: "Pattern differs: reference uses X, new uses Y"

## Keywords

review, code review, changes, commits, logic analysis, diff, git diff
