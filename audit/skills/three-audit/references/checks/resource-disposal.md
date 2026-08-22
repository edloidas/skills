# resource-disposal

**Severity:** high (memory)
**Applies to:** Three.js, React Three Fiber

## What it is

GPU resources — geometries, materials, textures, render targets — are not
garbage-collected. They hold WebGL handles that live until `.dispose()` is
called explicitly. Anything created imperatively and dropped without disposal
leaks VRAM for the lifetime of the page.

## Why it matters

A leak here is invisible in the JS heap profiler and invisible in a short dev
session. It shows up as a page that runs fine for two minutes and then
degrades: texture thrash, driver-level swapping, and eventually a lost WebGL
context (`THREE.WebGLRenderer: Context Lost`) or a browser tab crash.

The usual trigger is navigation or level switching in a long-lived session —
each scene load allocates fresh GPU resources while the old ones stay
resident. Ten level loads with a 40 MB texture set is 400 MB of VRAM that will
never come back.

## How to detect

Find imperative construction of disposable resources:

```bash
rg -n 'new\s+(THREE\.)?\w*(Geometry|Material|Texture|RenderTarget)\b' \
  --type ts --type tsx --type js --type jsx
rg -n 'TextureLoader|GLTFLoader|useLoader|useTexture|CanvasTexture|VideoTexture' \
  --type ts --type tsx --type js --type jsx
```

Then find the disposal side:

```bash
rg -n '\.dispose\(\)' --type ts --type tsx --type js --type jsx
```

Compare the two. For each imperative construction site, ask: **who owns this,
and when does it die?** A resource is fine if any of these hold:

- It is declarative JSX (`<boxGeometry />`, `<meshStandardMaterial />`) — R3F
  disposes it on unmount automatically.
- It came from `useLoader` / `useTexture` / `useGLTF` — those are cached by
  drei/R3F and intentionally shared across components; disposing them breaks
  other consumers.
- It is module-scope and shared for the page lifetime — never disposed by
  design, and correct.

It is a finding if it is created per-component or per-scene-load, imperatively,
and no cleanup path disposes it.

## Anti-patterns

```ts
// ❌ Created per mount, never disposed
function Panel() {
  const texture = new THREE.CanvasTexture(drawToCanvas());
  return <meshBasicMaterial map={texture} />;
}

// ❌ useMemo without a matching cleanup — useMemo has no teardown
const geometry = useMemo(() => new THREE.BufferGeometry(), []);

// ❌ Manual scene teardown that drops children without disposing them
scene.remove(mesh); // handles still allocated

// ❌ Disposing a shared cached resource — breaks every other consumer
const tex = useTexture('/wood.png');
useEffect(() => () => tex.dispose(), [tex]);

// ❌ Render target recreated on every resize, old one leaked
useEffect(() => {
  target = new THREE.WebGLRenderTarget(width, height);
}, [width, height]);
```

`useMemo` is the most common trap: it reads like a lifecycle hook but has no
teardown, so a memoized geometry survives unmount with its GPU handle intact.

## Canonical fix

Pair every imperative creation with a disposal in the same lifecycle.

```tsx
function Panel() {
  const texture = useMemo(() => new THREE.CanvasTexture(drawToCanvas()), []);
  useEffect(() => () => texture.dispose(), [texture]);

  return <meshBasicMaterial map={texture} />;
}
```

For render targets that track size, dispose the previous one before replacing:

```tsx
useEffect(() => {
  const target = new THREE.WebGLRenderTarget(width, height);
  setTarget(target);
  return () => target.dispose();
}, [width, height]);
```

For imperative scene teardown, walk the subtree:

```ts
function disposeSubtree(root: THREE.Object3D) {
  root.traverse((obj) => {
    const mesh = obj as THREE.Mesh;
    mesh.geometry?.dispose();
    const material = mesh.material;
    if (Array.isArray(material)) material.forEach((m) => m.dispose());
    else material?.dispose();
  });
}
```

Textures are deliberately excluded from that walk — they are usually shared
between materials, so disposing them per-mesh is wrong. Dispose textures where
they were loaded, once.

## Notes

- **Prefer declarative JSX.** `<boxGeometry args={[1, 1, 1]} />` is disposed by
  R3F automatically. The whole check largely disappears in a codebase that
  stays declarative.
- **`useGLTF` / `useTexture` results are cached and shared.** Never dispose
  them in a component. Use `useGLTF.clear(url)` / `useTexture.clear(url)` if
  the app genuinely needs to evict the cache.
- **`material.dispose()` does not dispose its textures**, and
  `geometry.dispose()` does not dispose attribute buffers referenced elsewhere.
  Ownership has to be tracked by hand.
- **`renderer.info.memory`** (`{ geometries, textures }`) is the cheapest way
  to confirm a leak: log it across a few mount/unmount cycles and check whether
  the counts return to baseline. Recommend this rather than asserting a leak
  you can only see statically.
- **Post-processing passes own render targets.** An `EffectComposer` created
  imperatively needs `composer.dispose()`.

## How to report this finding

> **Where:** `<file>:<line>` — `<resource type>` created here
>
> **What's wrong:** created per `<mount / scene load / resize>` with no
> `.dispose()` on any teardown path, so the GPU handle outlives the component.
>
> **Suggested fix:** pair with a `useEffect` cleanup (or switch to declarative
> JSX so R3F disposes it).
>
> **Why it matters:** prevents VRAM growth across navigations that ends in a
> lost WebGL context.

Report a resource as **suspected** rather than confirmed when the ownership
path is not fully visible in the source, and suggest checking
`renderer.info.memory` to confirm.
