---
name: code-polish
description: Analyze code changes for implementation quality, best practices, robustness, and reliability. Suggests improvements without over-engineering.
license: MIT
compatibility: Claude Code
allowed-tools: Bash, Read, Glob, Grep
---

# Code Polish

Analyze code changes to ensure they follow best practices and are implemented optimally.

## When to Use

Trigger phrases: "polish code", "best practices", "improve code quality", "review implementation"

## Determine Scope

```bash
git diff --name-status
git diff --cached --name-status
# If clean, use last commit:
git diff --name-status HEAD~1..HEAD
```

**Filter out:** `*-lock.*`, `dist/`, `build/`, `.next/`, `*.d.ts`, `*.min.js`, `*.map`

**Trivial diffs:** Version bumps, formatting only → "No substantive changes. Nothing to polish." and stop.

## Analysis Focus

For each changed file, evaluate:

1. **Efficiency** - No obvious performance issues, no redundant operations
2. **Best Practices** - Follows language/framework conventions and idioms
3. **Reliability** - Error handling is appropriate, no silent failures
4. **Robustness** - Handles edge cases, validates inputs at boundaries
5. **Clarity** - Code is readable, intent is clear without excessive comments

## Quality Threshold

**Internal guideline (do not display):** Estimate code quality 0-100%. If ≥95%, the code is production-ready. List findings as optional suggestions only, do not push for changes. Avoid:

- Adding complexity for marginal gains
- Suggesting tests for trivial code
- Recommending abstractions for single-use code
- Proposing defensive coding for impossible scenarios

## Output Format

**Summary:** `**Polish: X issues found in N files**`

For each issue, structure the response:

### Problem

Describe what's wrong. For behavioral issues, show step-by-step reproduction:

```
1. Do X → state becomes Y
2. Do Z
3. Unexpected result (WRONG - expected W)
```

### Root Cause

**File:** `path/to/file.ts`

Explain why the problem occurs. Reference specific code:

```typescript
// Current problematic code
someFunction() {
    // This causes the issue because...
}
```

Point to specific lines, missing handlers, incorrect conditions, etc.

### Solution

Describe the fix approach, then show implementation:

```typescript
// Suggested fix
someFunction() {
    // Fixed implementation
}
```

---

After all issues, include a recommendations table:

```
| Priority | Improvement                    | Effort |
|----------|--------------------------------|--------|
| High     | Fix X                          | Low    |
| Medium   | Handle Y edge case             | Medium |
| Low      | Consider Z optimization        | High   |
```

End with: "Would you like me to implement any of these?"

## Rules

- Read changed files before judging
- Focus on substance over style
- Respect existing patterns in the codebase
- Fewer high-value suggestions > many nitpicks
- If code is already good, say so and stop
