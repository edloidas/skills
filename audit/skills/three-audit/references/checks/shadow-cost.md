# shadow-cost

**Severity:** medium (perf)
**Applies to:** Three.js, React Three Fiber

## What it is

Shadow maps re-render the scene from each shadow-casting light's point of view,
every frame, at a resolution the developer chooses. Defaults and copy-pasted
configs routinely make this the single most expensive thing in a scene.

## Why it matters

Each shadow-casting light adds a full extra render pass over every casting
object (six passes for a point light — it renders a cube map). A 4096×4096
shadow map is 16.8 M texels, more pixels than the visible frame at 1080p, and
it costs that every frame even when nothing moved.

Three multipliers stack: number of casting lights × shadow map resolution ×
number of casting objects. A scene with three shadow-casting point lights at
2048² is eighteen extra scene renders per frame. The symptom is a frame rate
that halves the moment shadows are enabled and barely responds to reducing
scene detail.

## How to detect

```bash
# Shadow enablement
rg -n 'shadowMap|castShadow|receiveShadow|shadows' --type ts --type tsx --type js --type jsx

# Resolution and camera frustum config
rg -n 'shadow-mapSize|shadow\.mapSize|shadow-camera-|shadow\.camera\.' \
  --type ts --type tsx --type js --type jsx

# Light types that cast
rg -n '<(directional|point|spot)Light\b|new\s+THREE\.(Directional|Point|Spot)Light' \
  --type ts --type tsx --type js --type jsx
```

For each shadow-casting light, record: light type, `mapSize`, shadow camera
bounds, and whether the light or the casters ever move. Then check how many
objects set `castShadow` — a blanket `traverse(o => o.castShadow = true)` puts
every mesh in the scene into every shadow pass.

## Anti-patterns

```tsx
// ❌ 4096² on a light that lights a small area
<directionalLight castShadow shadow-mapSize={[4096, 4096]} />

// ❌ Point light shadows — six render passes for one light
<pointLight castShadow />

// ❌ Everything casts, including things nothing can see the shadow of
scene.traverse((o) => { o.castShadow = true; o.receiveShadow = true; });

// ❌ Default shadow camera on a directional light — a 10-unit box,
//    so distant geometry silently drops out or the map is wasted on empty space
<directionalLight castShadow position={[100, 100, 100]} />

// ❌ Static scene re-rendering its shadow map every frame
```

## Canonical fix

Budget shadows explicitly. Three levers, in order of payoff:

**1. Fewer casting lights.** One directional light casting, everything else
lighting without shadows, is the usual right answer.

```tsx
<directionalLight castShadow position={[10, 20, 10]} intensity={1} />
<ambientLight intensity={0.4} />
<pointLight intensity={0.6} /> {/* no castShadow */}
```

**2. Fit the shadow camera to the area that actually needs shadows**, then
lower `mapSize` — texel density is resolution ÷ frustum size, so a tight
frustum at 1024² beats a loose one at 4096².

```tsx
<directionalLight
  castShadow
  position={[10, 20, 10]}
  shadow-mapSize={[1024, 1024]}
  shadow-camera-left={-15}
  shadow-camera-right={15}
  shadow-camera-top={15}
  shadow-camera-bottom={-15}
  shadow-camera-near={1}
  shadow-camera-far={60}
/>
```

**3. Cast selectively.** Ground planes and backdrops should `receiveShadow`
only; small props usually need neither.

For a scene whose casters and lights are static, render the shadow map once:

```ts
renderer.shadowMap.autoUpdate = false;
renderer.shadowMap.needsUpdate = true; // set again whenever something moves
```

## Notes

- **`PCFSoftShadowMap` is more expensive than `PCFShadowMap`** and much more
  than `BasicShadowMap`. Check `renderer.shadowMap.type` alongside resolution.
- **Baked lighting or a contact-shadow approximation beats real shadows** for
  static scenes. drei's `<ContactShadows>` / `<AccumulativeShadows>` render
  once and cost nothing per frame — recommend them when the scene is static.
- **Shadow acne and peter-panning are correctness bugs, not perf**, but they
  show up in the same config. If `shadow-bias` is a large negative number
  (say, below `-0.005`), that is usually a band-aid over a badly fitted shadow
  camera — worth a low-severity note.
- **Shadow maps ignore `setPixelRatio`.** Fixing [`dpr-cap`](dpr-cap.md) does
  not reduce shadow cost.
- **Confirm before asserting.** The cheapest proof is toggling
  `renderer.shadowMap.enabled` and comparing frame time. Suggest it rather
  than claiming a specific speedup.

## How to report this finding

> **Where:** `<file>:<line>` — `<light type>` with `mapSize <W>×<H>`
>
> **What's wrong:** `<N>` shadow-casting lights at `<resolution>`, so `<N>`
> (or `<N*6>` for point lights) extra full scene passes per frame.
>
> **Suggested fix:** reduce to one casting directional light, fit the shadow
> camera, drop `mapSize` to `<value>` — or bake with `<ContactShadows>` if the
> scene is static.
>
> **Why it matters:** shadow passes are frequently the largest single item in
> the frame budget; this is usually the biggest available win.
