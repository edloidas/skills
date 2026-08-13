# Convention Audit

The repo-adaptive half of the convention pass: detect the stack, read what the project itself
documents, and check the code in scope against both. The eight stack files beside this one carry
fixed conventions for a specific frontend stack; this file is what makes the pass work on a repo
that stack does not describe.

Load this whenever the convention pass runs. Everything here is **report-first** — apply only what
the SKILL.md body classifies as a mechanical, local, behavior-preserving fix. Anything that
changes behavior is a finding for the report, never an edit.

## 1. Read what the project documents

Read these when present, and treat what they say as the project's own conventions:

- `CLAUDE.md`, `AGENTS.md`
- `.cursor/rules/*.mdc`, `rules/*.mdc`, `.rules/*.mdc`
- any repo-local rule file those instruction files point at

A rule the project wrote down outranks every rule shipped with this skill. A project that
documents its own conventions gets audited against those, not against the stack files.

## 2. Detect stack

| Stack | Detection signals |
|-------|------------------|
| **React/TSX** | `*.tsx` files present; `react` in `package.json` deps |
| **Svelte** | `*.svelte` files present; `svelte.config.*` exists |
| **Bun/Node** | `package.json` present; no `react`/`svelte` deps; no `*.tsx`/`*.svelte` |
| **Go** | `go.mod` or `*.go` files present |
| **Zig** | `build.zig` or `*.zig` files present |

Run only the audits the detected stack activates:

| Audit | React/TSX | Svelte | Bun/Node | Go | Zig |
|-------|:---------:|:------:|:--------:|:--:|:---:|
| useEffect | ✓ | – | – | – | – |
| Hook placement | ✓ | – | – | – | – |
| Component patterns | ✓ | – | – | – | – |
| Svelte-specific | – | ✓ | – | – | – |
| Tailwind | ✓ | ✓ | – | – | – |
| TypeScript | ✓ | ✓ | ✓ | – | – |
| Store patterns | ✓ | ✓ | – | – | – |
| Pattern consistency | ✓ | ✓ | ✓ | ✓ | ✓ |
| Security | ✓ | ✓ | ✓ | ✓ | – |
| Dead code | ✓ | ✓ | ✓ | ✓ | ✓ |

Omit inapplicable sections from the output entirely.

## 3. Audit the code in scope

Read every target file before reporting findings. Do not modify files.

### useEffect (React/TSX)

For each `useEffect`: locate the callback, extract the `}, [deps])` array, look for an
`if (condition) return;` guard at the top, and decide whether that guard blocks
re-execution when the deps change. A guard that does is a bug — name what goes stale.

```typescript
useEffect(() => {
  if (instanceRef.current) return;        // blocks re-execution
  instanceRef.current = createInstance();
  instanceRef.current.setItems(items);    // never runs again when items changes
}, [items]);
```

### Hook placement (React/TSX)

Rules-of-Hooks violations, all of which a linter can miss when the call is nested:

- hooks inside JSX expressions — `description={useI18n()}`
- hooks inside callbacks — `onClick={() => { const x = useRef() }}`
- hooks inside conditions — `if (condition) { useState() }`
- hooks after an early return — `if (!x) return null; const y = useHook();`
- hooks in ternaries — `const x = condition ? useHook() : null;`
- hooks in logical expressions — `const x = condition && useHook();`

To find them: locate every `return` that is not the component's final return and check for
`use[A-Z]` calls after it in the same scope; then search ternary and logical expressions for
`use[A-Z]\w+\(`.

### Component patterns (React/TSX)

Arrow-function components, `memo()`-wrapped components, and `forwardRef()` components
without a `displayName`.

### Svelte

- **`{@html}`** — the Svelte equivalent of `dangerouslySetInnerHTML`. Identify the source
  expression and whether it is sanitized (DOMPurify or similar) before use. Flag unsanitized
  values, especially from user input or external data.
- **Manual store subscriptions** — `store.subscribe(` inside `onMount` or the component body
  whose unsubscribe function is never called in `onDestroy`. Auto-subscriptions (`$store`)
  are safe; skip them.
- **Reactive statement ordering** — circular `$:` dependencies (`$: a = b + 1; $: b = a + 1`),
  and statements reading values declared after them where the order matters.

### Tailwind

Compare `gap-*`, `p-*`, `m-*`, and `rounded-*` values across similar components — files
sharing a name pattern (`Dialog*`, `Button*`, `Input*`, `Modal*`) or the same root structure
(both rooted at `flex flex-col`). Flag values that break the group's convention, and cite the
sibling you compared against.

### TypeScript

- **Null/undefined consistency** — only when `CLAUDE.md` or a rule file documents an explicit
  convention. No documented convention → skip this check entirely.
- **Export patterns** — default exports where the rules say to avoid them, named-export
  consistency, re-export patterns.

### Store / state

Detect the library first: `@nanostores/react` or `nanostores` imports, `zustand` imports, or
Svelte stores (covered in the Svelte section — skip here).

- **nanostores** — flag full subscriptions (`useStore($store)`) where a selective
  `useStore($store, {keys: ['field']})` would do; components subscribing to stores they never
  render; atoms read higher in the tree than necessary.
- **Zustand** — flag selector-less `useStore()`; broad selectors returning large objects when
  one field is used; multi-field selectors missing `shallow` equality.
- **Callback props** — callback props vs direct store calls, inconsistently within one
  codebase.

### Pattern consistency — error handling

Detect the project's typed-error library: `neverthrow` (imports, or
`ResultAsync|okAsync|errAsync|ok(|err(`) or Effect (`@effect/` / `effect` imports, `Effect.`,
`pipe(`). If either is in use, flag async functions in the changed files that use try/catch
instead, and flag files mixing both styles. Cite a reference file that shows the project's
pattern.

- **Go** — `_ = ` assignments discarding an error return; multi-return calls with `_` in the
  error position; `fmt.Errorf("...: %v", err)` where the project wraps with `%w`.
- **Zig** — `catch unreachable` on operations that can realistically fail; `try` used
  inconsistently with explicit `catch` for the same error types.

### Dead code

Within the target files: find exported or declared functions, types, and constants, grep the
codebase for usages, and flag those with zero references (`UNUSED`) or a single suspicious
reference (`LOW`, with the location).

