---
name: summary-commit
description: Generate Git commit message summaries following strict formatting rules. Analyzes staged/unstaged changes and produces technical, past-tense commit messages.
license: MIT
compatibility: Claude Code
allowed-tools: Read, Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git show:*)
model: claude-sonnet-4-5
---

# Git Commit Message Summary Generator

## Purpose

Analyze git changes and generate well-formatted commit message summaries. Produces technical, specific commit messages using past participle tense with strict formatting requirements.

## When to Use This Skill

Use when the user asks to:
- Generate a commit message
- Summarize changes for commit
- Create commit summary
- Write commit message body

Trigger phrases: "commit summary", "generate commit", "commit message", "summarize for commit", "write commit"

## Commands

| Command | Description |
|---------|-------------|
| `/summary-commit` | Analyze all changes (staged + unstaged) |
| `/summary-commit staged only` | Only staged changes |
| `/summary-commit [custom]` | Follow custom instructions |

## Workflow

### Step 1: Analyze Changes

```bash
git status
git diff
git diff --cached
```

### Step 2: Generate Summary

Apply strict output format rules.

## Output Format Rules

**Structure:**
1. Each change on a NEW LINE
2. NO blank lines between regular lines (only before footer)
3. Start immediately - no preamble
4. One sentence per line with period
5. 2-6 lines total for body
6. Use backticks for code: `ClassName`, `functionName()`

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

**Content depth:** Technical and specific
- "Refactored `ToggleGroup` to use single `value` prop instead of separate `singleValue`/`multipleValue`"
- NOT: "Refactored ToggleGroup component" (too vague)

**Focus:** HOW and WHY
- Mention approach/pattern used
- Explain benefit when non-obvious

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

## Content Guidelines

1. **Group related changes:** Component + tests + stories → one line
2. **Order by importance:** Main feature first, supporting second, cleanup last
3. **Technical specificity:** Key props, hooks, patterns, architecture, ARIA
4. **Avoid obvious:** NOT "Added new file" → "Implemented component with..."

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
Refactored `Form` validation to use Zod schemas instead of custom validators.
Updated all form components to support `schema` prop for type-safe validation.
Extracted common validation logic into `useFormValidation` hook.

BREAKING CHANGE: Removed `validate` prop, use `schema` instead.
```

```
Fixed focus trap in `Dialog` not releasing when closed via Escape key.
Updated `useKeyDown` hook to properly cleanup event listeners on unmount.
```

## Final Checklist

Before output, verify:
- [ ] Each change on its own line
- [ ] No blank lines between changes
- [ ] 2-6 lines total
- [ ] Code elements use backticks
- [ ] Past tense throughout
- [ ] Technical details included
- [ ] No preamble or explanatory text

## Keywords

commit, message, summary, git, conventional, changelog
