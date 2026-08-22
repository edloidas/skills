## Comments

Default to no comment. Add one only when the WHY is genuinely non-obvious — a hidden
constraint, a subtle invariant, a workaround for a specific bug, behavior that would
surprise a reader. Keep it to 1–2 lines.

Never explain WHAT the code does; names already do that. Never reference the current task,
fix, issue, or PR (`added for the X flow`, `handles the case from #123`) — that rots as the
code evolves and belongs in the commit message, PR body, or issue.

Four single-line prefixes, each colored differently by a comment-highlighter plugin. The
color is the point — it is what makes a prefix worth using over a plain comment. Never
combine two.

| Prefix | Use for |
|--------|---------|
| `// !` | Stop the reader: bug, security risk, breaking change, sharp edge. |
| `// *` | Section divider, or a header over a multi-line comment. |
| `// ?` | **Not settled** — a hack, a guess, a temporary fix. Doubt, not rationale: a finished decision with a non-obvious reason is a plain comment. |
| `// TODO:` | Actionable follow-up. Imperative verb, `[#123]` when an issue exists. Delete it once resolved rather than leaving it as a comment. |

The highlighter colors **per line**, so repeat the prefix on every line a block covers. A
bare indented `//` continuation loses the color and stops looking like part of the warning.

```ts
// ! Retries reuse the same AbortSignal.
// ! A signal already aborted makes every retry fail instantly.

// ? Above V8's ~640k argument-list ceiling — revisit if that limit lifts.
const merged = buildLargeBatch();
```

Wrap `// *` sections in blank `//` lines. Header ≤ 4 words. Never `// ----`, `// ====`, or
numbered headers.

```ts
//
// * Event Handlers
//
```

Prefixes are written for `//` line comments — use the host language's line-comment marker
where it differs.
