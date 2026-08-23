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
---

# Three.js / R3F Audit

## Purpose

A curated catalog of WebGL performance and correctness checks for Three.js and
React Three Fiber projects. Each check is one self-contained file describing
what to look for, why it matters, and how to fix it. The skill walks you
through running them against a target codebase and producing a structured
findings report.

This is not a linter — most checks need contextual judgment, not just
pattern-matching. The agent is expected to read the offending code and reason
about whether the pattern actually applies in this scene.

Detection commands assume `rg` (ripgrep) and `jq` are on `PATH`. Substitute
`grep -rn` and a manual read of `package.json` where they are not.

## When to Use This Skill

- Reviewing a 3D scene's performance, or before shipping a Three.js / R3F build
- Investigating a frame-rate regression, especially one that tracks window size
- Reviewing a change that touches renderer setup, `useFrame`, materials, shadows,
  instancing, or texture loading

## Workflow

### Step 1 — Confirm the project actually uses Three.js / R3F

```bash
jq -r '
  ((.dependencies // {}) + (.devDependencies // {}) + (.peerDependencies // {}))
  | to_entries
  | map(select(.key | test("^(three$|@react-three/)")))
  | .[].key
' package.json 2>/dev/null
```

If nothing matches, stop and tell the user the audit doesn't apply.

### Step 2 — Find renderer entry points

These are the anchors most checks key off of:

```bash
# Vanilla Three.js renderer construction
rg -n 'new\s+(THREE\.)?WebGLRenderer\b' --type ts --type tsx --type js --type jsx

# React Three Fiber Canvas mounts
rg -n '<\s*Canvas\b' --type tsx --type jsx

# R3F imperative GL access
rg -n "useThree\(|gl\s*[:=]" --type tsx --type jsx
```

Note the file paths — each check refers back to them.

### Step 3 — Decide which conditional checks apply

The convention checks encode project conventions, not Three.js rules. Running
them against a project that never adopted the convention produces noise, so
activate each one only on its signal:

```bash
# useframe-priority — is a priority argument used anywhere?
rg -n 'useFrame\([^)]*\},\s*-?\d' --type tsx --type jsx

# scene-dom-separation — is there a scene directory distinct from components?
ls -d src/scene src/three src/webgl src/components 2>/dev/null

# store-wiring — is there an external atom store?
jq -r '((.dependencies // {}) + (.devDependencies // {})) | keys[]' package.json 2>/dev/null \
  | rg 'nanostores|zustand|jotai|valtio'
```

No signal → skip that check and say so in the report's skipped list. Each check
file restates its own activation condition; follow that over this summary if
they disagree.

### Step 4 — Run checks from the catalog

For each row in the **Checks** tables below, open
`references/checks/<name>.md` and follow its detection and assessment
guidance. If the user passed `--check=<name>`, run only that one.

Read every candidate site before reporting it. Most checks list legitimate
uses of the pattern they detect — a grep hit is a candidate, not a finding.

### Step 5 — Report findings

Group findings by severity (`high`, `medium`, `low`) and emit one section per
check that produced a finding. Format:

```markdown
### <check-name> — <severity>

**Where:** <file>:<line> [+ more]

**What's wrong:** <one sentence>

**Suggested fix:**
\`\`\`<lang>
<canonical pattern>
\`\`\`

**Why it matters:** <one sentence on the user-visible impact>
```

Each check file ends with a **How to report this finding** section — use its
wording so findings from different checks read consistently.

Skip checks that produced no finding (don't pad the report). End with a tally:
`<N> findings: <high> high, <medium> medium, <low> low`, followed by one line
naming any conditional checks skipped for lack of a signal.

## Lens Mode

`review:changes-review` invokes this skill as a stack lens when the diff touches Three.js or R3F
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

1. Create `references/checks/<name>.md` using the existing checks as a
   template. Required sections: **What it is**, **Why it matters**,
   **How to detect**, **Anti-patterns**, **Canonical fix**, **Notes**, and
   **How to report this finding**.
2. Append a row to the appropriate **Checks** table above with topic and
   severity.
3. If the check is conditional on a project convention, state the activation
   signal in a `**Conditional:**` line in its header block and add the
   detection command to Step 3.
4. If the check needs special detection (beyond grep + read), describe it in
   the check file itself rather than baking shell scripts into the skill —
   keeps each check portable across Claude / Codex / future hosts.

## Out of Scope

- GLSL shader correctness (covered by shader-specific tooling)
- Model authoring — mesh topology, UV layout, rigging, DCC export settings
- Browser-level perf tracing (use Chrome DevTools / Spector.js directly)
- General React patterns — effects, memoization, state architecture (use
  `react-audit`; this skill only covers React as it meets the Canvas)

The audit reads the JS/TS source. The one exception is
[`texture-budget`](references/checks/texture-budget.md), which also sizes the
texture files on disk, because how a texture is *delivered* — dimensions,
format, colour space — is a renderer concern that the source alone cannot
answer. How it was *authored* is not.
