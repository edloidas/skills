---
name: code-cleanup
description: >
  Post-implementation cleanup of AI-added comment noise and trivial code issues. Removes comments
  that restate the code or narrate how it works, moves design rationale to the commit message,
  compacts genuine gotchas to a line or two, and renames unclear symbols so a comment is not needed;
  gentle on docs. Auto-applies and reports. Use after implementing, before committing, or when asked
  to clean up comments, trim excessive AI commentary, or remove over-explanation from changed code.
license: MIT
compatibility: Claude Code, Codex
allowed-tools: Bash(git:*) Read Edit Glob Grep
argument-hint: "[files | commit-ref] [--dry-run] [--comments-only]"
---

# Code Cleanup

Post-implementation cleanup. Strips comment noise an AI tends to add, fixes trivial issues, and
leaves only comments that earn their place.

## Core Principle

**A comment should explain only what the code cannot.** Three things the code already covers, so a
comment must not:

- **What the code does** — readable from the code itself. Delete.
- **The design story / why it was built this way** — that is the commit message's job, not the
  source's. Move it out, hand it to the commit.
- **A missing name** — if a comment exists because a variable or function is unclearly named, rename
  the symbol instead.

What remains worth keeping: genuinely non-obvious behavior, timing gotchas, hacks, and external
constraints — kept, but compacted to a line or two.

## When to Use

- After completing a feature implementation, before committing
- When asked to "clean up comments", "trim the comments", "remove excessive AI comments", or
  "the comments are over-explaining"
- When reviewing code quality
- Called by other skills as a final cleanup step

## Read Intent First

- A request about **comments** ("clean up the comments") → comment work is the whole job. Code
  changes are allowed only where a cheap rename removes the need for a comment.
- A general **"clean this up"** → run the full pass (comments + artifacts + trivial fixes below).
- `--comments-only` forces the comment-focused mode regardless of phrasing.

## Workflow

### Phase 1: Scope

**Step 1: Find project guidelines.** Check for comment/doc conventions in:
```
CLAUDE.md   AGENTS.md   .cursor/rules/*.md(c)   docs/CONTRIBUTING.md   docs/STYLE_GUIDE.md   .github/CONTRIBUTING.md
```
Honor anything they say about comment style, JSDoc requirements, or section markers.

**Step 2: Resolve the target.** In priority order:

1. **Explicit argument** — files, a directory, or a commit ref passed in → use exactly that.
2. **Uncommitted changes** (default) — staged + unstaged:
   ```bash
   git diff --name-only HEAD                    # tracked modifications (staged + unstaged)
   git ls-files --others --exclude-standard     # new untracked files
   ```
3. **Last commit** — fall back here only when the working tree is clean:
   ```bash
   git diff --name-only HEAD~1..HEAD
   ```

Announce which scope resolved (e.g. "Cleaning uncommitted changes: 4 files" or "Tree clean —
cleaning last commit `0cccf9d`: 3 files").

Filter to code files (exclude `*.md`, `*.json`, `*.lock`, `*.yaml`, `*.yml`, `dist/`, `build/`,
`*.min.js`, `*.map`).

**Step 3: Decide which comments are in scope.** For diff/commit modes, pull the actual hunks
(`git diff HEAD` / `git show`) and consider:

- **every comment added or modified** by the change, plus
- **pre-existing comments in changed files that relate to the changed code** (e.g. a doc comment on
  a function whose body you just edited).

Leave unrelated pre-existing comments elsewhere in the file alone — surgical. For an explicitly
named file, the whole file is in scope.

### Phase 2: Classify Each Comment

Run every in-scope comment through this table. The first three classes are the AI-noise the skill
exists to remove.

| Class | What it looks like | Action |
| --- | --- | --- |
| **Restates the code** | One-liner narration (`// increment counter`) **or** a multi-line block describing how the mechanism works, step by step, that a reader gets from the code itself | **Remove** |
| **Design rationale / history** | "We do it this way because…", "Captured here because by the time X runs…", the story of the decision aimed at a PR reader | **Remove from code; surface the text for the commit message** |
| **Non-obvious behavior / gotcha / hack** | Timing dependency, surprising side effect, workaround for an external bug, a constraint you cannot infer from the code | **Keep — compact to 1–2 lines, drop the narration** |
| **Comment compensating for a bad name** | The comment exists mainly to explain what a vague symbol means | **Rename the symbol** (see Phase 3); delete the comment |
| **Documentation (JSDoc / docstring / public API)** | API-level doc humans rely on | **Gentle:** correct inaccuracies, tighten wording for human readability, never gut |
| **AI implementation artifacts** | `// TODO: implement` on done code, `// Claude:`/`// AI:`, `// Add your code here`, leftover `console.log('DEBUG…')`, commented-out alternatives with AI reasoning | **Remove** |
| **Misleading / stale** | Describes behavior the code no longer has, wrong names, outdated references | **Fix if obvious, else flag** |
| **Markers** | `HACK` `FIXME` `XXX` `BUG` `@ts-expect-error` `eslint-disable` `// region`, license headers | **Preserve** (flag `FIXME`/`HACK` for review, don't delete) |

**The test for the top two classes:** read the code *without* the comment. If you still understand
what it does, the comment was restating — remove it. If what you lose is *why a decision was made*
rather than *what the code does*, that belongs in the commit message, not the source.

**Test files:** a step-label comment that just narrates the next call (`// focus the field`) is
restatement — remove it. Keep one only where it conveys intent the calls don't (e.g. "most recent,
not stale"). The test name and assertions should carry the rest.

### Phase 3: Apply

**Auto-apply.** Edit directly — uncommitted changes are the review surface, and `git diff` shows
exactly what changed. With `--dry-run`, produce the Phase 4 report and stop without editing.

**Order:** remove restatement → pull rationale out (collect for the report) → compact gotchas →
rename-to-kill → docs polish → AI artifacts & dead code → quick wins → flag the rest.

**Renaming to kill a comment.** When a cheap, local rename makes a comment unnecessary, do it and
remove the comment. "Cheap" = a single symbol whose every reference you can update in the in-scope
files (a local variable, a private function). Anything heavier — splitting a function into
utilities, reshaping control flow, renaming an exported symbol with external callers — is **not**
applied; record it as a suggestion in the report instead.

**Quick wins (auto-fix if truly trivial):** obvious missing return type TS already infers, an
`eslint-disable` for an issue that no longer exists, an unused import your removal orphaned.

**Safety rules:**
- Never remove `@ts-ignore` / `@ts-expect-error` without understanding why it's there.
- Never remove `eslint-disable` without checking the rule still passes.
- Never delete `HACK` / `FIXME` / `XXX` / `BUG` comments — flag them.
- Never remove license headers or copyright notices.
- Preserve `// region` / `// endregion` and any project-specific markers.

### Phase 4: Report

```
## Cleanup: [N files, M comments touched]

Scope: uncommitted changes (4 files)

### Removed
- [count] restated / how-it-works comments
- [count] AI artifacts
- [count] dead commented code

### Compacted
- [count] gotcha comments shortened

### Renamed (to remove a comment)
- `activeDataContext` → `focusedDataContext`  (file.ts)

### Docs
- [count] doc comments corrected / tightened

### Suggested for commit message
> The seed is captured at the toggle's pointer-down because the click blurs the
> field before the open handler runs. Clearing context on close is the plugin's job.

### Suggested refactors (not applied)
- `file.ts:120` handleDataActivePath does two things — consider splitting focus-tracking from context-push

### Flagged for review
- `file.ts:456` FIXME left in place — needs attention
- `file.ts:88` comment claims X but code does Y
```

The **Suggested for commit message** section is the home for the design-rationale text removed from
the code — formatted so it can be pasted straight into the commit body.

## Examples

### Restated mechanism → remove

The function name already says everything the comment does.

```typescript
// Before
// Opens the Content Operator dialog and seeds it with the field captured by
// `captureOperatorSeed` (if any), then clears the pending seed.
export function openOperatorWithSeed(): void { ... }

// After
export function openOperatorWithSeed(): void { ... }
```

### Design rationale → commit message

```typescript
// Before
// CS pushes the focused data field to the operator as its mention target — but
// only while the dialog is open. While closed the field is remembered so the
// toolbar can seed the dialog on open. The seed is captured at pointer-down
// because clicking the toggle blurs the field before the open handler runs.
// Clearing context on close is the plugin's responsibility.

// After  (a short orienting note stays; the decision story goes to the commit)
// Focused field is pushed as context only while the dialog is open;
// while closed it is remembered as a seed for the next open.
```
Report → **Suggested for commit message:** "Seed captured at pointer-down because the click blurs
the field before the open handler runs; clearing on close is the plugin's job."

### Gotcha → keep, compacted

```typescript
// Before
// Field snapshotted when the user initiates opening the operator dialog (toolbar
// toggle pointer-down), consumed by `openOperatorWithSeed`. Captured before the
// click blurs the field, because by the time the dialog opens focus is gone.
let pendingOperatorSeed: string | null = null;

// After
// Captured at toggle pointer-down, before the click blurs the focused field.
let pendingOperatorSeed: string | null = null;
```

### Rename to kill the comment

```typescript
// Before
// Live focused data field as a context path, or null. Reflects the field
// focused right now (set on focus, cleared on blur).
let activeDataContext: string | null = null;

// After
let focusedDataContext: string | null = null;
```

### Useful transformation comment → keep, with the concrete example

```typescript
// Before
// Strip the leading dot from the absolute data path
// (e.g. ".itemSet[1].field" -> "itemSet[1].field").

// After
// Drop the leading dot: ".itemSet[1].field" -> "itemSet[1].field".
```

### Documentation → gentle (correct & tighten, don't gut)

```typescript
// Before
/** Process */
function processPayment(amount: number, currency: string): PaymentResult { ... }

// After
/** Charges `amount` via the configured gateway. Throws PaymentError if the gateway is down. */
function processPayment(amount: number, currency: string): PaymentResult { ... }
```

## Common Mistakes

- **Deleting a gotcha as if it were restatement.** "Captured before the click blurs the field" is
  *why*, not *what* — compact it, don't drop it.
- **Keeping rationale "to be safe".** If it's the decision story, the commit message is its home;
  surface it and remove it from the source.
- **Over-trimming docs.** Public API docs are for humans reading the signature — correct and
  tighten, never gut.
- **Renaming exported symbols with outside callers.** That's a refactor, not a rename-to-kill —
  flag it, don't apply it.
- **Touching unrelated comments.** Stay within the changed code; surgical.

## Arguments

| Argument | Description |
|----------|-------------|
| (none) | Clean uncommitted changes; fall back to the last commit if the tree is clean |
| `<file>` / `<dir>/` | Clean the named file(s) or directory — whole file in scope |
| `<commit-ref>` | Clean the files changed in that commit |
| `--comments-only` | Comment work only; never touch code |
| `--dry-run` | Report what would change without editing |
