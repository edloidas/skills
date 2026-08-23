---
name: code-cleanup
description: >
  Post-implementation cleanup of correct code. Removes comments that restate the code or narrate
  how it works, moves design rationale to the commit message, compacts genuine gotchas, renames
  unclear symbols so a comment is not needed, checks the code against the project's conventions,
  and simplifies what is more complicated than it needs to be. Gentle on docs. Auto-applies and
  reports. Use after implementing, before committing, or when asked to clean up comments, tidy
  code, apply conventions, or simplify an implementation.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash(git:*) Read Edit Glob Grep AskUserQuestion
argument-hint: "[files | commit-ref] [--dry-run] [--comments-only] [--no-simplify]"
---

# Code Cleanup

Post-implementation cleanup of code that is already correct. Strips comment noise an AI tends to
add, applies the project's conventions, and simplifies what is needlessly complicated.

**Correctness is not this skill's job.** It does not hunt for bugs, and it must not "fix" behavior
it thinks is wrong — that is `/changes-review`. Everything here preserves behavior.

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
- When asked to apply project conventions or simplify an implementation
- Called by other skills as a final cleanup step

## Read Intent First

- A request about **comments** ("clean up the comments") → comment work is the whole job. Code
  changes are allowed only where a cheap rename removes the need for a comment.
- A general **"clean this up"** → run the full pass: comments, artifacts, conventions, simplify.
- `--comments-only` forces the comment-focused mode regardless of phrasing, and **never touches
  code**. It disables, without exception: convention loading and fixes, the simplifier pass,
  rename-to-kill, and quick wins. Comments and docs only. It may still *report* what it would
  otherwise have done.
- `--no-simplify` runs everything except the simplifier pass.

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

**Step 4: Load the conventions that apply.** Skip entirely under `--comments-only`.

**Always load `references/conventions.md`.** It is the repo-adaptive half of the pass: read what
the project itself documents, detect the stack, and audit against both. It is what makes this work
on a repo the stack files below do not describe.

The eight stack files carry fixed conventions for one specific frontend stack. Each is gated on
**two** conditions, and both must hold:

| Reference | Paths | Only when |
| --- | --- | --- |
| `references/react.md` | `*.tsx` | `react` in deps **and** React 19+ |
| `references/typescript.md` | `*.ts`, `*.tsx` | `typescript` in deps, or `tsconfig.json` exists |
| `references/tailwind.md` | `*.tsx` | `tailwindcss` or `@tailwindcss/*` in deps |
| `references/radix.md` | `*.tsx` | `radix-ui` or `@radix-ui/*` in deps |
| `references/storybook.md` | `*.stories.tsx`, `.storybook/**` | `@storybook/*` in deps, or `.storybook/` exists |
| `references/frontend-structure.md` | `src/**` *(JS/TS only — never `src/main/kotlin/**`)* | `react` or `preact` in deps |
| `references/kotlin.md` | `*.kt` | `.kt` files present, or a `kotlin(...)` plugin in `build.gradle.kts` |

**The dependency gate is not optional.** A path glob alone would load `tailwind.md` for any `.tsx`
file and rewrite `h-4 w-4` to `size-4` in a project with no Tailwind, or convert a variant lookup
to `cva` without the package installed. Check `package.json` before loading a stack file; if the
dependency is absent, the file does not apply and its rules are not violations.

`react.md` additionally requires React 19 — `forwardRef` is correct on 18 and its ref-as-prop rule
would break the build.

**The project's own instructions outrank all of this.** If `CLAUDE.md`, `AGENTS.md`, or a rules
file found in Step 1 contradicts a reference, follow the project. These are defaults for repos
that have not said otherwise — not a house style to write into someone else's codebase.

### Phase 2: Classify Each Comment

Run every in-scope comment through this table. The first three classes are the AI-noise the skill
exists to remove.

| Class | What it looks like | Action |
| --- | --- | --- |
| **Restates the code** | One-liner narration (`// increment counter`) **or** a multi-line block describing how the mechanism works, step by step, that a reader gets from the code itself | **Remove** |
| **Design rationale / history** | "We do it this way because…", "Captured here because by the time X runs…", the story of the decision aimed at a PR reader | **Remove from code; surface the text for the commit message** |
| **Non-obvious behavior / gotcha / hack** | Timing dependency, surprising side effect, workaround for an external bug, a constraint you cannot infer from the code | **Keep — compact to 1–2 lines, drop the narration** |
| **Comment compensating for a bad name** | The comment exists mainly to explain what a vague symbol means | **Rename the symbol** (see Phase 3); delete the comment. Under `--comments-only`, leave both and report the rename as a suggestion |
| **Documentation (JSDoc / docstring / public API)** | API-level doc humans rely on | **Gentle:** correct inaccuracies, tighten wording for human readability, never gut |
| **AI implementation artifacts** | `// TODO: implement` on done code, `// Claude:`/`// AI:`, `// Add your code here`, leftover `console.log('DEBUG…')`, commented-out alternatives with AI reasoning | **Remove** |
| **Misleading / stale** | Describes behavior the code no longer has, wrong names, outdated references | **Fix if obvious, else flag** |
| **Markers** | `HACK` `FIXME` `XXX` `BUG` `@ts-expect-error` `eslint-disable` `// region`, license headers, and the prefix convention some repos use — `// !` warning, `// *` section divider, `// ?` open question, `// TODO:` | **Preserve** (flag `FIXME`/`HACK` for review, don't delete). A `// *` divider is structure, not restatement; a `// ?` is an open question, not design rationale |

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
rename-to-kill → docs polish → AI artifacts & dead code → quick wins → conventions → flag the
rest. The simplifier runs after all of it, in Phase 3.5.

**Convention fixes.** Apply only the references that passed **both** gates in Step 4. Fix what is
mechanical, local, and behavior-preserving — `h-4 w-4` that should be `size-4`, an
`interface X extends Y` that should be an intersection type, a flat story name missing its group
prefix, a `forwardRef` that should be ref-as-prop *if the project is on React 19*.

Two things are never auto-applied:

- **Anything that ripples past the files in scope** — a rename with external callers, a file move
  to satisfy the structure rules, a dependency swap like `@radix-ui/react-tabs` → `radix-ui`.
- **Anything a reference marks report-only**, and anything that changes behavior. Some rules in
  `references/conventions.md` and `references/kotlin.md` are correctness or security checks; they
  produce findings, never edits.

Skipped entirely under `--comments-only`.

**Renaming to kill a comment.** Skipped under `--comments-only` — a rename is a code change.
When a cheap, local rename makes a comment unnecessary, do it and remove the comment. "Cheap" = a single symbol whose every reference you can update in the in-scope
files (a local variable, a private function). Anything heavier — splitting a function into
utilities, reshaping control flow, renaming an exported symbol with external callers — is **not**
applied; record it as a suggestion in the report instead.

**Quick wins (auto-fix if truly trivial).** Skipped under `--comments-only`. An obvious missing
return type TS already infers, or an unused import your comment removal orphaned. Leave an
`eslint-disable` alone unless you can actually run the linter and confirm the rule passes —
guessing that a suppression is stale is how a suppression becomes a build failure.

**Safety rules:**
- Never remove `@ts-ignore` / `@ts-expect-error` without understanding why it's there.
- Never remove `eslint-disable` without running the linter and confirming the rule passes. `allowed-tools` grants only `Bash(git:*)`, so on most invocations you cannot — leave it and report it.
- Never delete `HACK` / `FIXME` / `XXX` / `BUG` comments — flag them.
- Never remove license headers or copyright notices.
- Preserve `// region` / `// endregion` and any project-specific markers.

### Phase 3.5: Simplifier pass

Skipped entirely under `--comments-only`, `--no-simplify`, or `--dry-run`. Under `--dry-run` the
analysis still runs — the suggestions go in the report and nothing is written.

Simplify code that is more complicated than it needs to be, **preserving behavior exactly**:
collapse a nested conditional into a guard clause, replace a hand-rolled loop with the obvious
built-in, drop an indirection with one caller, delete a branch that cannot be reached, unwrap a
wrapper that only forwards. Small, local, provable.

Not in scope: anything that changes behavior, anything that needs a test to prove it is safe, and
anything the code is doing deliberately for a reason you cannot see. When in doubt, it is a
suggestion, not an edit.

**Whether to ask first turns on one observable signal: did the invocation carry anything beyond
the bare skill name?**

- **Any argument, flag, or instruction — apply without asking.** A scope, a flag, "simplify the
  parser", "clean this up and tidy the helpers". The caller already said what they want, and a
  skill invoking this one always passes at least a scope or a flag.
- **Nothing at all — ask before applying.** A bare `/code-cleanup`, or a bare "clean up the
  changes" with no further direction.

That rule is deliberately mechanical, because "did a human or a skill call me" is not something
you can read at runtime. **A skill calling this one must pass at least one argument** — a scope,
or `--no-simplify` if it wants the pass off. A caller that passes nothing gets treated as a user
who typed the bare command, which means it may block on a prompt.

If the host cannot prompt interactively at all, do not ask — apply nothing, and report the
simplifications as suggestions.

When asking, use `AskUserQuestion` if the host provides it; otherwise ask in normal chat as a
numbered list and wait for the reply:

1. `Apply the simplifications` (Recommended) — N refactors, all behavior-preserving
2. `Report them only` — list them under Suggested refactors, change nothing

Declined, or the host cannot prompt → fall back to the existing **Suggested refactors (not
applied)** section. Under `--no-simplify` and `--dry-run` the analysis still runs and populates
that section; under `--comments-only` the pass does not run at all and the section carries only
the renames and convention fixes it would otherwise have applied.

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

### Conventions applied
- `Button.tsx:12` forwardRef → ref-as-prop  (react.md)
- `Card.tsx:30` `h-4 w-4` → `size-4`  (tailwind.md)

### Simplified
- `parse.ts:44` nested conditional → guard clause
- `index.ts:8` removed a wrapper that only forwarded to `format()`

### Suggested for commit message
> The seed is captured at the toggle's pointer-down because the click blurs the
> field before the open handler runs. Clearing context on close is the plugin's job.

### Quick wins
- `util.ts:3` removed an import orphaned by a comment deletion

### Suggested refactors (not applied)
Everything analysed but not edited lands here: declined simplifications, renames with callers
outside scope, convention fixes that ripple past the files in scope, and file moves the structure
rules imply.
- `file.ts:120` handleDataActivePath does two things — consider splitting focus-tracking from context-push
- `Card.tsx` structure rules put this in `components/card/` — a move, so not applied

### Flagged for review
- `file.ts:456` FIXME left in place — needs attention
- `file.ts:88` comment claims X but code does Y
```

The **Suggested for commit message** section is the home for the design-rationale text removed from
the code. It is an *input* to the commit body, not a block to be pasted at the end of one: it answers
why the code is built the way it is, which is the first thing a body has to establish, so the commit
writer folds it into that opening paragraph. Write it as prose that can carry that weight — the
reason, not a label for it.

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
- **Drifting into correctness.** A simplification that changes behavior is a bug you introduced,
  not a cleanup. If the code looks wrong rather than untidy, say so in the report and leave it —
  `/changes-review` owns correctness.
- **Imposing the references on a project that disagrees.** `CLAUDE.md` and the repo's own rules
  files win. The references are defaults, not a house style to export.

## Arguments

| Argument | Description |
|----------|-------------|
| (none) | Clean uncommitted changes; fall back to the last commit if the tree is clean |
| `<file>` / `<dir>/` | Clean the named file(s) or directory — whole file in scope |
| `<commit-ref>` | Clean the files changed in that commit |
| `--comments-only` | Comment work only; never touch code — no conventions, no simplification |
| `--no-simplify` | Everything except the simplifier pass |
| `--dry-run` | Report what would change without editing |
