# Cleanup examples

Before/after pairs for the comment classes in the skill's Phase 2. The two the body keeps — one
mechanism in three places, and design rationale moved to the commit message — are not repeated
here.

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

### Useful transformation → keep, carried by the concrete example

```typescript
// Before: "Strip the leading dot from the absolute data path (e.g. …)."
// After
// Drop the leading dot: ".itemSet[1].field" -> "itemSet[1].field".
```

### External reference → self-contained, or gone

```typescript
// Before
// Workaround for the case described in #412.

// After — the fact is in the file; the issue number bought the reader nothing
// Chrome reports a zero-height box until the font loads, so measure after `ready`.
```
