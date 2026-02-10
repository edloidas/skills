---
name: review-scope
description: Determines review scope by parsing arguments, running git diff, filtering generated files, and returning a structured file list. Used by /review-changes and other review commands.
license: MIT
compatibility: Claude Code
allowed-tools: Bash, Read, Glob, Grep
---

# Review Scope

Determine the scope of code changes for review. Parse arguments, run appropriate git diff, filter generated files, and return structured output.

## Input Formats

Parse the command arguments to determine scope:

| Input | Meaning |
|-------|---------|
| (none) | Staged + unstaged changes, or last commit if clean |
| `last N commits` | Changes in last N commits |
| `path/` | Changes in directory |
| `file.ext` | Specific file changes |
| `HEAD~N..HEAD` | Commit range |

## Process

### Step 1: Parse Input

Determine which mode based on input:

```bash
# No args: check for staged/unstaged changes
git diff --stat
git diff --cached --stat

# If clean working tree, use last commit
git log -1 --name-status

# Last N commits
git diff HEAD~N..HEAD --stat

# Specific path or file
git diff -- path/

# Commit range
git diff START..END --stat
```

### Step 2: Get Changed Files

Run git diff with `--name-status` to get file status and names:

```bash
# For working tree changes
git diff --name-status
git diff --cached --name-status

# For commits
git diff --name-status HEAD~N..HEAD
```

Status codes:
- `A` = Added (NEW)
- `M` = Modified (MODIFIED)
- `D` = Deleted (DELETED)
- `R` = Renamed (RENAMED)

### Step 3: Filter Generated Files

**Exclude these patterns:**
- `*-lock.*`, `*.lock` (package locks)
- `dist/`, `build/`, `.next/`, `out/` (build output)
- `*.d.ts` (type declarations, unless manually authored)
- `*.min.js`, `*.min.css` (minified files)
- `*.map` (source maps)
- `node_modules/` (dependencies)
- Binary files (images, fonts, etc.)

**Detection for manually authored `.d.ts`:**
- If `.d.ts` has corresponding `.ts` source, it's generated → exclude
- If `.d.ts` is standalone in `types/` or `typings/`, it's authored → include

### Step 4: Get Line Ranges (for MODIFIED files)

For each modified file, get changed line ranges:

```bash
git diff --unified=0 file.ext | grep '^@@' | sed 's/^@@ .* +\([0-9,]*\) @@.*/\1/'
```

This extracts ranges like `42,10` (starting at line 42, 10 lines changed).

### Step 5: Check Diff Size

Count total changed lines:

```bash
git diff --stat | tail -1
# Example: 15 files changed, 423 insertions(+), 89 deletions(-)
```

If total < 500 lines, include inline content. Otherwise, just file list.

## Output Format

```markdown
## SCOPE

**Mode**: staged+unstaged | last N commits | path | file | range
**Total changes**: X insertions, Y deletions across Z files

**Changed files:**
- `src/components/Dialog.tsx` (MODIFIED) lines: 42-52, 120-145
- `src/utils/helpers.ts` (NEW)
- `src/old/legacy.ts` (DELETED)

**Excluded**: N files (pnpm-lock.yaml, dist/*, *.d.ts)

---

## CONTENT (if < 500 lines total)

### src/components/Dialog.tsx

\`\`\`diff
@@ -42,5 +42,10 @@
- old code
+ new code
\`\`\`

### src/utils/helpers.ts (NEW)

\`\`\`typescript
// Full file content for new files
\`\`\`
```

## Rules

- Always filter generated files
- Include line ranges for MODIFIED files
- Include inline content only if total < 500 lines
- Report excluded files count with examples
- NEW files get full content (if inline enabled)
- MODIFIED files get diff hunks (if inline enabled)
- DELETED files just listed, no content

## Examples

### Example 1: Default (working tree)

**Input**: `/review-changes`

```bash
git diff --name-status
git diff --cached --name-status
```

If both empty:
```bash
git diff --name-status HEAD~1..HEAD
```

### Example 2: Last N commits

**Input**: `/review-changes last 3 commits`

```bash
git diff --name-status HEAD~3..HEAD
```

### Example 3: Specific path

**Input**: `/review-changes src/components/`

```bash
git diff --name-status -- src/components/
git diff --cached --name-status -- src/components/
```

### Example 4: Commit range

**Input**: `/review-changes abc123..def456`

```bash
git diff --name-status abc123..def456
```
