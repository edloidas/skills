---
name: comment-audit
description: Analyze code comments in changed files for quality, relevance, and adherence to best practices. Manual invocation only.
license: MIT
compatibility: Claude Code
allowed-tools: Bash, Read, Glob, Grep, Task
model: claude-haiku-4-5
---

# Comment Audit

## Purpose

Analyze code comments in changed files to ensure they follow best practices. Scans specific files for comment quality, identifies excessive or trivial comments, and reports issues with suggested improvements.

## When to Use This Skill

Use ONLY when explicitly requested:
- "analyze comments", "audit comments"
- "check comments first", "review comments"
- "do audit", "analyze first"

This skill does NOT run automatically with code reviews. It must be manually invoked.

Trigger phrases: "comment audit", "audit comments", "analyze comments", "check comments"

## Workflow

### Step 1: Identify Files to Analyze

```bash
git diff --name-only
git diff --cached --name-only
# If clean, use last commit:
git diff --name-only HEAD~1..HEAD
```

Filter to code files only (exclude: `*.md`, `*.json`, `*.lock`, `dist/`, `build/`).

### Step 2: Spawn Comment Scanner

Use Task tool with haiku model to scan specific files:

```
Task:
- subagent_type: general-purpose
- model: haiku
- prompt: "Scan the following files for comments and extract all comments with their line numbers and context. Files: [file list]"
```

### Step 3: Evaluate Comments

Apply rules from General Rules and Language-Specific sections below.

### Step 4: Generate Report

Output findings using the Output Format below.

---

## General Rules (All Languages)

These rules apply to all languages. Follow them strictly.

### What to Comment

1. **Non-obvious logic only** - Comment algorithms, workarounds, edge cases
2. **Why, not what** - Explain reasoning, not code mechanics
3. **Public APIs** - Use doc comments for public functions/methods

### What NOT to Comment

1. **Obvious code** - No comments for getters, setters, simple mappings
2. **Self-documenting code** - If variable/function names are clear, no comment needed
3. **Commented-out code** - Remove it, use version control instead
4. **Placeholder comments** - No `// TODO` without issue reference or clear action

### Style Requirements

1. **Complete sentences** - Start with capital letter, end with period
2. **Present tense** - "Returns cached value" not "Will return cached value"
3. **Max 80 characters** - Break long comments into multiple lines
4. **No emojis** - Keep comments professional
5. **No casual slang** - Avoid informal language

### Maintenance

1. **Update with code** - Stale comments are worse than none
2. **Delete resolved TODOs** - Promote to commits, remove tags
3. **Convert answered questions** - Move clarified questions to docs

### Anti-Patterns

| Pattern | Issue | Fix |
|---------|-------|-----|
| `// increment i` | States the obvious | Remove |
| `// get user` before `getUser()` | Redundant | Remove |
| `// TODO: fix this` | No actionable info | Add issue reference or specifics |
| `// HACK` without explanation | No context | Explain why and when to fix |
| Commented-out code blocks | Dead code | Delete, use git history |

---

## TypeScript

TypeScript is the primary language. Apply stricter rules with detailed examples.

### Doc Comments (TSDoc)

Use TSDoc for public APIs:

```ts
/**
 * Calculates the total price including tax.
 * @param items - Cart items to calculate
 * @param taxRate - Tax rate as decimal (e.g., 0.08 for 8%)
 * @returns Total price with tax applied
 */
function calculateTotal(items: CartItem[], taxRate: number): number {
  // ...
}
```

### When Comments Are Needed

```ts
// Bitwise operation for performance in hot path
const hash = (value << 5) - value + charCode;

// Safari requires this workaround for paste events
if (isSafari && event.clipboardData) {
  event.preventDefault();
  // ...
}

// Guard against unsorted input - sorting here would hide caller's bug
if (!isSorted(haystack)) {
  throw new Error('Input must be pre-sorted');
}
```

### When Comments Are NOT Needed

```ts
// BAD: Obvious from code
// Set loading to true
setLoading(true);

// BAD: Redundant with function name
// Gets the user by ID
function getUserById(id: string) { ... }

// BAD: Type already documents this
// The user's email address
email: string;
```

### React/JSX Specific

1. **No comments for props** - Use TypeScript types instead
2. **No comments for simple handlers** - `onClick` handlers are self-documenting
3. **Comment complex hooks** - Explain non-obvious `useEffect` dependencies

```tsx
// BAD
// Handle click
const handleClick = () => { ... }

// GOOD (no comment needed for simple handler)
const handleClick = () => { ... }

// GOOD (complex effect needs explanation)
// Sync local state with server when connection is restored
useEffect(() => {
  if (isOnline && hasPendingChanges) {
    syncWithServer();
  }
}, [isOnline, hasPendingChanges]);
```

---

## Java

Java has comprehensive doc comment conventions. Apply minimal inline commenting.

### Rules

1. **Javadoc for public APIs** - Required for public classes, methods, fields
2. **Minimal inline comments** - Only for truly non-obvious implementations
3. **No redundant comments** - Method names and signatures should be self-documenting
4. **No obvious comments** - Avoid restating what code clearly shows
5. **Complex algorithms only** - Comment only when logic is genuinely complex

### What Requires Comments

- Non-obvious algorithms or optimizations
- Workarounds for library/framework bugs
- Critical business logic that affects correctness
- Thread-safety considerations

### What Does NOT Require Comments

- Standard patterns (builders, factories, getters/setters)
- Simple CRUD operations
- Well-named methods with clear parameters
- Standard exception handling

---

## Go

Go has established conventions from the Go community. Follow idiomatic Go commenting.

### Rules

1. **Package comments** - Required for every package, describe purpose
2. **Exported identifiers** - Doc comment required for all exported functions, types, constants
3. **Start with name** - `// FunctionName does...` format for godoc
4. **Complete sentences** - End with period
5. **No redundant comments** - Go code should be self-documenting

### Style

```go
// Package auth provides authentication and authorization utilities.
package auth

// User represents an authenticated user in the system.
type User struct { ... }

// Authenticate verifies credentials and returns a valid session.
// Returns ErrInvalidCredentials if authentication fails.
func Authenticate(username, password string) (*Session, error) { ... }
```

### What NOT to Comment

- Simple implementations that match function signature
- Standard error handling patterns
- Well-named local variables
- Channel operations with clear purpose

---

## Zig

Zig emphasizes simplicity and explicitness. Comments should match this philosophy.

### Rules

1. **Doc comments for public** - Use `///` for public functions and types
2. **Explain comptime magic** - Comment compile-time logic that's not obvious
3. **Memory management notes** - Comment ownership and allocation patterns
4. **No comments for explicit code** - Zig's explicitness reduces need for comments

### Style

```zig
/// Allocates and returns a new buffer of the specified size.
/// Caller owns returned memory and must call deinit() when done.
pub fn create(allocator: Allocator, size: usize) !*Self { ... }
```

### What to Comment

- Complex comptime logic
- Unsafe operations with safety justification
- Memory ownership transfers
- Platform-specific behavior

### What NOT to Comment

- Explicit error handling (Zig makes this visible)
- Simple allocator usage
- Standard patterns from std library

---

## Output Format

### Summary Line

`**Comment Audit: X issues, Y suggestions in N files**`

### Issue (Must Fix)

```
**Issue** (`file.ext:line`)
**Problem**: Description of the issue
**Fix**: Specific action to take
```

Use for:
- Stale/incorrect comments
- Misleading comments
- Commented-out code
- Obvious/redundant comments

### Suggestion (Consider)

```
**Suggestion** (`file.ext:line`)
**Current**: What exists now
**Improve**: Recommended change
```

Use for:
- Style improvements
- Missing doc comments on public APIs
- Vague comments that could be clearer

### Example Output

```
**Comment Audit: 2 issues, 1 suggestion in 3 files**

**Issue** (`src/utils/parser.ts:45`)
**Problem**: Comment says "handles edge case" but doesn't explain which edge case
**Fix**: Specify the edge case or remove if code is self-explanatory

**Issue** (`src/components/Button.tsx:12-18`)
**Problem**: Commented-out code block
**Fix**: Remove dead code, use git history to recover if needed

**Suggestion** (`src/api/client.ts:23`)
**Current**: `// retry logic`
**Improve**: Explain retry strategy: `// Retry up to 3 times with exponential backoff for transient network errors`
```

## Keywords

comments, audit, code quality, documentation, review, lint, style
