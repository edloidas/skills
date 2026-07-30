---
paths:
  - '**/*.{ts,tsx}'
---

# Comments

## When to comment

Default: no comment, except separators. Add one only when the WHY is genuinely non-obvious — a hidden constraint, a subtle invariant, a workaround for a specific bug, behavior that would surprise a reader. Keep it to 1–2 lines.

Don't explain WHAT the code does — names already do that. Don't reference the current task, fix, issue, or PR (`added for the X flow`, `handles the case from #123`, `fixed during refactor`) — that rots as the code evolves and belongs in the commit message, PR body, or issue, not the source.

## Prefixes

Four single-line prefixes, picked so a comment-highlighter plugin colors each one differently. The color is the point — it is what makes a prefix worth using over a plain comment. Never combine two. Never use `// ----`, `// ====`, or numeric headers (`// ---- 1. Validate ----`).

| Prefix | Color | Use for |
|--------|-------|---------|
| `// !` | red | Important enough to stop a reader: bug, security risk, breaking change, sharp edge. |
| `// *` | green | Section divider, or a header over a multi-line comment. |
| `// ?` | blue | **Not settled**: a hack, a temporary fix, a guess, something still in doubt. |
| `// TODO:` | — | Actionable follow-up. Imperative verb, `[#123]` when an issue exists. |

```ts
// ! Potential race condition if fetch retries here
// ? May need to memoize once this call becomes hot
// TODO: [#123] Replace mock with live API
```

## `// ?` is for doubt, not for rationale

This is the one that gets misused. A finished decision with a non-obvious reason is a plain comment. `// ?` means the code is still open — a flag to come back to, not an explanation.

```ts
// Stable sort — ties resolve by original insertion order.
const sorted = [...items].sort(byRank);

// ? Above V8's ~640k argument-list ceiling — revisit if that limit lifts.
const merged = buildLargeBatch();
```

If removing the uncertainty would not change the comment, it should not be `// ?`.

## `// *` sections

Wrap in blank `//` lines. Header ≤ 4 words.

```ts
//
// * Event Handlers
//

/* ... */

//
// * Validators
//

/* ... */
```

Use `// *` between subcomponents in composite component files. Delete a `// TODO:` once resolved — don't leave it as a comment.
