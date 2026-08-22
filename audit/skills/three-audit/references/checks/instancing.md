# instancing

**Severity:** medium (perf)
**Applies to:** Three.js, React Three Fiber

## What it is

Rendering many copies of the same geometry as separate `Mesh` objects instead
of a single `InstancedMesh` (or `Points` for sprites, or a merged geometry for
static objects).

## Why it matters

Every `Mesh` is at least one draw call. The CPU cost of a draw call is roughly
fixed regardless of how many triangles it submits, so 2,000 ten-triangle rocks
cost far more than one 20,000-triangle mesh. Past a few hundred objects the
main thread becomes the bottleneck and the GPU idles — the frame rate is
CPU-bound and adding a faster GPU changes nothing.

`InstancedMesh` submits all copies in one draw call, with per-instance
transforms (and optionally colours) in an attribute buffer. The usual result on
a few thousand objects is a 5–20× drop in CPU frame time.

## How to detect

Count the objects a render path can produce. Look for `.map(...)` over a
collection that yields `<mesh>`, or loops that `scene.add(new THREE.Mesh(...))`:

```bash
rg -n -A6 '\.map\(' --type tsx --type jsx | rg -n '<mesh\b'
rg -n 'scene\.add\(' --type ts --type js
```

Then find whether instancing is already used:

```bash
rg -n 'InstancedMesh|instancedMesh|<Instances\b|<Merged\b|InstancedBufferAttribute' \
  --type ts --type tsx --type js --type jsx
```

The finding needs a count. Read the data source — a fixed-length array, a
config constant, a generator — and state the number. "Could be many" is not a
finding; "renders `PARTICLE_COUNT = 4000` meshes" is.

If the app exposes `renderer.info.render.calls`, that number is the direct
evidence.

## Anti-patterns

```tsx
// ❌ 4,000 draw calls per frame
{Array.from({ length: 4000 }).map((_, i) => (
  <mesh key={i} position={positions[i]}>
    <sphereGeometry args={[0.05, 8, 8]} />
    <meshBasicMaterial color="white" />
  </mesh>
))}

// ❌ Vanilla equivalent
for (const p of points) {
  const mesh = new THREE.Mesh(geometry, material);
  mesh.position.copy(p);
  scene.add(mesh);
}
```

## Canonical fix

For a fixed count with per-instance transforms:

```tsx
const _matrix = new THREE.Matrix4();

function Rocks({ transforms }: { transforms: Transform[] }) {
  const ref = useRef<THREE.InstancedMesh>(null!);

  useLayoutEffect(() => {
    transforms.forEach((t, i) => {
      _matrix.compose(t.position, t.quaternion, t.scale);
      ref.current.setMatrixAt(i, _matrix);
    });
    ref.current.instanceMatrix.needsUpdate = true;
  }, [transforms]);

  return (
    <instancedMesh ref={ref} args={[undefined, undefined, transforms.length]}>
      <sphereGeometry args={[0.05, 8, 8]} />
      <meshBasicMaterial color="white" />
    </instancedMesh>
  );
}
```

drei's `<Instances>` / `<Instance>` gives the same result with a declarative
API when the instances need to stay individually addressable:

```tsx
<Instances limit={4000}>
  <sphereGeometry args={[0.05, 8, 8]} />
  <meshBasicMaterial />
  {transforms.map((t, i) => <Instance key={i} position={t.position} />)}
</Instances>
```

Pick the alternative that matches the objects:

| Situation | Use |
| --- | --- |
| Many copies of one geometry, transforms change | `InstancedMesh` |
| Many copies, static, different geometries | `BufferGeometryUtils.mergeGeometries` |
| Camera-facing dots or sprites | `Points` with a `PointsMaterial` |
| A handful of distinct meshes | Leave as-is |

## Notes

- **Instancing costs flexibility.** Instances share one material, cannot be
  raycast individually without extra work (`InstancedMesh.raycast` returns an
  `instanceId`), and are culled as one unit — see
  [`frustum-culling`](frustum-culling.md).
- **Per-instance colour** goes through `setColorAt` + `instanceColor.needsUpdate`,
  not a per-instance material.
- **Updating `instanceMatrix` every frame is not free** — it re-uploads the
  whole buffer. For mostly-static instances, update only on change; for fully
  static ones set `instanceMatrix.setUsage(THREE.StaticDrawUsage)`.
- **Merging is better than instancing for static scenery** — one draw call and
  no per-instance buffer, at the cost of losing individual transforms.
- **Under ~100 objects, don't recommend this.** The rewrite cost exceeds the
  win, and the code gets harder to read.

## How to report this finding

> **Where:** `<file>:<line>`
>
> **What's wrong:** renders `<N>` separate meshes of the same geometry — `<N>`
> draw calls per frame where one would do.
>
> **Suggested fix:** `InstancedMesh` (or `<Instances>` / merged geometry, per
> the table above).
>
> **Why it matters:** collapses `<N>` draw calls to 1; removes the CPU-bound
> ceiling on object count.
