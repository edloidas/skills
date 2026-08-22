# asset-reuse

**Severity:** medium (perf / memory)
**Applies to:** Three.js, React Three Fiber

## What it is

Creating a distinct geometry, material, or texture per object when every
object could share one. The classic shape: a list component that renders 500
cubes, each with its own `<boxGeometry>` and `<meshStandardMaterial>`.

## Why it matters

Two separate costs:

- **Memory.** Every geometry uploads its own vertex buffers, every texture its
  own GPU allocation. 500 identical cubes is 500 buffer uploads for one
  cube's worth of unique data.
- **Draw calls and state changes.** The renderer batches by material. Distinct
  material instances — even with identical parameters — are distinct programs
  and uniform sets from the renderer's point of view, so each one forces a
  state change. Shared materials let the renderer sort and reuse.

The symptom is a scene whose frame cost scales with object count far faster
than the triangle count suggests, plus a `renderer.info.memory.geometries`
count that tracks object count 1:1.

## How to detect

Look for construction inside a map/loop or inside a component body that renders
many times:

```bash
rg -n -B4 '<(box|sphere|plane|cylinder|cone|torus|circle)Geometry\b' --type tsx --type jsx
rg -n -B4 '<mesh(Standard|Basic|Physical|Lambert|Phong|Toon)Material\b' --type tsx --type jsx
```

Then check the enclosing scope: is the JSX inside a `.map(...)`, or in a
component instantiated many times? Read the parent to find out — the geometry
tag alone tells you nothing.

Vanilla Three.js:

```bash
rg -n -B6 'new\s+THREE\.(Mesh|Points|Line)\b' --type ts --type js
```

and check whether the geometry/material arguments were constructed inside the
same loop.

Also check `renderer.info` reporting in the app, if present — a geometry count
close to the object count is the direct evidence.

## Anti-patterns

```tsx
// ❌ 500 geometries, 500 materials, one unique cube
{items.map((item) => (
  <mesh key={item.id} position={item.position}>
    <boxGeometry args={[1, 1, 1]} />
    <meshStandardMaterial color="orange" />
  </mesh>
))}

// ❌ Same problem one level up — the component body allocates per instance
function Cube({ position }) {
  const geometry = useMemo(() => new THREE.BoxGeometry(1, 1, 1), []);
  return <mesh geometry={geometry} position={position} />;
}

// ❌ Loading the same texture per instance instead of once
function Tile() {
  const map = new THREE.TextureLoader().load('/tile.png');
  return <meshBasicMaterial map={map} />;
}
```

The second one is subtle: `useMemo` correctly avoids re-creating on re-render,
but it still creates one geometry **per mounted instance**.

## Canonical fix

Hoist shared assets above the loop.

```tsx
const CUBE_GEOMETRY = new THREE.BoxGeometry(1, 1, 1);
const CUBE_MATERIAL = new THREE.MeshStandardMaterial({ color: 'orange' });

function Cubes({ items }) {
  return items.map((item) => (
    <mesh
      key={item.id}
      geometry={CUBE_GEOMETRY}
      material={CUBE_MATERIAL}
      position={item.position}
    />
  ));
}
```

When the objects differ only in colour, share the geometry and vary a per-mesh
uniform instead of the material — or move to `InstancedMesh` with an instance
colour attribute (see [`instancing`](instancing.md)).

For textures, load once and share:

```tsx
const map = useTexture('/tile.png'); // drei caches by URL
```

## Notes

- **Module-scope assets are never disposed.** That is correct for
  page-lifetime shared assets, and it is the deliberate exception to
  [`resource-disposal`](resource-disposal.md). Say so when reporting both.
- **Shared materials are shared state.** Mutating `material.color` on one mesh
  changes every mesh using it. If objects need independent appearance, either
  clone deliberately or use instancing — do not "fix" the sharing by reverting.
- **drei's `useTexture` / `useGLTF` already share by URL.** A project using
  those consistently only needs this check on imperative loader calls.
- **Reuse and instancing solve overlapping problems.** If the count is high
  enough that reuse matters, instancing is usually the better end state. Report
  reuse as the cheap fix and instancing as the ceiling.
- **Below ~20 objects this rarely matters.** Note it as low severity, or skip.

## How to report this finding

> **Where:** `<file>:<line>` — geometry/material constructed inside
> `<the map or component>`
>
> **What's wrong:** one geometry and one material per object across `<N>`
> objects that are visually identical.
>
> **Suggested fix:** hoist to a module-scope shared instance (or
> `InstancedMesh` if `<N>` is large).
>
> **Why it matters:** cuts GPU memory and per-object state changes; frame cost
> stops scaling with object count.
