---
name: code-cleanup
description: Post-implementation cleanup. Removes obvious comments, AI artifacts, improves JSDoc, fixes trivial TODOs, and flags misleading comments.
license: MIT
compatibility: Claude Code, Codex
allowed-tools: Bash(git:*) Read Edit Glob Grep
model: claude-sonnet-4-5
arguments: "files --dry-run"
argument-hint: "[files] [--dry-run]"
---

# Code Cleanup

Post-implementation cleanup skill for removing noise, improving documentation quality, and fixing trivial issues.

## Purpose

Clean up code after implementation to ensure production-ready quality. Removes AI artifacts, obvious comments, and fixes quick wins that don't require design decisions.

## When to Use

- After completing a feature implementation
- Before committing code
- When reviewing code quality
- Called by other skills as a final cleanup step

## Workflow

### Phase 1: Gather Context

**Step 1: Find Project Guidelines**

Search for comment/documentation rules in:
```
CLAUDE.md
.cursor/rules/*.md
.cursor/rules/*.mdc
docs/CONTRIBUTING.md
docs/STYLE_GUIDE.md
.github/CONTRIBUTING.md
```

Extract relevant rules about:
- Comment style preferences
- JSDoc requirements
- Code documentation standards

**Step 2: Identify Scope**

If no files specified, use git diff:
```bash
git diff --name-only HEAD~1..HEAD
git diff --cached --name-only
```

Filter to code files only (exclude: `*.md`, `*.json`, `*.lock`, `*.yaml`, `*.yml`, `dist/`, `build/`, `*.min.js`, `*.map`)

### Phase 2: Analysis

For each file, identify:

#### 2.1 Obvious Comments (REMOVE)

Comments that restate what code already says:
- `// increment counter` before `counter++`
- `// return the result` before `return result`
- `/** Gets user by ID */` on `getUserById(id)`
- `// loop through items` before `for (const item of items)`
- `// check if null` before `if (value === null)`

#### 2.2 AI Implementation Artifacts (REMOVE)

- `// TODO: implement` on already-implemented code
- `// Claude: ...` or `// AI: ...` comments
- Placeholder comments like `// Add your code here`
- Debug logging left from development: `console.log('DEBUG:...')`
- Commented-out alternative implementations with AI reasoning

#### 2.3 JSDoc Quality (IMPROVE)

**Keep and improve:**
- Public API documentation
- Complex algorithm explanations
- Non-obvious parameter constraints
- Return value edge cases

**Remove:**
- JSDoc that only restates function name
- `@param name - The name` style redundancy
- `@returns {void}` on void functions
- Empty or placeholder descriptions

**Fix format issues:**
- Missing `@param` tags for documented functions
- Incorrect types in JSDoc vs TypeScript
- Orphaned `@example` without actual example

#### 2.4 Misleading Comments (FLAG or FIX)

- Comments describing different behavior than code
- Outdated comments referencing removed code
- Wrong variable/function names in comments
- Incorrect assertions about behavior

#### 2.5 Commented Code (EVALUATE)

**Remove if:**
- Old implementation replaced by new code
- Debug code not needed
- Alternative approaches not chosen
- TODO items already completed

**Keep if:**
- Explicit `// KEEP:` or `// NOTE:` marker
- Reference implementation for complex algorithm
- Temporarily disabled feature with ticket reference
- Platform-specific code with clear reason

#### 2.6 Quick Wins (AUTO-FIX)

Fix without asking if truly trivial:
- `// TODO: add type` where type is obvious
- Missing function return type that TypeScript infers
- `// eslint-disable-next-line` for resolved issues
- Empty catch blocks that should have comment or handling
- Unused imports (if safe to remove)

### Phase 3: Execute Cleanup

**User confirmation:** Before making any changes, present the analysis summary from Phase 2 and ask the user for approval. If `--dry-run` was specified, output the report and stop here.

**Order of operations:**
1. Remove obvious comments
2. Remove AI artifacts
3. Clean up commented code
4. Fix JSDoc (remove redundant, improve valuable)
5. Apply quick wins
6. Flag misleading comments for review

**Safety rules:**
- Never remove `// @ts-ignore` or `// @ts-expect-error` without understanding why
- Never remove `// eslint-disable` without checking the rule
- Never remove comments with `HACK`, `FIXME`, `XXX`, `BUG` - flag for review
- Never remove license headers or copyright notices
- Preserve `// region` / `// endregion` markers if project uses them

### Phase 4: Report

Output format:
```
## Cleanup Summary: [N files, M changes]

### Removed
- [count] obvious comments
- [count] AI artifacts
- [count] redundant JSDoc
- [count] dead commented code

### Improved
- [count] JSDoc comments enhanced

### Fixed
- [count] quick wins applied

### Flagged for Review
- `file.ts:123` - Misleading comment: describes X but code does Y
- `file.ts:456` - FIXME comment needs attention
```

## Examples

### Obvious Comment Removal

```typescript
// Before
// Get the user from the database
const user = await getUser(id);

// After
const user = await getUser(id);
```

### JSDoc Cleanup

```typescript
// Before
/**
 * Adds a user.
 * @param user - The user to add
 * @returns The added user
 */
function addUser(user: User): User { ... }

// After
function addUser(user: User): User { ... }
```

### JSDoc Improvement

```typescript
// Before
/**
 * Process
 */
function processPayment(amount: number, currency: string): PaymentResult { ... }

// After
/**
 * Processes payment through the configured gateway.
 * Throws PaymentError if gateway is unavailable or amount exceeds limit.
 */
function processPayment(amount: number, currency: string): PaymentResult { ... }
```

### AI Artifact Removal

```typescript
// Before
// TODO: implement validation
function validate(input: string): boolean {
    if (!input) return false;
    if (input.length > 100) return false;
    return /^[a-z]+$/.test(input);
}

// After
function validate(input: string): boolean {
    if (!input) return false;
    if (input.length > 100) return false;
    return /^[a-z]+$/.test(input);
}
```

### Commented Code Removal

```typescript
// Before
function calculate(x: number): number {
    // Old implementation:
    // return x * 2 + 1;
    // return Math.pow(x, 2);
    return x ** 2;
}

// After
function calculate(x: number): number {
    return x ** 2;
}
```

## Integration

This skill can be invoked:
- Directly: `/code-cleanup [files or git range]`
- By other skills as final step
- By subagents after implementation

## Arguments

| Argument | Description |
|----------|-------------|
| (none) | Clean staged + unstaged changes |
| `<file>` | Clean specific file |
| `<dir>/` | Clean all code files in directory |
| `last N commits` | Clean files from last N commits |
| `--dry-run` | Report what would change without modifying |
| `--aggressive` | Also remove section divider comments |
