# render-loop-allocations

**Severity:** high (perf)
**Applies to:** Three.js, React Three Fiber

## What it is

Allocating objects — `Vector3`, `Quaternion`, `Matrix4`, `Color`, arrays,
closures, object literals — inside the per-frame render loop (`useFrame`, a
`requestAnimationFrame` callback, or anything called from them).

## Why it matters

At 60 FPS a single allocation per frame is 3,600 objects per minute. A scene
with twenty animated objects each allocating three temporaries is over
200,000 objects per minute. None of them leak — that's the problem. They all
become garbage, and the collector eventually stops the main thread to sweep
them.

The symptom is not a low average frame rate. It's **periodic hitches** — a
smooth 60 FPS with a visible stutter every few seconds, worst on mobile and
on lower-end GPUs where the JS heap is smaller and GC runs more often. Average
FPS counters hide it; a frame-time graph shows it as regular spikes.

## How to detect

Find the render loops first, then read what's inside them:

```bash
rg -n 'useFrame\(|requestAnimationFrame\(' --type ts --type tsx --type js --type jsx
```

Then, within those callback bodies, look for construction:

```bash
rg -n 'new\s+THREE\.(Vector[234]|Quaternion|Matrix[34]|Euler|Color|Box3|Sphere|Raycaster)\b' \
  --type ts --type tsx --type js --type jsx
rg -n 'new\s+(Vector[234]|Quaternion|Matrix[34]|Euler|Color|Box3|Sphere|Raycaster)\b' \
  --type ts --type tsx --type js --type jsx
```

A hit is only a finding if it sits inside a per-frame callback (directly, or
in a helper the callback calls every frame). Construction during setup, in a
`useMemo`, or in an event handler is fine — read the enclosing scope before
reporting.

Also check for the non-obvious allocators: `.clone()`, `.toArray()`,
`Array.prototype.map/filter/slice`, template literals, and destructuring into
a fresh object.

```bash
rg -n '\.clone\(\)|\.toArray\(\)' --type ts --type tsx --type js --type jsx
```

## Anti-patterns

```ts
// ❌ Three allocations per frame, per object
useFrame((state, delta) => {
  const target = new THREE.Vector3(x, y, z);
  const offset = new THREE.Vector3(0, bobHeight, 0);
  mesh.current.position.copy(target.add(offset));
});

// ❌ clone() is an allocation
useFrame(() => {
  const p = camera.position.clone();
  p.y = 0;
  lookTarget.copy(p);
});

// ❌ Fresh array + closures every frame
useFrame(() => {
  const visible = objects.filter((o) => o.visible);
  visible.forEach((o) => (o.rotation.y += 0.01));
});

// ❌ setState per frame — allocates and re-renders the React tree
useFrame(() => setProgress(clock.elapsedTime / duration));
```

## Canonical fix

Hoist scratch objects to module scope (or a `useRef` / `useMemo`) and mutate
them in place. Three.js math classes are all mutable and designed for this.

```ts
const _target = new THREE.Vector3();
const _offset = new THREE.Vector3(0, 0, 0);

function Bobber() {
  const mesh = useRef<THREE.Mesh>(null!);

  useFrame((state, delta) => {
    _target.set(x, y, z);
    _offset.set(0, bobHeight, 0);
    mesh.current.position.copy(_target).add(_offset);
  });
}
```

Module-scope scratch objects are safe as long as nothing holds a reference to
them across a frame boundary and no async work reads them later. Prefix them
with `_` so it's obvious they are throwaway.

For loops over collections, index instead of allocating an intermediate array:

```ts
useFrame(() => {
  for (let i = 0; i < objects.length; i++) {
    const o = objects[i];
    if (o.visible) o.rotation.y += 0.01;
  }
});
```

For values React needs, prefer a ref or a store write over `setState`; write
straight to the object3D when the value only drives the scene.

## Notes

- **Mutating `position` / `rotation` / `scale` in place is free.** Only
  `new`, `clone()`, and array methods allocate. `mesh.position.x += delta` is
  the cheap path.
- **`state.clock.getElapsedTime()` and `delta` do not allocate** — use them
  freely.
- **A `useMemo` scratch object is per-component.** If the component mounts
  many times, that's still one allocation per instance, not per frame — fine.
  Module scope is only better when the objects are genuinely shared.
- **Verify before reporting.** A `new Vector3()` in a `useFrame` body that
  runs behind `if (!dirty) return;` may execute rarely. Read the control flow.
- **Don't chase micro-allocations in setup code.** This check is about the
  frame loop only.

## How to report this finding

> **Where:** `<file>:<line>` (list every allocating line in the loop)
>
> **What's wrong:** `<N>` allocations per frame inside `useFrame` — at 60 FPS
> that's `<N * 60>` objects per second becoming garbage.
>
> **Suggested fix:** hoist to module-scope scratch objects and mutate in place.
>
> **Why it matters:** removes periodic GC hitches; average FPS is unchanged
> but frame-time consistency improves.
