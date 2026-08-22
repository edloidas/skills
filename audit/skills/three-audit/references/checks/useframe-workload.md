# useframe-workload

**Severity:** high (perf)
**Applies to:** React Three Fiber (Three.js `requestAnimationFrame` loops by analogy)

## What it is

Work inside the per-frame callback that does not need to run per frame: React
state updates, scene graph lookups by name, raycasts, `getBoundingClientRect`,
JSON or string work, physics queries, and anything whose result changes far
more slowly than 16 ms.

Distinct from [`render-loop-allocations`](render-loop-allocations.md), which is
about *garbage* produced in the loop. This one is about *time* spent in it.

## Why it matters

The frame budget at 60 FPS is 16.6 ms for everything — React, application
logic, Three.js scene traversal, and the GPU submit. Every millisecond of
avoidable JS in `useFrame` comes straight out of it, and it is paid by every
component with a frame callback, every frame, forever.

Two items dominate real codebases:

- **`setState` in `useFrame`** re-renders the React tree 60 times a second.
  Reconciliation, effects, and the child components' render functions all run
  per frame. This routinely costs more than the entire 3D render.
- **`scene.getObjectByName()` / `scene.traverse()`** walk the whole scene graph
  to find something whose identity never changes. O(nodes) per frame for a
  lookup that should be a ref.

The symptom is a scene that is slow with almost nothing on screen, and a CPU
profile dominated by React internals or `Object3D.traverse`.

## How to detect

```bash
rg -n -A20 'useFrame\(' --type tsx --type jsx
```

Read each callback body and classify the work. Then target the specific
offenders:

```bash
# React state updates in the loop
rg -n 'useFrame\(' -A20 --type tsx --type jsx | rg 'set[A-Z]\w*\(|dispatch\('

# Scene graph lookups
rg -n 'getObjectByName|getObjectByProperty|scene\.traverse|\.traverse\(' \
  --type ts --type tsx --type js --type jsx

# Layout reads and per-frame raycasts
rg -n 'getBoundingClientRect|new\s+THREE\.Raycaster|\.intersectObjects\(' \
  --type ts --type tsx --type js --type jsx
```

Also count the `useFrame` callbacks themselves. Fifty components each with
their own callback is fifty function calls plus fifty closures invoked per
frame — worth consolidating even when each one is cheap.

## Anti-patterns

```tsx
// ❌ 60 React renders per second
useFrame(({ clock }) => setElapsed(clock.elapsedTime));

// ❌ Full scene-graph walk to find a fixed object
useFrame(() => {
  const target = scene.getObjectByName('player');
  camera.lookAt(target.position);
});

// ❌ Raycast every frame when the pointer only moves sometimes
useFrame(() => {
  raycaster.setFromCamera(pointer, camera);
  const hits = raycaster.intersectObjects(scene.children, true);
  setHovered(hits[0]?.object.name ?? null);
});

// ❌ Logic that only needs to run a few times a second
useFrame(() => {
  updateAIDecisions(entities); // expensive pathfinding
});

// ❌ Layout read forces a style recalculation every frame
useFrame(() => {
  const rect = containerRef.current.getBoundingClientRect();
});
```

## Canonical fix

Keep per-frame state out of React. Write to refs and object3D properties
directly; the renderer picks the values up on the next frame without a
re-render.

```tsx
const label = useRef<HTMLSpanElement>(null!);

useFrame(({ clock }) => {
  // no setState — mutate the DOM node / object3D directly
  label.current.textContent = clock.elapsedTime.toFixed(1);
});
```

Resolve scene objects once, outside the loop:

```tsx
const player = useRef<THREE.Object3D>(null!);

useFrame(() => {
  camera.lookAt(player.current.position);
});
```

Move sometimes-work to the event that actually triggers it:

```tsx
// R3F's built-in pointer events already raycast only on pointer movement
<mesh onPointerOver={() => setHovered(true)} onPointerOut={() => setHovered(false)} />
```

Throttle work whose result does not need frame resolution:

```tsx
const accumulator = useRef(0);

useFrame((_, delta) => {
  accumulator.current += delta;
  if (accumulator.current < 0.1) return; // 10 Hz
  accumulator.current = 0;
  updateAIDecisions(entities);
});
```

When state genuinely has to be shared, use a store that lets subscribers read
without re-rendering the tree (a nanostore, a Zustand `getState()`, or a plain
ref object) rather than component state.

## Notes

- **`useFrame` itself is cheap.** Consolidating callbacks is a low-severity
  suggestion; the finding is what the callbacks *do*.
- **Not all `setState` in a frame loop is wrong** — a state update guarded by a
  condition that rarely fires (crossing a threshold, changing a discrete phase)
  is fine. Read the guard before reporting.
- **Ordering between callbacks is set by `useFrame` priority**, not by the
  component tree. When suggesting consolidation, check
  [`useframe-priority`](useframe-priority.md) so the merge does not change the
  order gameplay and effects run in.
- **`delta` is the right unit for throttling** — it survives frame-rate changes
  and tab backgrounding, where a frame counter does not.
- **Confirm with a profile.** A CPU profile that shows React reconciliation or
  `traverse` inside the animation frame is the evidence; static reading gives
  the candidate.

## How to report this finding

> **Where:** `<file>:<line>`
>
> **What's wrong:** `<setState / scene lookup / raycast / heavy logic>` runs
> every frame, though its result changes `<rarely / only on pointer move>`.
>
> **Suggested fix:** `<write to a ref | resolve the object once | move to the
> pointer event | throttle with a delta accumulator>`.
>
> **Why it matters:** frees frame budget that is currently spent on work the
> frame does not need.
