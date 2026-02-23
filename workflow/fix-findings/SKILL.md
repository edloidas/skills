---
name: fix-findings
description: >
  Use when conversation contains problems, issues, or findings from reviews,
  consilium, debugging, or research that need to be fixed in the current project.
  Triages findings into tasks and works through each with user approval.
license: MIT
compatibility: Claude Code
arguments: instructions
argument-hint: "[additional instructions]"
allowed-tools: Bash Read Write Edit Glob Grep Task AskUserQuestion
metadata:
  author: edloidas
---

# Fix Findings

Turns problems and findings from the current conversation into a task-driven fix workflow. Scans for issues surfaced by reviews, consilium, debugging, or research — triages them, creates tasks, and works through each fix with user approval before implementing.

## Arguments

| Argument    | Description                                                      |
| ----------- | ---------------------------------------------------------------- |
| _(none)_    | Triage all findings from conversation, ask before working        |
| `$ARGUMENTS`| Focusing instructions — e.g., `skip warnings`, `only criticals` |

Honor any filtering or scoping passed via `$ARGUMENTS`. Examples:

- `skip warnings` — only critical and note severity
- `only criticals` — skip warnings and notes
- `focus on performance` — only performance-related findings
- `ignore lint` — skip lint/formatting findings

## Workflow

```
┌─────────────────────────────────────────────┐
│              Phase 1: Triage                │
│                                             │
│  Scan conversation → Categorize findings    │
│  → Group trivials → Create tasks            │
│         │                                   │
│         ▼                                   │
│  Ambiguous? ──yes──► AskUserQuestion        │
│      │                     │                │
│      no                    ▼                │
│      │              User confirms scope     │
│      ▼                     │                │
└──────┴─────────────────────┘                │
       │                                      │
       ▼                                      │
┌─────────────────────────────────────────────┐
│         Phase 2: Work Loop                  │
│                                             │
│  For each task:                             │
│    Mark in_progress                         │
│    → Analyze code + root cause              │
│    → Present problem/thoughts/fix           │
│    → WAIT for user approval                 │
│    → Implement fix                          │
│    → Mark completed                         │
│    → Next task                              │
└─────────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────┐
│      Phase 3: Trivial Batch (optional)      │
│                                             │
│  Offer to fix grouped trivials via          │
│  background subagent                        │
└─────────────────────────────────────────────┘
```

## Phase 1: Triage

### 1. Scan Conversation

Search the full conversation history for problems, issues, and findings. Sources include:

- Consilium reviewer feedback (Seneca, Codex, Scrutator, etc.)
- Code review comments and suggestions
- Debugging session conclusions
- Research findings and recommendations
- User-reported problems
- Build/test/lint failures mentioned in conversation

Prioritize **recent** findings. Ignore stale or already-addressed items from early in the conversation.

### 2. Categorize by Severity

Assign each finding one severity level:

| Severity     | Criteria                                                        |
| ------------ | --------------------------------------------------------------- |
| **critical** | Bugs, broken logic, security issues, data loss risks            |
| **warning**  | Suboptimal patterns, potential issues, missing edge cases        |
| **note**     | Style, naming, minor improvements, documentation gaps           |

### 3. Group Trivial Items

Collect genuinely trivial fixes into a single "batch fix" group:

- Lint/formatting fixes
- Typo corrections
- Simple rename suggestions
- Obvious test fixes (e.g., updated snapshot, changed assertion value)

These will be offered as a batch in Phase 3. Do NOT group items that require analysis or judgment.

### 4. Create Tasks

Use `TaskCreate` for each finding (or trivial group). Include:

- **subject**: Concise problem title (imperative form)
- **description**: Problem context, source (which review/reviewer), severity, relevant file(s)
- **activeForm**: Present continuous form for the spinner

Order tasks: critical first, then warnings, then notes, trivial batch last.

### 5. Decision Point

If the task list is clear and unambiguous, proceed directly to Phase 2.

If unclear — multiple interpretations, conflicting findings, or many low-severity items — use `AskUserQuestion`:

- Which severity levels to include (criticals only? include warnings?)
- Whether to skip specific findings
- Whether the trivial batch should be auto-fixed

## Phase 2: Work Loop

Process tasks one at a time, in order. For each task:

### Step 1: Start

`TaskUpdate` → mark `in_progress`.

### Step 2: Analyze

- Read the relevant code files
- Research the problem (grep for related patterns, check usage)
- Understand root cause and impact
- Consider trade-offs between different fix approaches

### Step 3: Present

Show the user a structured analysis. Use this format:

```
### Task #N: <Subject>

**Severity:** critical | warning | note
**Source:** <which review/reviewer surfaced this>
**File(s):** `path/to/file.ts:42`

**Problem**
<What's wrong and where — be specific, reference line numbers>

**Analysis**
<Root cause, why it matters, trade-offs considered>

**Suggested Fix**
<Recommended approach — or multiple options if genuinely ambiguous>
```

If the fix is obvious and low-risk, present it briefly. If complex or ambiguous, present options via `AskUserQuestion`:

1. Recommended approach (with description of trade-offs)
2. Alternative approach (if genuinely different)
3. "Skip this task" — move to next

### Step 4: Wait

**Do NOT implement until the user approves.** Wait for explicit user input. The user may:

- Approve the suggested fix
- Choose an alternative
- Provide additional context or constraints
- Skip the task
- Ask for more analysis

### Step 5: Implement

Apply the approved fix. Use the appropriate tools (`Edit`, `Write`, `Bash` for tests, etc.).

### Step 6: Complete

`TaskUpdate` → mark `completed`. Move to the next task.

## Phase 3: Trivial Batch

After all non-trivial tasks are done, if a trivial batch exists:

1. Show the user the list of trivial fixes grouped together
2. Use `AskUserQuestion`:
   - "Fix all in background" (Recommended) — use `Task` tool with `run_in_background: true`
   - "Fix all inline" — apply fixes sequentially in this conversation
   - "Skip trivials" — leave them unfixed

For background execution, the subagent prompt should list each trivial fix with file paths and specific changes to make. Report results when the background task completes.

Only delegate to background subagent for genuinely trivial fixes — if any item requires judgment, keep it in the main loop.

## Rules

1. **Never implement before user approves** — always present analysis first, wait for input
2. **Use TaskCreate/TaskUpdate/TaskList** — not ad-hoc tracking or numbered lists
3. **Prioritize recency** — most recent review/research findings take priority over older ones
4. **Respect `$ARGUMENTS`** — honor filtering instructions (severity, topic, skip directives)
5. **One task at a time** — do not jump ahead, batch non-trivial fixes, or implement multiple fixes without approval between each
6. **Stay focused** — fix what was found, do not expand scope or refactor adjacent code
7. **Mark tasks properly** — `in_progress` before starting, `completed` after implementing
