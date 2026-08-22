# texture-budget

**Severity:** medium (memory / perf)
**Applies to:** Three.js, React Three Fiber

## What it is

Textures uploaded at higher resolution than they are ever displayed at, in
uncompressed formats, with wrong colour space, or with mipmaps and filtering
misconfigured.

## Why it matters

A 4096×4096 RGBA texture is 64 MB in VRAM uncompressed, and 85 MB with
mipmaps — for one map. A PBR material with base colour, normal, roughness, and
AO at that size is over 300 MB. Mobile GPUs have a few hundred MB of usable
texture memory in total, so the page either thrashes or loses the WebGL
context.

Beyond memory, oversized textures hurt sampling: minified textures without
mipmaps alias badly and, more importantly, sample cache-hostile — nearby
fragments read distant texels, so the texture cache misses constantly. It looks
like a shimmering, noisy surface that is also slow.

Colour space is a correctness issue in the same file: an albedo map decoded as
linear renders washed out, and a normal map decoded as sRGB produces wrong
lighting.

## How to detect

```bash
# Texture loading
rg -n 'TextureLoader|useTexture|useKTX2|KTX2Loader|CompressedTextureLoader|EXRLoader|RGBELoader' \
  --type ts --type tsx --type js --type jsx

# Colour space / filtering / mipmaps
rg -n 'colorSpace|encoding|SRGBColorSpace|generateMipmaps|minFilter|magFilter|anisotropy' \
  --type ts --type tsx --type js --type jsx
```

Then look at the files on disk — this is the one check where the source alone
is not enough:

```bash
find . -path ./node_modules -prune -o \
  \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \
     -o -iname '*.ktx2' -o -iname '*.hdr' -o -iname '*.exr' \) -print0 \
  | xargs -0 ls -lS 2>/dev/null | head -25
```

Anything above ~2 MB is worth reading about. If ImageMagick is available,
`identify -format '%f %wx%h\n'` gives dimensions; otherwise report file size
and ask the user for the intended display size.

Compare against how the texture is used: a 4K map on an object that occupies
200 screen pixels is 4K wasted.

## Anti-patterns

```ts
// ❌ Albedo map decoded as linear — washed-out colours
const map = new THREE.TextureLoader().load('/albedo.png');
// missing: map.colorSpace = THREE.SRGBColorSpace;

// ❌ Normal / roughness / AO map tagged sRGB — wrong lighting
normalMap.colorSpace = THREE.SRGBColorSpace;

// ❌ Mipmaps disabled on a texture that is minified
map.generateMipmaps = false;
map.minFilter = THREE.LinearFilter;

// ❌ 4096² PNGs shipped for props a few hundred pixels tall

// ❌ Anisotropy left at 1 on a ground plane viewed at a grazing angle
```

## Canonical fix

Set colour space by role — colour maps are sRGB, data maps are not:

```ts
albedo.colorSpace = THREE.SRGBColorSpace;   // map, emissiveMap, specularMap
normal.colorSpace = THREE.NoColorSpace;     // normalMap, roughnessMap,
                                            // metalnessMap, aoMap, displacementMap
```

R3F's `useTexture` sets sRGB on the `map` slot for you; the data maps still
need checking.

Ship compressed textures for anything large. KTX2/Basis stays compressed in
VRAM — roughly 4–8× smaller than RGBA — and decodes on the GPU:

```bash
npx @gltf-transform/cli optimize in.glb out.glb --texture-compress ktx2
```

```tsx
const map = useKTX2('/textures/ground.ktx2');
```

Leave mipmaps on (the default) for anything minified, and raise anisotropy on
surfaces seen at a grazing angle:

```ts
map.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());
```

Size textures to their on-screen footprint: 512² for props, 1024–2048² for
hero assets and ground, 2048² for an environment map unless it is the
background of a reflective scene.

## Notes

- **Mipmaps must stay off for render targets and data textures** —
  `generateMipmaps = false` with `NearestFilter` is correct for lookup tables,
  data buffers, and anything sampled by exact texel. Do not report those.
- **`NearestFilter` is a deliberate art choice** in pixel-art and voxel
  projects. Check the surrounding scene before calling it a mistake.
- **Power-of-two dimensions no longer matter** in WebGL2 for mipmapping, so
  non-POT sizes are not a finding on their own.
- **Compressed formats trade quality for memory.** KTX2 on normal maps can show
  banding; flag it as a consideration rather than pushing compression
  everywhere.
- **`renderer.info.memory.textures`** gives the live count, and the browser's
  memory tooling gives the size. Recommend measuring before a large
  re-authoring effort.

## How to report this finding

> **Where:** `<file>:<line>` (source) / `<asset path>` (`<size>`, `<WxH>`)
>
> **What's wrong:** `<oversized for its display size | uncompressed | wrong
> colour space | mipmaps disabled on a minified texture>`.
>
> **Suggested fix:** `<downscale to NxN | convert to KTX2 | set colorSpace to
> ... | re-enable mipmaps>`.
>
> **Why it matters:** `<VRAM saved>` and removes texture thrash on mobile /
> fixes the incorrect shading.
