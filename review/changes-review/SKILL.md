---
name: changes-review
description: Deep logic analysis of code changes. Spawns review-build and review-rules agents, then performs logic analysis to find issues tooling cannot detect.
license: MIT
compatibility: Claude Code
allowed-tools: Bash Read Glob Grep Task
arguments: "scope"
argument-hint: "[commits, path, range, or empty]"
---

# Review Code Changes

## Purpose

Perform deep logic analysis of changed files. Delegates tooling checks and convention validation to specialized agents, then focuses on finding logic errors, behavior gaps, and missing business requirements that automated tools cannot detect.

## When to Use This Skill

Use when the user asks to:
- Review code changes before commit
- Analyze recent commits for issues
- Check changes in specific files or directories
- Review a commit range

Trigger phrases: "review changes", "review my code", "check changes", "analyze commits", "code review"

## Dependencies

This skill spawns two subagents via the Task tool:

| Subagent | Type | Purpose |
|----------|------|---------|
| `review-build` | Custom agent | Runs project checks (typecheck, lint, build, test), returns TOOLING_REPORT |
| `review-rules` | Custom agent | Checks files against project conventions, returns CONVENTION_REPORT |

These must be defined as `.claude/agents/review-build.md` and `.claude/agents/review-rules.md` in the target project. If unavailable, Claude Code falls back to `general-purpose` behavior.

**Fallback:** If either agent fails, proceed with the other's report and note the gap in output. If both fail, perform logic analysis standalone and note that tooling/convention checks were skipped.

## Commands

| Command | Description |
|---------|-------------|
| `/changes-review` | All changes (staged + unstaged), or last commit if clean |
| `/code:review-changes last N commits` | Changes in last N commits |
| `/code:review-changes path/` | Changes in directory |
| `/code:review-changes file.ext` | Specific file |
| `/code:review-changes HEAD~N..HEAD` | Commit range |

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

**Step 2: Spawn Agents (parallel)**

Use Task tool to spawn both agents in a single message:

```
Agent 1: review-build
- subagent_type: review-build
- prompt: "Run project checks and return TOOLING_REPORT"

Agent 2: review-rules
- subagent_type: review-rules
- prompt: "Check these files against project conventions: [file list]"
```

Wait for both reports before proceeding.

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
1. **TOOLING_REPORT** (review-build) → Type errors, lint, build/test failures
2. **CONVENTION_REPORT** (review-rules) → Pattern violations
3. **Logic Analysis** (this review) → Behavior gaps, missing features

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

## Rules

- **Spawn agents first** - Get reports before analysis
- **Focus on logic** - Agents handle types and conventions
- **Read reference completely** - Don't stop when patterns look familiar
- **Diff line-by-line** - "Similar" is not "same"
- **Verify usage** - Variables must be used in logic
- **Flag differences** - Don't rationalize them
- **Present findings first** - User approves before fixes

**Anti-pattern:** Rationalization

WRONG: "Simpler is OK"
RIGHT: "Missing feature: [what] - reference has this"

WRONG: "Both patterns are valid"
RIGHT: "Pattern differs: reference uses X, new uses Y"

## Keywords

review, code review, changes, commits, logic analysis, diff, git diff
