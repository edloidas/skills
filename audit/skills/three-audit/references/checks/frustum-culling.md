# frustum-culling

**Severity:** medium (perf)
**Applies to:** Three.js, React Three Fiber

## What it is

Three.js skips objects whose bounding sphere lies outside the camera frustum.
The check breaks in three ways: culling explicitly disabled, bounding volumes
that are stale or far larger than the object, and geometry merged or instanced
into one huge unit that is never off-screen.

## Why it matters

When culling works, off-screen objects cost nothing beyond the frustum test.
When it does not, every object is submitted every frame — draw call, uniform
upload, and vertex shading for geometry the camera cannot see. In a large
world this is the difference between frame cost tracking what is visible and
frame cost tracking the entire scene.

The signature: frame rate that does not improve when the camera looks at empty
sky, and `renderer.info.render.calls` that stays flat as the camera turns.

## How to detect

```bash
# Culling explicitly turned off
rg -n 'frustumCulled\s*[:=]\s*(false|\{false\})' --type ts --type tsx --type js --type jsx

# Bounding volume computation — needed after geometry mutation
rg -n 'computeBoundingSphere|computeBoundingBox|boundingSphere|boundingBox' \
  --type ts --type tsx --type js --type jsx

# Geometry mutated after creation
rg -n 'setAttribute\(|attributes\.position|\.needsUpdate\s*=\s*true' \
  --type ts --type tsx --type js --type jsx

# Merged / instanced units
rg -n 'mergeGeometries|mergeBufferGeometries|InstancedMesh|<Merged\b' \
  --type ts --type tsx --type js --type jsx
```

For each `frustumCulled = false`, find the justification. There are legitimate
ones (see Notes) — this check is about the ones with no reason.

For mutated geometry, check whether `computeBoundingSphere()` is called after
the mutation. If not, the bounding sphere reflects the original vertex data and
the object will either be culled while visible (it pops out) or never culled.

## Anti-patterns

```ts
// ❌ Culling disabled to "fix" a popping bug whose real cause is a stale bound
mesh.frustumCulled = false;

// ❌ Vertices moved, bounds never recomputed — object pops in and out wrongly
geometry.attributes.position.array[0] = 1000;
geometry.attributes.position.needsUpdate = true;
// missing: geometry.computeBoundingSphere();

// ❌ The whole world merged into one mesh — a single bounding sphere
//    covering everything, so nothing is ever culled
const world = mergeGeometries(allChunkGeometries);

// ❌ A skinned mesh whose bind-pose bounds are far smaller than its animation
```

## Canonical fix

Recompute bounds whenever vertex data changes:

```ts
geometry.attributes.position.needsUpdate = true;
geometry.computeBoundingSphere();
geometry.computeBoundingBox(); // only if raycasting/Box3 checks need it
```

Chunk large merged geometry so culling has something to reject:

```ts
// One merged mesh per spatial cell instead of one for the whole world
const chunks = groupByCell(geometries, CELL_SIZE);
const meshes = chunks.map((cell) => new THREE.Mesh(mergeGeometries(cell), material));
```

Give instanced meshes a bounding volume that reflects where instances actually
are, so the whole batch can be rejected when off-screen:

```ts
instancedMesh.computeBoundingSphere(); // after filling instanceMatrix
```

And remove `frustumCulled = false` where the underlying cause was a stale
bound — fix the bound instead.

## Notes

- **Legitimate reasons to disable culling**, which are not findings: objects
  whose vertex positions are computed in the vertex shader (GPU-driven
  particles, morphing, procedural displacement), sky domes and backdrops that
  are always in view, and `Points` clouds whose displayed positions diverge
  from the attribute data. Expect a comment explaining it; if there is none,
  report it as *unexplained* rather than *wrong*.
- **Culling is per-object, not per-triangle.** A single mesh spanning the whole
  world is never culled, however little of it is visible. That is the
  chunking case above, and it is the one worth acting on.
- **Culling and instancing pull against each other.** Instancing removes draw
  calls; culling removes work per object. For scattered instances across a
  large area, several `InstancedMesh` batches per region beat one global batch.
- **Skinned meshes** use the bind-pose bounding volume by default. If an
  animation moves vertices well outside it, set a manual `boundingSphere` on
  the geometry rather than disabling culling.
- **Small scenes do not benefit.** Below a few hundred objects, or when
  everything is on screen anyway, note it as low and move on.

## How to report this finding

> **Where:** `<file>:<line>`
>
> **What's wrong:** `<culling disabled with no stated reason | bounds not
> recomputed after mutating vertex data | one merged mesh spanning the scene>`,
> so off-screen geometry is submitted every frame.
>
> **Suggested fix:** `<recompute bounds | chunk the merge | remove the
> frustumCulled override>`.
>
> **Why it matters:** frame cost starts tracking what is visible instead of
> what exists.
