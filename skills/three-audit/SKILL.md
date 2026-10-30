---
name: three-audit
description: >
  Audit Three.js and React Three Fiber code for performance and correctness issues that hurt
  frame rate in WebGL scenes — uncapped devicePixelRatio, fillrate blowups, missing disposals,
  render-loop allocations, and similar pitfalls. Walks through detecting each issue, assessing
  the offending sites in context, and reporting findings grouped by severity.
when_to_use: >
  When reviewing a 3D scene's performance, before shipping a Three.js / R3F build, or when
  investigating a frame-rate regression — "smooth in dev preview, choppy in fullscreen", "why
  is my scene slow", "the scene hitches". Also on "three audit", "audit threejs", "audit r3f",
  or when reviewing a change touching renderer setup, `useFrame`, materials, shadows,
  instancing, or texture loading.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Read Grep Glob Bash(rg:*) Bash(jq:*) Bash(ls:*) Bash(find:*)
argument-hint: "[<target-dir>] [--check=<name>]"
metadata:
  tier: routed
---

# Three.js / R3F Audit

## Purpose

**This skill reports; it never edits the scene.** After a run the working tree
is byte-identical. Most checks need judgment: a grep hit needs a read.

Detection commands assume `rg` (ripgrep) and `jq` are on `PATH`. Substitute
`grep -rn` and a manual read of `package.json` where they are not. ripgrep has no
`tsx` or `jsx` type: `--type ts` already covers `.tsx`, `--type js` covers `.jsx`, and a
JSX-only search uses `-g '*.tsx' -g '*.jsx'`.

## Workflow

### Step 1 — Resolve the audit root and confirm Three.js / R3F

The audit root is `<target-dir>` when the user passed one, otherwise the current directory.
Run every later command from that root.

```bash
jq -r '
  ((.dependencies // {}) + (.devDependencies // {}) + (.peerDependencies // {}))
  | to_entries
  | map(select(.key | test("^(three$|@react-three/)")))
  | .[].key
' package.json
```

Read the outcome by its cause. Stop only where a row says so:

| Outcome | Action |
|---|---|
| A `three` or `@react-three/*` key printed | Continue to Step 2 |
| `jq` not on `PATH` | Read `package.json` directly; if it cannot be read either, put `project detection — jq missing` on the not-run list and let Step 2's anchors decide |
| No match, and the root is a workspace (`pnpm-workspace.yaml`, or a `workspaces` field) | Run the workspace search below, then Steps 2–5 once per matching package with its directory as the root; findings keep repo-relative paths. No match → stop: does not apply |
| No `package.json` at the root | Stop: no Node project at `<root>` — name the path so the user can pass a `<target-dir>` |
| No match, not a workspace | Stop: the audit does not apply |

```bash
# Workspace members that depend on Three.js or R3F
rg -l -g '**/package.json' -g '!**/node_modules/**' '"(three|@react-three/[^"]+)"\s*:' .
```

### Step 2 — Find renderer entry points

These are the anchors most checks key off of:

```bash
# Vanilla Three.js renderer construction
rg -n 'new\s+(THREE\.)?WebGLRenderer\b' --type ts --type js

# React Three Fiber Canvas mounts
rg -n '<\s*Canvas\b' -g '*.tsx' -g '*.jsx'

# R3F imperative GL access
rg -n "useThree\(|gl\s*[:=]" -g '*.tsx' -g '*.jsx'
```

Note the file paths — each check refers back to them. Close the step with one
line: `Anchors: 1 WebGLRenderer, 2 Canvas mounts, 6 useThree sites across 14 files.`

### Step 3 — Decide which conditional checks apply

The convention checks encode project conventions, not Three.js rules. Running
them against a project that never adopted the convention produces noise, so
activate each one only on its signal:

```bash
# useframe-priority — is a priority argument used anywhere?
# Multiline, PCRE2: a numeric last argument at the call's own depth, e.g.
# useFrame((state, delta) => {...}, 1). Without PCRE2, read the `useFrame(` hits.
rg -U -P -n 'useFrame\((?:[^()]|(\((?:[^()]|(?1))*\)))*,\s*-?\d+\s*\)' -g '*.tsx' -g '*.jsx'

# scene-dom-separation — is there a scene directory distinct from components?
ls -d src/scene src/three src/webgl src/components 2>/dev/null

# store-wiring — does the project use nanostores? (its detection is nanostores-only)
jq -r '((.dependencies // {}) + (.devDependencies // {})) | keys[]' package.json \
  | rg '^nanostores$|^@nanostores/'
```

No signal → skip that check and record it. Each check file restates its own
activation condition; follow that over this summary if they disagree.

Keep a running **not-run list** from Step 1 to the report. Every check that does
not execute goes in it with its reason, whatever the reason: a conditional check
with no signal, a check `--check=<name>` excluded, a check whose detection needs
`rg` or `jq` where neither is on `PATH`, a check whose target files could not be
read. A run that names only the conditional skips reads as a full audit.

### Step 4 — Run checks from the catalog

For each row in the **Checks** tables below, open
`references/checks/<name>.md` and follow its detection and assessment
guidance. If the user passed `--check=<name>`, run only that one.

A grep hit is a candidate, not a finding — most checks list legitimate uses of
the pattern they detect. List every candidate site a check produced and open all
of them in one response before writing any of its findings.

Close the step with one line: `Checks: 11 of 14 run, 47 candidate sites read, 6 findings.`

### Step 5 — Report findings

Group findings by severity (`high`, `medium`, `low`) and emit one section per
check that produced a finding, in the shape of the filled report below.

Each check file ends with a **How to report this finding** section — use its
wording so findings from different checks read consistently.

Skip checks that produced no finding (don't pad the report). End with a tally,
`<N> findings: <high> high, <medium> medium, <low> low`, then a **Not run**
list — one line per entry on the not-run list from Step 3, with its reason.

A filled report:

```markdown
### dpr-cap — high

**Where:** src/scene/Stage.tsx:41

**What's wrong:** `<Canvas dpr={window.devicePixelRatio}>` is uncapped, so a 2x
Retina display at fullscreen shades 4x the pixels of the dev preview.

**Suggested fix:** cap by a pixel budget, not a ratio alone:
\`\`\`tsx
const getDpr = () =>
  Math.max(1, Math.min(window.devicePixelRatio, 1.5,
    Math.sqrt(1_650_000 / (window.innerWidth * window.innerHeight))))

<Canvas dpr={getDpr()}>
\`\`\`

**Why it matters:** This is the "smooth in the preview pane, choppy fullscreen"
regression — frame time roughly quadruples with no visible quality gain.

### render-loop-allocations — high

**Where:** src/scene/Orbiter.tsx:58, src/scene/Trail.tsx:24

**What's wrong:** `new THREE.Vector3()` inside `useFrame`, allocating two vectors
per frame per instance — 240 objects/s at 120 fps.

**Suggested fix:**
\`\`\`ts
const tmp = useMemo(() => new THREE.Vector3(), [])
useFrame(() => { tmp.set(x, y, z); mesh.current.position.copy(tmp) })
\`\`\`

**Why it matters:** Minor GC pauses land as visible hitches during motion.

2 findings: 2 high, 0 medium, 0 low

**Not run:**
- `store-wiring` — no `nanostores` dependency in `package.json`
- `useframe-priority` — no `useFrame` priority argument anywhere in the tree
- `texture-budget` — `public/textures/` is git-lfs and the pointers did not
  resolve; on-disk sizes could not be read
```

Then stop. Report the findings; do not apply a suggested fix, and do not start a
second pass over the same catalog.

## Lens Mode

`changes-review` invokes this skill as a stack lens when the diff touches Three.js or R3F
files. In that mode:

- The caller supplies the scope. Audit exactly the files it resolved and no more — a whole-scene
  audit returns findings the run cannot attribute to the change
- Skip Step 1's project detection; the caller already matched on the imports
- Return findings in the shape the caller asked for, not the report format above
- Conditional convention checks map to the caller's lowest severity

Standalone invocation is unaffected and stays the primary path.

## Checks

Catalog of checks. Each one is defined in `references/checks/<name>.md`.

### Performance and correctness

| Check | Topic | Severity |
|-------|-------|----------|
| [`dpr-cap`](references/checks/dpr-cap.md) | Cap `devicePixelRatio` by a pixel budget so Retina/fullscreen doesn't quadruple GPU fillrate | High (perf) |
| [`fillrate-overdraw`](references/checks/fillrate-overdraw.md) | Stacked transparency and post-processing passes shading the same pixels many times over | High (perf) |
| [`render-loop-allocations`](references/checks/render-loop-allocations.md) | `new Vector3` and friends inside `useFrame`, producing GC hitches | High (perf) |
| [`resource-disposal`](references/checks/resource-disposal.md) | Geometries, materials, textures, and render targets leaking VRAM without `.dispose()` | High (memory) |
| [`useframe-workload`](references/checks/useframe-workload.md) | `setState`, scene lookups, and raycasts running every frame when they don't need to | High (perf) |
| [`asset-reuse`](references/checks/asset-reuse.md) | A distinct geometry/material per object where one shared instance would do | Medium (perf/memory) |
| [`instancing`](references/checks/instancing.md) | Hundreds of identical meshes that should be one `InstancedMesh` | Medium (perf) |
| [`shadow-cost`](references/checks/shadow-cost.md) | Shadow map resolution, casting light count, and shadow cameras fitted to nothing | Medium (perf) |
| [`material-recompiles`](references/checks/material-recompiles.md) | Shader-define changes at runtime causing main-thread GLSL recompiles | Medium (perf) |
| [`texture-budget`](references/checks/texture-budget.md) | Oversized or uncompressed textures, wrong colour space, mipmaps disabled | Medium (memory/perf) |
| [`frustum-culling`](references/checks/frustum-culling.md) | Culling disabled, stale bounding volumes, or one merged mesh spanning the scene | Medium (perf) |

### Project conventions (conditional)

Run only when Step 3 found the activation signal.

| Check | Topic | Severity |
|-------|-------|----------|
| [`store-wiring`](references/checks/store-wiring.md) | Atom store reads that don't subscribe, and unbatched related writes | Medium (perf/convention) |
| [`useframe-priority`](references/checks/useframe-priority.md) | Gameplay at priority 1, effects at priority 2, so effects don't sample stale transforms | Medium (correctness/convention) |
| [`scene-dom-separation`](references/checks/scene-dom-separation.md) | 3D components under `src/scene/`, DOM/HUD under `src/components/`, never mixed in one file | Low (convention) |

## Severity Guide

- **High** — measurable frame-rate or memory impact under realistic load, or a
  correctness bug that ships visible artifacts. Worth fixing before release.
- **Medium** — perf hit on stress paths or older hardware, or a fragile pattern
  that's likely to break later. Worth scheduling.
- **Low** — minor cleanup, style nit, or a pattern that's only suspect in
  unusual scenes. Note it; don't block on it.

The severity in the table is the check's default. Adjust it for the scene you
are looking at and say why — 300 unshared materials in a 12-object scene is
still low.

## Adding a New Check

Maintainer steps are in `references/adding-a-check.md`.

## Out of Scope

- GLSL shader correctness (covered by shader-specific tooling)
- Model authoring — mesh topology, UV layout, rigging, DCC export settings
- Browser-level perf tracing (use Chrome DevTools / Spector.js directly)
- General React patterns — effects, memoization, state architecture (use
  `react-audit`; this skill only covers React as it meets the Canvas)

The audit reads the JS/TS source; only `texture-budget.md` also sizes texture files on disk, since delivery is a renderer concern.
