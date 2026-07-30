# dpr-cap

**Severity:** high (perf)
**Applies to:** Three.js, React Three Fiber

## What it is

Cap the renderer's `devicePixelRatio` (DPR) so the GPU doesn't shade dramatically
more pixels than necessary on Retina or high-DPR displays.

## Why it matters

A scene that renders comfortably at 1080p on a DPR-1 screen renders internally
near 4K on a DPR-2 Retina display — the GPU shades roughly **4× more pixels**.
For alpha-heavy or fragment-heavy scenes (transparency, post-processing,
volumetrics, complex shaders) this is fillrate-bound work, and frame time
scales linearly with pixel count.

A common symptom: the scene runs at 120 FPS in the dev tool's embedded
preview (where the canvas is small and DPR effectively low), but drops hard
in real fullscreen Chrome on the same machine. The diff isn't logic — it's
internal resolution.

Capping DPR by a **pixel budget** instead of a hard ratio gives consistent
fillrate across screen sizes:

- Small viewport on Retina → uses the full DPR (looks crisp).
- Large viewport on Retina → DPR drops to keep total pixel count bounded
  (stays smooth).

## How to detect

Search for any DPR-related call:

```bash
rg -n 'setPixelRatio|pixelRatio|devicePixelRatio' --type ts --type tsx --type js --type jsx
```

R3F-specific:

```bash
# Canvas dpr prop
rg -n '<\s*Canvas\b[^>]*\bdpr\s*=' --type tsx --type jsx

# gl prop renderer construction
rg -n 'gl\s*=\s*\{[^}]*setPixelRatio' --type tsx --type jsx
```

For each hit, open the file and assess the call site against the
anti-patterns and canonical fix below.

If **no hits** exist in a Three.js / R3F project, that itself is a finding —
the renderer defaults are not safe for fullscreen on Retina. Report as a
missing DPR cap.

## Anti-patterns

```ts
// ❌ Uncapped — can hit DPR 3+ on some phones
renderer.setPixelRatio(window.devicePixelRatio);

// ❌ Hard-coded — ignores low-DPR displays and high-resolution viewports
renderer.setPixelRatio(2);

// ❌ Capped only by a constant — still over-renders at fullscreen
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

// ❌ R3F equivalent — accepts up to 2 unconditionally
<Canvas dpr={[1, 2]} />

// ❌ R3F with raw DPR
<Canvas dpr={window.devicePixelRatio} />
```

The first two are the most common. The `Math.min(..., 2)` pattern is a
half-fix — it stops the worst phones but does nothing about a 4K-display
fullscreen window on a desktop Retina machine, where the canvas itself is
huge and the DPR multiplier compounds.

## Canonical fix

Cap by **the minimum of three signals**: the actual DPR, a hard upper bound,
and a pixel-budget cap derived from the current viewport size.

```ts
const maxPixels = 1_650_000;
const dpr = Math.min(
  window.devicePixelRatio,
  1.5,
  Math.sqrt(maxPixels / (window.innerWidth * window.innerHeight)),
);

renderer.setPixelRatio(Math.max(1, dpr));
```

For React Three Fiber, compute the same value and pass it as `dpr`:

```tsx
function getDpr() {
  const maxPixels = 1_650_000;
  return Math.max(
    1,
    Math.min(
      window.devicePixelRatio,
      1.5,
      Math.sqrt(maxPixels / (window.innerWidth * window.innerHeight)),
    ),
  );
}

<Canvas dpr={getDpr()} ...>
```

### What each piece does

- `window.devicePixelRatio` — never render at higher DPR than the device
  natively reports.
- `1.5` — hard upper cap. Above this the visual gain is marginal; the GPU
  cost is not.
- `Math.sqrt(maxPixels / (innerWidth * innerHeight))` — pixel-budget cap.
  Total rendered pixels = `width * height * dpr²`, so to stay under
  `maxPixels` we need `dpr ≤ sqrt(maxPixels / (width * height))`.
- `Math.max(1, ...)` — floor at 1 so we never render below native pixel
  density on low-DPR screens.

### Tuning `maxPixels`

`1_650_000` is roughly 1080p area × 1.4 — a reasonable default for a desktop
GPU running an alpha-heavy scene. Adjust based on the perf budget you've
measured for the target hardware. Lower = smoother on weaker GPUs, blurrier
on huge displays.

## Notes

- **Recompute on resize.** If the user can resize the window during the
  session (or rotate a device), recompute DPR in the resize handler and call
  `renderer.setPixelRatio` again, followed by `renderer.setSize(w, h, false)`
  to re-apply.
- **Shadow maps and render targets are independent** of `setPixelRatio` —
  they have their own resolution budgets. A DPR cap won't fix oversized
  shadow maps or post-processing render targets.
- **R3F's `dpr={[min, max]}` tuple** is reactive — R3F re-applies it when the
  canvas resizes, but it still uses the ratio directly without a pixel-area
  budget. If you stay with the tuple form, derive `[1, getDpr()]` instead of
  hard-coding `[1, 2]`.
- **The fix is invisible on DPR-1 monitors** — `Math.max(1, ...)` clamps to
  1, and the pixel-budget cap usually doesn't bind at typical desktop
  resolutions. Don't treat that as evidence the fix is unnecessary; the
  problem only shows on Retina / fullscreen.

## How to report this finding

If a setPixelRatio call is uncapped or hard-coded, report:

> **Where:** `<file>:<line>` (and any other call sites)
>
> **What's wrong:** DPR is set to `<the bad value>`, with no pixel-budget
> cap. On Retina/fullscreen this renders ~4× more pixels than the visible
> canvas size, blowing the GPU fillrate budget.
>
> **Suggested fix:** apply the canonical pattern (or `getDpr()` helper for
> R3F).
>
> **Why it matters:** consistent frame rate across screen sizes — especially
> avoids the "smooth in dev preview, choppy in fullscreen" regression.

If `setPixelRatio` is missing entirely, report as `missing` rather than
`uncapped` — the default behavior depends on context (vanilla Three.js
defaults to 1; R3F defaults to `window.devicePixelRatio`), so naming the
state explicitly helps the user reason about what changed.
