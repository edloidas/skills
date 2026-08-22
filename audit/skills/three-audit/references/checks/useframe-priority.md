# useframe-priority

**Severity:** medium (correctness / convention)
**Applies to:** React Three Fiber
**Conditional:** only when the project already passes a priority argument to
`useFrame` in at least one place, or its instructions state a priority
convention. Otherwise report at most one low-severity note.

## What it is

`useFrame(callback, priority)` controls the order frame callbacks run in.
Callbacks run in ascending priority; ties fall back to mount order, which is
effectively arbitrary. The convention this check enforces:

- **priority `1`** — gameplay and simulation: movement, physics integration,
  state transitions, anything that decides where things *are*.
- **priority `2`** — visual effects: camera follow, trails, particles,
  shaders, anything that *samples* where things are.

Gameplay updates first, so effects sample the current frame's positions rather
than the previous frame's.

## Why it matters

Without an explicit priority, ordering is mount order. A camera-follow callback
that happens to mount before the player-movement callback reads last frame's
position, every frame. The result is a camera that lags one frame behind — a
subtle, persistent judder that looks like a smoothing bug and survives every
attempt to fix it in the smoothing code.

The same one-frame lag hits trails, attached particles, look-at targets, and
anything that derives a transform from another object. It is invisible when
standing still and obvious when moving fast, which is why it usually ships.

The failure is also *unstable*: reordering imports, extracting a component, or
lazy-loading a chunk changes mount order and moves the bug around.

## How to detect

```bash
# Every frame callback, with and without a priority argument
rg -n 'useFrame\(' --type tsx --type jsx

# Calls that pass a priority
rg -n 'useFrame\([^)]*\},\s*-?\d' --type tsx --type jsx
```

Establish whether the convention is in force: if some callbacks pass a priority
and others do not, the ones without it are the finding. If **none** do, the
project has not adopted the convention — do not fill the report with a finding
per callback; raise it once, as a single low-severity note.

Then classify each callback that lacks a priority: does it *write* a transform
(gameplay) or *read* one to derive something (effect)? A callback that reads
another object's transform and has no priority is the high-value hit.

Note also that `useFrame` with **any** non-zero priority disables R3F's
automatic render. If a project uses priorities, exactly one callback must call
`state.gl.render(state.scene, state.camera)` — check that it does.

## Anti-patterns

```tsx
// ❌ No priority — camera may sample the player's previous-frame position
function Player() {
  useFrame((_, delta) => {
    ref.current.position.addScaledVector(velocity, delta);
  });
}

function FollowCamera() {
  useFrame(() => {
    camera.position.lerp(playerRef.current.position, 0.1);
  });
}

// ❌ Effect before gameplay — guarantees the one-frame lag
useFrame(cameraFollow, 1);
useFrame(playerMovement, 2);

// ❌ Priorities used, but nothing renders — R3F's auto-render is off
useFrame(playerMovement, 1);
useFrame(cameraFollow, 2);
// missing: a callback that calls gl.render(...)
```

## Canonical fix

```tsx
// Gameplay / simulation — decides where things are
useFrame((state, delta) => {
  ref.current.position.addScaledVector(velocity, delta);
}, 1);

// Visual effects — samples where things are
useFrame((state) => {
  camera.position.lerp(playerRef.current.position, 0.1);
}, 2);
```

If the project uses priorities anywhere, one callback owns the render, last:

```tsx
useFrame((state) => {
  state.gl.render(state.scene, state.camera);
}, 3);
```

## Notes

- **This is a project convention, not a Three.js rule.** The numbers are
  arbitrary; the ordering they encode is not. If a repo uses a different scheme
  (`0`/`10`/`20`, named constants), check consistency with *that* scheme rather
  than imposing `1`/`2`.
- **Ordering only matters between callbacks that share data.** Two independent
  animations do not need priorities, and adding them everywhere is noise.
  Report the read-after-write pairs, not every callback.
- **The one-frame lag is real but small.** Rank it medium unless the project
  has a camera or trail bug that this explains, in which case it is the answer
  and worth ranking high.
- **Post-processing changes the render owner.** With an `EffectComposer`, the
  composer's `render()` takes the last slot instead of `gl.render`.

## How to report this finding

> **Where:** `<file>:<line>` (the effect callback) and `<file>:<line>` (the
> gameplay callback it reads from)
>
> **What's wrong:** neither passes a `useFrame` priority, so ordering is mount
> order — `<the effect>` can sample `<the source>` one frame stale.
>
> **Suggested fix:** priority `1` for the gameplay callback, `2` for the
> effect; if any priority is used, add an explicit render callback last.
>
> **Why it matters:** removes a one-frame lag that reads as camera judder and
> cannot be fixed by tuning the smoothing.
