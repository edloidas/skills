---
name: commit-summary
description: Generate commit message body summaries from git changes. Produces technical, past-tense descriptions formatted as one-line-per-change. Use when the user asks for a commit summary, commit message body, or change description — not for full commit creation.
license: MIT
compatibility: Claude Code
allowed-tools: Read Bash(git status:*) Bash(git diff:*) Bash(git log:*) Bash(git show:*)
arguments: "'staged only', custom instructions, or none for all changes"
argument-hint: "[scope]"
model: claude-sonnet-4-6
---

# Git Commit Message Summary Generator

## Commands

| Command | Description |
|---------|-------------|
| `/commit-summary` | Analyze all changes (staged + unstaged) |
| `/commit-summary staged only` | Only staged changes |
| `/commit-summary [custom]` | Follow custom instructions |

## Workflow

### Step 1: Analyze Changes

```bash
git status
git diff
git diff --cached
```

### Step 2: Generate Summary

Apply the output format rules below.

## Output Format Rules

1. Each change on a NEW LINE — one sentence per line, ending with a period
2. NO blank lines between regular lines (only before footer)
3. Start immediately — no preamble or explanatory text
4. 2-6 lines total for body
5. Use backticks for code: `ClassName`, `functionName()`
6. No bullet points (`-` or `*`), no paragraphs

**Correct:**
```
Implemented `Toolbar` component with ARIA-compliant keyboard navigation using roving tabindex.
Added `ToggleGroup` subcomponent supporting single/multiple selection with `value`/`onValueChange` API.
Refactored selection logic in `ToggleGroup` to eliminate redundant state management.
Created Storybook stories demonstrating toolbar patterns with separators and disabled items.
```

**Incorrect:**
- Everything in one paragraph
- Using bullet points (`-` or `*`)
- Text continuing on next line without sentence structure

## Writing Style

**Tense:** Past participle (elliptical past tense)
- "Implemented `useKeyboard` hook"
- "Refactored `Button` to accept `asChild` prop"
- NOT: "Implement hook" or "Implementing hook"

**Depth:** Technical and specific
- "Refactored `ToggleGroup` to use single `value` prop instead of separate `singleValue`/`multipleValue`"
- NOT: "Refactored ToggleGroup component" (too vague)

**Focus:** HOW and WHY — mention approach/pattern used, explain benefit when non-obvious

**Grouping:** Group related changes (component + tests + stories → one line). Order by importance: main feature first, supporting second, cleanup last. Avoid obvious statements like "Added new file" — describe what was implemented.

## Preferred Verbs

| Verb | Use for |
|------|---------|
| Implemented | New complex features/patterns |
| Added | New functionality, components |
| Refactored | Code restructuring |
| Updated | Modified existing behavior |
| Removed | Deleted code/functionality |
| Fixed | Bug fixes |
| Integrated | Connected systems |
| Extracted | Separated into reusable pieces |

## Footer (Optional)

Add only if needed:
- Issue references: `Fixes #123` or `Resolves #456`
- Breaking changes: `BREAKING CHANGE: Removed legacyMode prop`
- Co-authors: `Co-authored-by: Name <email>`

## Examples

```
Implemented `DatePicker` component with keyboard navigation and locale support.
Added `useDateRange` hook for managing start/end date state with validation.
Integrated with `Popover` component for consistent dropdown positioning.
Created comprehensive Storybook stories covering all date selection patterns.
```

```
Fixed focus trap in `Dialog` not releasing when closed via Escape key.
Updated `useKeyDown` hook to properly cleanup event listeners on unmount.
```

## Keywords

commit, message, summary, git, conventional, changelog
