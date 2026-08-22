# store-wiring

**Severity:** medium (perf / convention)
**Applies to:** React Three Fiber with an external state store
**Conditional:** only when the project depends on `nanostores` (or an
equivalent atom store — Zustand, Jotai, Valtio). Skip in projects that keep
scene state in React state alone.

## What it is

How scene state reaches components, and how many renders each write costs.
Two rules:

- **Subscribe through the store's React binding** — `useStore` from
  `@nanostores/react`, not `atom.get()` in a render body and not a manual
  `.subscribe()` in a `useEffect`.
- **Batch related writes** — several atoms updated in one logical step go
  inside `batch()` so subscribers re-render once.

## Why it matters

`atom.get()` in a render body reads the value without subscribing. The
component renders the current value once and then never updates, because
nothing told React to re-render it. It works on first paint and silently goes
stale — the hardest class of bug to spot in review, because the initial screen
is correct.

Unbatched writes cost the opposite way. Setting `$position` and `$rotation`
separately is two store notifications, so every subscriber renders twice per
logical update. Inside a 60 FPS movement loop that is 120 renders per second
per subscriber for 60 actual changes.

Manual `.subscribe()` in `useEffect` gets both wrong in a third way: it
usually leaks the unsubscribe on fast refresh, and it re-renders through a
`setState` that runs after the paint, so the scene shows the previous value
for one frame.

## How to detect

Confirm the store first:

```bash
jq -r '((.dependencies // {}) + (.devDependencies // {})) | keys[]' package.json \
  | rg 'nanostores|zustand|jotai|valtio'
```

Then:

```bash
# Reads that do not subscribe
rg -n '\$\w+\.get\(\)' --type tsx

# Manual subscriptions in components
rg -n '\.subscribe\(|\.listen\(' --type tsx

# Writes, to check batching
rg -n '\$\w+\.set\(' --type ts --type tsx

# Batching, the fix side
rg -n 'batch\(' --type ts --type tsx
```

For `.get()` hits, check the enclosing scope: inside an event handler, a
`useFrame` callback, or a store action it is correct and idiomatic — that is
reading a current value without wanting a re-render. **Only a `.get()` in a
render body is a finding.**

For `.set()` hits, look for two or more consecutive writes in the same
function. That is the batching finding.

## Anti-patterns

```tsx
// ❌ Reads once, never updates — no subscription
function Hud() {
  const hp = $hp.get();
  return <div>{hp}</div>;
}

// ❌ Manual subscription: leaks on fast refresh, renders a frame late
function Hud() {
  const [hp, setHp] = useState($hp.get());
  useEffect(() => {
    $hp.subscribe(setHp);
  }, []);
  return <div>{hp}</div>;
}

// ❌ Two notifications for one logical update
function move(next: Transform) {
  $position.set(next.position);
  $rotation.set(next.rotation);
}

// ❌ Per-frame store writes with no throttle — every subscriber re-renders
//    at frame rate
useFrame(() => $position.set(ref.current.position.clone()));
```

The last one compounds with
[`useframe-workload`](useframe-workload.md): a store write that drives React
subscribers is a `setState` in disguise.

## Canonical fix

Subscribe with the binding, write in a batch:

```tsx
import { useStore } from '@nanostores/react';
import { batch } from 'nanostores';
import { $position, $rotation } from '@/stores/game';

function Hud() {
  const hp = useStore($hp);
  return <div>{hp}</div>;
}

const updateTransform = useMemo(
  () =>
    throttle((next: Transform) => {
      batch(() => {
        $position.set(next.position);
        $rotation.set(next.rotation);
      });
    }, 16),
  [],
);
```

For values that only the scene consumes, skip the store round trip entirely and
write to the object3D — no subscriber, no render:

```tsx
useFrame((_, delta) => {
  ref.current.position.addScaledVector(velocity, delta);
});
```

Reserve store writes for state the DOM side actually displays, and throttle
them to the rate a human can read (10–20 Hz is plenty for a HUD).

## Notes

- **`.get()` outside render is correct.** In handlers, `useFrame` callbacks,
  and store actions it is the intended API. Do not report it.
- **`useStore` on a computed atom is the right way to select a slice** —
  subscribing to a whole object atom re-renders on every field change.
  Recommend `computed()` over subscribing broadly.
- **`batch()` is nanostores-specific.** The equivalents are Zustand's single
  `set()` with a partial object, Jotai's `useSetAtom` with one write, and
  Valtio's natural batching through proxies. Match the store the repo uses
  rather than proposing nanostores.
- **This is a project convention** absorbed into the audit. Enforce it where
  the project already uses the store; do not propose adopting a store in a
  project that has none.
- **Throttling frame-rate writes changes behaviour.** Confirm the value is only
  displayed, not integrated, before recommending it.

## How to report this finding

> **Where:** `<file>:<line>`
>
> **What's wrong:** `<atom read with .get() in a render body — the component
> never updates | N consecutive .set() calls outside batch() — N renders per
> logical update | per-frame store write driving React subscribers>`.
>
> **Suggested fix:** `<useStore | wrap the writes in batch() | write to the
> object3D and skip the store>`.
>
> **Why it matters:** `<fixes silently stale UI | halves subscriber renders per
> update | removes frame-rate React renders>`.
