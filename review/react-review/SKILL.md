---
name: react-review
description: >
  Review React code for useEffect misuse, convention violations, memoization issues, and architectural problems.
  Runs react-doctor, Haiku subagents for mechanical checks, and deep Sonnet analysis in parallel.
  Use when reviewing React components, finishing a feature, or refactoring.
license: MIT
compatibility: Claude Code, Codex
model: claude-sonnet-4-6
allowed-tools: Bash(pnpm:*) Bash(npx:*) Bash(timeout:*) Bash(git:*) Task Read Glob Grep
arguments: "path"
argument-hint: "[file, directory, or empty]"
---

# React Review

## Purpose

Deep review of React code combining automated tooling (react-doctor), mechanical pattern checks (Haiku subagents), and architectural analysis (main Sonnet agent). Focuses on what linters and type-checkers can't catch: effects misuse, convention violations, memoization strategy, state architecture, and component organization.

**Linter-aware:** Biome / ESLint already handle hook rules, dependency arrays, self-closing elements, fragments, type imports, and unused variables. This skill explicitly skips those areas.

## When to Use

- After implementing a React feature
- Refactoring existing components
- Code review of React pull requests
- Learning better React patterns
- When code "works" but feels wrong

Trigger phrases: "review react", "check components", "react patterns", "effects review", "suggest improvements"

## Commands

| Command | Description |
|---------|-------------|
| `/react-review` | Review staged/unstaged changes |
| `/react-review path/file.tsx` | Specific file |
| `/react-review src/components/` | Directory |

---

## Phase 1: Load Context

### 1.1 Read Project Rules

Read these files if they exist (skip silently if missing):

```
.cursor/rules/react.mdc
.cursor/rules/typescript.mdc
.cursor/rules/stores.mdc
.claude/rules/react.md
.claude/rules/typescript.md
```

If no project rules found, use React 19 best practices as defaults.

### 1.2 Detect Conventions

Run these checks to determine which convention rules to activate:

```bash
# Check if project uses displayName
grep -rl "\.displayName\s*=" src/ --include="*.tsx" | head -3
# Check if project uses data-component
grep -rl "data-component" src/ --include="*.tsx" | head -3
```

**Convention activation:**
- If `displayName` found in 2+ files → activate `displayName` + `data-component` checks
- If not found → skip those checks entirely (no false positives on projects without this convention)
- `props-naming`, `variable-order`, `component-props-ref`, and `destructuring` checks are always active

### 1.3 Identify Target Files

- If `$ARGUMENTS` provided: use that path (file or directory)
- Otherwise: get staged + unstaged changes via `git diff --name-only HEAD` and `git diff --name-only --cached`
- Filter to `.tsx` and `.ts` files containing React imports
- Read each target file

---

## Phase 2: Parallel Dispatch

Launch all three tracks in a **single message** with parallel tool calls.

### Track A: react-doctor (Bash, background)

Run the bundled script:

```bash
bash <skill-dir>/scripts/run-react-doctor.sh . /tmp/react-doctor-output.txt
```

This runs react-doctor with `--no-dead-code --verbose --no-ami -y` flags. It creates a temp config if the project lacks one, excludes stories and test files, and cleans up on exit.

Run this in the background (`run_in_background: true`) — results are collected in Phase 3.

### Track B: Mechanical Checks (Haiku Subagent)

Use the Task tool to launch a Haiku subagent (`model: haiku`):

1. Read `references/mechanical-checks-prompt.md` for the prompt template
2. Read `references/rules-conventions.md` for convention rules
3. Build the prompt:
   - Replace `{{CONVENTIONS}}` with only the **active** convention rules from Phase 1.2
   - Replace `{{FILE_LIST}}` with the target file paths
4. Dispatch with `subagent_type: "general-purpose"`, `model: "haiku"`

The subagent uses Read/Glob/Grep to scan files and returns structured violations.

### Track C: Deep Analysis (Main Sonnet, inline)

Perform deep analysis on each target file using the rules from `references/rules-effects.md` and `references/rules-patterns.md`. Load these reference files, then analyze:

**Effects Analysis** (from rules-effects.md):
- All 14 useEffect anti-patterns — match against patterns in target files
- Flag each violation with the specific anti-pattern number and fix

**Patterns Analysis** (from rules-patterns.md):
- Memoization strategy — over-memoization, missing memoization, wrong tool
- `ref.current` in dependency arrays
- Early returns vs conditional rendering
- Performance patterns (throttle, CSS animations, context splitting)
- Data fetching in effects >15 lines → extract to custom hook
- Component size >200 lines → suggest splitting
- State architecture — related `useState` calls that should be `useReducer`

---

## Phase 3: Collect & Merge

1. **Read Track A output** from the background task output
2. **Collect Track B results** from the Haiku subagent response
3. **Combine with Track C** deep analysis findings

**Deduplication:** If multiple tracks flag the same issue (same file + same line range + same category), keep the most detailed version and note the source.

---

## Phase 4: Output

### Finding Format

For each file with findings:

```markdown
## path/to/Component.tsx

### Critical
Issues that cause bugs or incorrect behavior.

**1. Race condition in fetch effect** (`Component.tsx:45-58`) [Effects #13]
**Current:** Raw fetch in useEffect without cleanup — stale responses can overwrite fresh data
**Fix:** Add ignore flag in cleanup, or use TanStack Query
**Source:** Deep Analysis

### Improvements
Better patterns and architecture.

**2. Extract data fetching to custom hook** (`Component.tsx:30-72`) [Patterns]
**Current:** 40 lines of fetch logic in component body
**Fix:** Create `useItemData` hook following project's existing `use*Data` pattern
**Source:** Deep Analysis

### Conventions
Project convention violations.

**3. Missing displayName** (`Component.tsx`) [displayName]
**Fix:** Add `Component.displayName = COMPONENT_NAME;`
**Source:** Mechanical Check

### react-doctor
Findings from react-doctor automated analysis.

**4. [react-doctor finding description]** (`Component.tsx:15`)
**Source:** react-doctor
```

### Priority Table

After all file sections, include a summary table:

```markdown
## Priority Table

| # | Finding | Category | Location | Source |
|---|---------|----------|----------|--------|
| 1 | Race condition in fetch effect | Critical | `Component.tsx:45-58` | Deep |
| 2 | Extract data fetching to hook | Improvement | `Component.tsx:30-72` | Deep |
| 3 | Missing displayName | Convention | `Component.tsx` | Haiku |
| 4 | react-doctor finding | react-doctor | `Component.tsx:15` | RD |
```

**Source column:** `Deep` = Track C, `Haiku` = Track B, `RD` = Track A (react-doctor)

### When No Findings

If all tracks return clean results:

```markdown
## React Review: No Issues Found

All checks passed:
- react-doctor: clean
- Convention checks: clean
- Deep analysis: clean
```

---

## Rules

- **Read files before analyzing** — never guess about code you haven't seen
- **Convention checks are opt-in** — only enforce displayName/data-component if the project uses them
- **No linter overlap** — skip anything Biome/ESLint already catches
- **Show examples** — include before/after snippets for non-obvious fixes
- **Reference project patterns** — "Following pattern in useVersionsData.ts"
- **No false positives** — only flag when you're certain
- **Respect trade-offs** — acknowledge when current approach is valid
- **Don't be pedantic** — skip trivial findings

## Keywords

react, review, effects, useEffect, hooks, conventions, displayName, data-component, memoization, architecture, patterns, react-doctor
