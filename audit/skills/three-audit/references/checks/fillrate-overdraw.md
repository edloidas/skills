# fillrate-overdraw

**Severity:** high (perf)
**Applies to:** Three.js, React Three Fiber

## What it is

Fillrate is the number of fragment-shader invocations per frame. It blows up
when many transparent surfaces stack over the same pixels (overdraw), when
full-screen post-processing passes chain up, or when an expensive material
covers the whole viewport.

## Why it matters

Overdraw is invisible in every count a developer normally looks at. Triangle
count is low, draw calls are low, object count is low — and the frame is still
slow, because a hundred alpha-blended quads each shade the same pixel.
Transparent surfaces cannot use the depth buffer to reject early, so **every**
layer runs its full fragment shader.

The diagnostic signature is a scene whose frame rate depends almost entirely on
window size: shrink the browser window and it recovers, resize to fullscreen
and it collapses. That is fillrate, not geometry.

Post-processing has the same shape — each pass is a full-screen quad at render
resolution, so a five-pass chain shades the viewport five extra times.

## How to detect

```bash
# Transparency and blending
rg -n 'transparent\s*[:=]|opacity\s*[:=]|blending\s*[:=]|AdditiveBlending|depthWrite' \
  --type ts --type tsx --type js --type jsx

# Post-processing chains
rg -n 'EffectComposer|<Effect|RenderPass|UnrealBloom|Bloom|SSAO|DepthOfField|ShaderPass' \
  --type ts --type tsx --type js --type jsx

# Full-screen / very large surfaces
rg -n '<planeGeometry|ScreenQuad|fullscreen|<Backdrop|<Sky\b|<Cloud' \
  --type tsx --type jsx

# Volumetric / particle systems
rg -n '<Sparkles|<Points\b|<points\b|ParticleSystem|<Trail' --type tsx --type jsx
```

Then read the sites and estimate **layers over a typical pixel**: how many
transparent surfaces can stack in the camera's usual view, plus one per
post-processing pass. Three or four is normal. Twenty is a finding.

Also check whether the material work itself is heavy — a `MeshPhysicalMaterial`
with transmission, a raymarched `ShaderMaterial`, or `MeshTransmissionMaterial`
covering a large screen area is fillrate-bound on its own.

## Anti-patterns

```tsx
// ❌ 200 large additive quads, all overlapping in the middle of the screen
{smoke.map((s) => (
  <mesh key={s.id} position={s.position}>
    <planeGeometry args={[8, 8]} />
    <meshBasicMaterial map={puff} transparent blending={THREE.AdditiveBlending} />
  </mesh>
))}

// ❌ Post chain where each pass costs a full screen
<EffectComposer>
  <Bloom /><DepthOfField /><SSAO /><Noise /><Vignette />
</EffectComposer>

// ❌ Transmission material across the whole viewport — renders the scene
//    a second time into a transmission buffer
<mesh scale={100}><meshPhysicalMaterial transmission={1} /></mesh>

// ❌ transparent on a material that has no partial alpha at all
<meshStandardMaterial transparent color="red" />
```

The last one is free to fix and surprisingly common: `transparent: true` opts
the mesh out of the opaque pass and into back-to-front sorted rendering with no
early-z, for no visual benefit.

## Canonical fix

Reduce layers, area, or passes — in that order.

```tsx
// Fewer, larger particles beat many small overlapping ones
<Sparkles count={80} scale={6} size={3} />

// Cut the post chain to what the art direction actually needs,
// and run bloom at reduced resolution
<EffectComposer>
  <Bloom mipmapBlur intensity={0.6} resolutionScale={0.5} />
</EffectComposer>

// Alpha-test instead of alpha-blend where the edges are hard (foliage, decals):
// keeps early-z rejection, no sorting
<meshStandardMaterial map={leaf} alphaTest={0.5} />

// Drop transparent where alpha is always 1
<meshStandardMaterial color="red" />
```

For layered smoke/fog, `depthWrite={false}` with a **smaller count of larger,
lower-opacity** sprites gives the same look at a fraction of the fragment cost.

Cap the damage globally with [`dpr-cap`](dpr-cap.md) — fillrate scales with
`width * height * dpr²`, so the DPR cap is a direct multiplier on everything
in this check.

## Notes

- **Opaque geometry is cheap by comparison.** Early-z rejection means a pixel
  covered by ten opaque surfaces usually shades once. Do not report opaque
  overdraw unless the material is unusually expensive and sorting is disabled.
- **`alphaTest` is not free either** — it disables early-z on some mobile GPUs.
  It is still much cheaper than blending in most desktop cases.
- **Render order matters for correctness, not just cost.** Transparent objects
  sort by distance; if the project sets `renderOrder` by hand, do not suggest
  changes that break the intended layering.
- **This check is confirmed by measurement, not by reading.** The window-resize
  test above is the cheapest confirmation; recommend it in the finding rather
  than asserting a number.
- **Overlaps with [`dpr-cap`](dpr-cap.md).** If both fire, report DPR as the
  cheap global fix and this one as the structural fix. Do not double-count the
  severity.

## How to report this finding

> **Where:** `<file>:<line>` — `<N>` transparent surfaces / `<M>` post passes
>
> **What's wrong:** an estimated `<L>` shaded layers over a typical pixel;
> fragment cost scales with viewport area, so the scene is fillrate-bound.
>
> **Suggested fix:** `<fewer/larger sprites | alphaTest | trim the post chain |
> resolutionScale>`.
>
> **Why it matters:** explains a frame rate that tracks window size rather than
> scene complexity.
