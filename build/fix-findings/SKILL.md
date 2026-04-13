---
name: fix-findings
description: >
  Use when conversation contains problems, issues, or findings from reviews,
  consilium, debugging, or research that need to be fixed in the current project.
  Triages findings into tasks and works through each with user approval.
license: MIT
compatibility: Claude Code
argument-hint: "[auto] [additional instructions]"
allowed-tools: Bash Read Write Edit Glob Grep Task AskUserQuestion
metadata:
  author: edloidas
---

# Fix Findings

## Arguments

| Argument     | Description                                                      |
| ------------ | ---------------------------------------------------------------- |
| _(none)_     | Triage all findings from conversation, ask before working        |
| `auto`       | Fix routine findings automatically, only ask for tough decisions |
| `$ARGUMENTS` | Focusing instructions, combinable with `auto`                    |

Filtering examples: `skip warnings`, `only criticals`, `focus on performance`, `ignore lint`, `auto only criticals`.

## Workflow

### Regular Mode

1. **Triage:** Scan conversation → Categorize → Group trivials → Create tasks → If ambiguous: AskUserQuestion for scope confirmation
2. **Work Loop:** For each task: mark in_progress → Analyze → Present analysis → WAIT for user approval → Implement → mark completed → next
3. **Trivial Batch:** Offer to fix grouped trivials (background subagent, inline, or skip)

### Auto Mode

1. **Triage:** Scan conversation → Categorize → Group trivials → Create tasks → Resolve ambiguity autonomously (no AskUserQuestion)
2. **Auto Work Loop:** For each task: mark in_progress → Analyze → Classify as routine or escalate
   - **Routine:** Implement fix → show condensed summary → mark completed → next
   - **Escalate:** Present full analysis → WAIT for user approval → Implement → mark completed → next
3. **Trivial Batch:** Fix all trivials via background subagent automatically (no user prompt)

## Phase 1: Triage

### 1. Scan Conversation

Search conversation history for findings from: reviews, consilium feedback, debugging conclusions, research, user-reported problems, build/test/lint failures.

Prioritize **recent** findings. Ignore stale or already-addressed items.

### 2. Categorize by Severity

| Severity     | Criteria                                                        |
| ------------ | --------------------------------------------------------------- |
| **critical** | Bugs, broken logic, security issues, data loss risks            |
| **warning**  | Suboptimal patterns, potential issues, missing edge cases        |
| **note**     | Style, naming, minor improvements, documentation gaps           |

### 3. Group Trivial Items

Collect genuinely trivial fixes (lint, typos, simple renames, obvious test fixes) into a single batch for Phase 3. Do NOT group items that require analysis or judgment.

### 4. Create Tasks

`TaskCreate` for each finding (or trivial group):
- **subject**: Concise problem title (imperative form)
- **description**: Problem context, source (reviewer), severity, relevant file(s)
- **activeForm**: Present continuous form for the spinner

Order: critical → warnings → notes → trivial batch last.

### 5. Decision Point

If clear and unambiguous, proceed to Phase 2.

If unclear (multiple interpretations, conflicting findings, many low-severity items), use `AskUserQuestion` for scope: severity levels, specific skips, trivial batch handling.

**Auto mode:** Skip `AskUserQuestion`. Resolve ambiguity with best judgment, default to all severity levels unless `$ARGUMENTS` says otherwise. Conflicting reviewer feedback gets escalated per-task in Phase 2.

## Phase 2: Work Loop

Process tasks one at a time, in order.

**Start:** `TaskUpdate` → mark `in_progress`.

**Analyze:** Read relevant code, grep for related patterns, understand root cause and impact, consider fix approaches.

**Present:** Show structured analysis:

```
### Task #N: <Subject>

**Severity:** critical | warning | note
**Source:** <which review/reviewer surfaced this>
**File(s):** `path/to/file.ts:42`

**Problem**
<What's wrong and where — reference line numbers>

**Analysis**
<Root cause, why it matters, trade-offs>

**Suggested Fix**
<Recommended approach — or options if genuinely ambiguous>
```

If complex or ambiguous, present options via `AskUserQuestion`: recommended approach, alternative, or skip.

**Wait:** Do NOT implement until the user approves.

**Implement:** Apply the approved fix using `Edit`, `Write`, `Bash`, etc.

**Complete:** `TaskUpdate` → mark `completed`. Next task.

### Auto Mode: Classify Fix

In auto mode, after Analyze, classify as **routine** or **escalate**:

| Routine (auto-fix)                            | Escalate (ask user)                                      |
| --------------------------------------------- | -------------------------------------------------------- |
| Bug with clear correct behavior               | Multiple valid approaches with real trade-offs            |
| Missing error handling, obvious approach       | Breaking changes or public API changes                    |
| Code not matching documented patterns          | Security-sensitive changes                                |
| Test fixes, assertion updates                  | Ambiguous requirements, unclear "right" fix               |
| Performance fix with no readability cost       | Cross-cutting changes affecting multiple systems          |
| Single-file, localized changes                | Architectural decisions (new abstractions, restructuring) |
| Removing dead code or unused imports           | Conflicting reviewer feedback on same issue               |

**When in doubt, escalate.** Think through implications, check for side effects, and verify codebase context before classifying as routine.

**Routine flow:** Implement the fix, then show condensed summary:

```
**Task #N: <Subject>** [<severity>]
`path/to/file.ts:42` — <one-line description of what was fixed and why>
```

Do NOT wait for approval — proceed to next task.

**Escalate flow:** Same as regular mode — present full analysis, wait for approval, implement.

## Phase 3: Trivial Batch

After non-trivial tasks are done, if a trivial batch exists:

1. Show the list of trivial fixes
2. `AskUserQuestion`: "Fix all in background" (Recommended), "Fix all inline", or "Skip trivials"

Background subagent prompt should list each fix with file paths and specific changes. Only delegate genuinely trivial fixes.

**Auto mode:** Skip `AskUserQuestion`. Fix all trivials via background subagent. Show brief summary of what was dispatched.

## Rules

1. **Never implement before user approves** — present analysis first, wait for input
2. **Use TaskCreate/TaskUpdate/TaskList** — not ad-hoc tracking
3. **Prioritize recency** — recent findings over older ones
4. **Respect `$ARGUMENTS`** — honor filtering and mode instructions
5. **One task at a time** — no jumping ahead or batching non-trivials
6. **Stay focused** — fix what was found, no scope expansion
7. **Mark tasks properly** — `in_progress` before starting, `completed` after

### Auto Mode Exceptions

- **Rule 1:** Routine fixes are implemented immediately after classification
- **Rule 5:** Routine fixes proceed without waiting, but still sequentially
- **Extra:** Spend extra time analyzing before classifying as routine — confidence must be high before auto-implementing
