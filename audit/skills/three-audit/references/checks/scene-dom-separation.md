# scene-dom-separation

**Severity:** low (convention / maintainability)
**Applies to:** React Three Fiber
**Conditional:** only when the project has a scene directory (`src/scene/`, or
another directory that clearly holds R3F components) separate from its DOM
component directory. Skip entirely in single-directory projects.

## What it is

3D and DOM components render into different trees through different
reconcilers. The convention keeps them in different files:

- **`src/scene/`** — R3F components: `<mesh>`, `<group>`, `<instancedMesh>`,
  lights, materials, anything that renders inside `<Canvas>`.
- **`src/components/`** — DOM components: `<div>`, Tailwind classes, Radix
  primitives, HUD and menu markup.

A single file should not contain both.

## Why it matters

R3F swaps React's host config inside `<Canvas>`. A `<div>` in a file that also
exports scene children is not a styling mistake — it is a component that
crashes if it is ever rendered on the wrong side of the Canvas boundary, with
an error (`div is not part of the THREE namespace`) that points at the JSX
rather than at the import that put it there.

Mixed files also make the boundary unreviewable. Whether a component is legal
in a given position stops being answerable from its path and starts requiring a
read of its body, which is exactly the kind of thing that decays as a codebase
grows.

The exception that makes the rule workable is drei's `<Html>`, which renders
DOM *from inside* the Canvas through a portal. That is the sanctioned bridge,
and it should be the only one.

## How to detect

Confirm the convention exists before checking it:

```bash
ls -d src/scene src/components 2>/dev/null
```

Then look for files that carry both kinds of markup:

```bash
# DOM tags inside the scene directory
rg -n '<(div|span|button|section|ul|li|p|h[1-6])\b' src/scene --type tsx

# R3F tags inside the DOM component directory
rg -n '<(mesh|group|instancedMesh|points|line|primitive|(ambient|directional|point|spot|hemisphere)Light)\b' \
  src/components --type tsx

# The sanctioned bridge — these hits are not findings
rg -n 'from\s+.@react-three/drei.' src/scene --type tsx | rg 'Html'
```

Read each hit. A DOM tag inside an `<Html>` subtree is correct. A DOM tag as a
direct sibling of scene children is the finding.

## Anti-patterns

```tsx
// ❌ src/scene/Player.tsx — HUD markup living next to scene children
export function Player() {
  return (
    <>
      <mesh ref={ref}>
        <capsuleGeometry />
      </mesh>
      <div className="absolute top-4 left-4">HP: {hp}</div>
    </>
  );
}

// ❌ src/components/GameView.tsx — scene children in a DOM component file
export function GameView() {
  return (
    <div className="h-screen">
      <Canvas>
        <mesh>
          <boxGeometry />
        </mesh>
      </Canvas>
    </div>
  );
}
```

The second one is milder — the JSX is legal — but it puts scene content in a
file whose path says DOM, so it still drifts.

## Canonical fix

Split by tree, and let the DOM side own the HUD:

```tsx
// src/scene/Player.tsx
export function Player() {
  return (
    <mesh ref={ref}>
      <capsuleGeometry />
    </mesh>
  );
}

// src/components/Hud.tsx
export function Hud() {
  const hp = useStore($hp);
  return <div className="absolute top-4 left-4">HP: {hp}</div>;
}

// src/components/GameView.tsx — the one place the two trees meet
export function GameView() {
  return (
    <div className="h-screen">
      <Canvas>
        <Scene />
      </Canvas>
      <Hud />
    </div>
  );
}
```

For labels that must track a 3D position, use the bridge rather than moving the
markup:

```tsx
// src/scene/Nameplate.tsx
<Html position={[0, 2, 0]} center>
  <span className="rounded bg-black/60 px-2">{name}</span>
</Html>
```

## Notes

- **`<Html>` and `<Hud>` from drei are legal inside the scene tree.** They
  portal out. Do not report them.
- **The Canvas host file is the intended meeting point.** One file that mounts
  `<Canvas>` and the HUD side by side is the boundary, not a violation.
- **This is maintainability, not performance.** Rank it low unless a mixed file
  is actually causing a runtime namespace error, and never let it crowd out
  perf findings in the report.
- **Directory names vary.** `src/three/`, `src/webgl/`, `src/game/scene/` are
  the same convention. Match what the repo does.
- **A repo with no scene directory has not adopted this.** Skip the check
  rather than proposing a reorganisation the audit was not asked for.

## How to report this finding

> **Where:** `<file>:<line>`
>
> **What's wrong:** `<file>` under `<scene dir>` renders DOM markup alongside
> scene children (or the reverse), so it is only valid on one side of the
> Canvas boundary and its path does not say which.
>
> **Suggested fix:** move the `<DOM / scene>` half to `<the other directory>`,
> or wrap it in drei's `<Html>` if it has to track a 3D position.
>
> **Why it matters:** keeps the Canvas boundary checkable from the file path.
