# material-recompiles

**Severity:** medium (perf)
**Applies to:** Three.js, React Three Fiber

## What it is

Changing a material property that is baked into the shader program — a define,
a map slot going from `null` to a texture, `transparent`, `vertexColors`,
`flatShading` — forces Three.js to compile a new GLSL program. Compilation is
synchronous on the main thread and takes tens of milliseconds.

## Why it matters

A shader compile is a **frame-length stall**, not a slow frame. 20–200 ms of
blocked main thread produces a visible freeze, and it lands exactly when the
user does something — picks up an object, walks into a new area, toggles a
setting. That timing is what makes it feel like a bug rather than a perf issue.

The related failure is the first-frame stall: every material in the scene
compiles the moment it first becomes visible, so the transition from loading
screen to gameplay is a long hitch even though everything was "already loaded".

## How to detect

```bash
# Shader-affecting mutations
rg -n '\.needsUpdate\s*=\s*true' --type ts --type tsx --type js --type jsx
rg -n 'onBeforeCompile|customProgramCacheKey|\.defines\b' --type ts --type tsx --type js --type jsx

# Material properties changed at runtime
rg -n '\.(transparent|vertexColors|flatShading|alphaTest|side|fog|toneMapped)\s*=' \
  --type ts --type tsx --type js --type jsx

# Map slots assigned after construction
rg -n '\.(map|normalMap|roughnessMap|emissiveMap|alphaMap|envMap)\s*=' \
  --type ts --type tsx --type js --type jsx

# Precompilation, the fix side
rg -n 'compileAsync|renderer\.compile\(|<Preload\b' --type ts --type tsx --type js --type jsx
```

For each hit, determine when it runs. In an event handler or `useFrame`, it is
a finding. In setup before the first render, it is not.

R3F-specific: a JSX prop that changes across renders (`transparent={hovered}`,
`key={...}` on a material) recreates or recompiles the material — check props
bound to state.

## Anti-patterns

```tsx
// ❌ Recompiles on every hover — transparent is a program define
<meshStandardMaterial transparent={hovered} color={hovered ? 'red' : 'white'} />

// ❌ Assigning a map for the first time at runtime adds USE_MAP and recompiles
useEffect(() => {
  if (unlocked) material.map = glowTexture;
}, [unlocked]);

// ❌ needsUpdate in the frame loop — a compile attempt every frame
useFrame(() => {
  material.needsUpdate = true;
});

// ❌ key remount on a material — throws away the compiled program
<meshStandardMaterial key={variant} color={colors[variant]} />

// ❌ Defines mutated per instance, so every instance gets its own program
material.defines.USE_RIM = level > 3;
```

## Canonical fix

Make the shader-affecting state constant, and vary only uniforms.

```tsx
// color, opacity, emissiveIntensity, and every uniform are free to animate.
// transparent stays fixed so the program never changes.
<meshStandardMaterial transparent color={hovered ? 'red' : 'white'} />
```

When two genuinely different shader configurations are needed, build both up
front and swap the material reference rather than mutating one:

```tsx
const [normalMat, glowMat] = useMemo(
  () => [
    new THREE.MeshStandardMaterial({ map: base }),
    new THREE.MeshStandardMaterial({ map: base, emissiveMap: glow, emissive: 'white' }),
  ],
  [base, glow],
);

<mesh material={unlocked ? glowMat : normalMat} />
```

Precompile everything before the scene becomes interactive:

```tsx
// R3F / drei
<Preload all />
```

```ts
// vanilla — async where supported, so it does not block
await renderer.compileAsync(scene, camera);
```

## Notes

- **Uniforms are free; defines are not.** `color`, `opacity`, `roughness`,
  `metalness`, `emissiveIntensity`, and any `uniforms.*.value` on a
  `ShaderMaterial` change without recompiling. Anything that adds or removes a
  `#define` in the generated GLSL does recompile.
- **Swapping between two textures in an existing slot is cheap.** Going from
  `null` to a texture (or back) is not — that toggles `USE_MAP`.
- **`material.needsUpdate = true` is required after changing a define** — the
  problem is doing it at a moment the user can feel, not doing it at all.
- **`onBeforeCompile` without `customProgramCacheKey`** defeats program
  caching: Three.js cannot tell two customised materials apart, so it may reuse
  or rebuild the wrong one. Flag the pair.
- **Programs are cached per renderer.** The same configuration compiles once;
  repeated toggling A→B→A is cheap after the first pass in each direction. A
  one-time hitch on first hover is still worth precompiling away.

## How to report this finding

> **Where:** `<file>:<line>`
>
> **What's wrong:** `<the property>` is a shader define and changes at
> `<hover / unlock / every frame>`, forcing a GLSL recompile on the main
> thread.
>
> **Suggested fix:** keep it constant and animate a uniform instead, or
> prebuild both material variants and swap the reference.
>
> **Why it matters:** removes a multi-frame freeze at the exact moment the user
> interacts.
