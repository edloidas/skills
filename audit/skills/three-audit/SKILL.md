---
name: three-audit
description: >
  Audit Three.js and React Three Fiber code for performance and best-practice
  issues that hurt frame rate or correctness in WebGL scenes — uncapped
  devicePixelRatio, fillrate blowups, missing disposals, render-loop
  allocations, and similar subtle pitfalls. Walks the agent through detecting
  each issue, assessing the offending sites in context, and reporting findings
  grouped by severity. Use when reviewing a 3D scene's perf, before shipping a
  Three.js / R3F build, or when investigating frame-rate regressions
  ("smooth in dev preview, choppy in real fullscreen").
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash Read Grep Glob
user-invocable: true
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

## When to Use This Skill

Trigger phrases: "three audit", "three-audit", "audit threejs", "audit r3f",
"check three.js perf", "review my webgl scene", "why is my scene slow",
"three.js performance review".

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

### Step 3 — Run checks from the catalog

For each row in the **Checks** table below, open
`references/checks/<name>.md` and follow its detection and assessment
guidance. If the user passed `--check=<name>`, run only that one.

### Step 4 — Report findings

Group findings by severity (`high`, `medium`, `low`) and emit one section per
check that produced a finding. Format:

```
### <check-name> — <severity>

**Where:** <file>:<line> [+ more]

**What's wrong:** <one sentence>

**Suggested fix:**
\`\`\`<lang>
<canonical pattern>
\`\`\`

**Why it matters:** <one sentence on the user-visible impact>
```

Skip checks that produced no finding (don't pad the report). End with a tally:
`<N> findings: <high> high, <medium> medium, <low> low`.

## Checks

Catalog of checks. Each one is defined in `references/checks/<name>.md`.

| Check | Topic | Severity |
|-------|-------|----------|
| [`dpr-cap`](references/checks/dpr-cap.md) | Cap `devicePixelRatio` by a pixel budget so Retina/fullscreen doesn't quadruple GPU fillrate | High (perf) |

More checks land here as they're added.

## Severity Guide

- **High** — measurable frame-rate or memory impact under realistic load, or a
  correctness bug that ships visible artifacts. Worth fixing before release.
- **Medium** — perf hit on stress paths or older hardware, or a fragile pattern
  that's likely to break later. Worth scheduling.
- **Low** — minor cleanup, style nit, or a pattern that's only suspect in
  unusual scenes. Note it; don't block on it.

## Adding a New Check

1. Create `references/checks/<name>.md` using the existing checks as a
   template. Required sections: **What it is**, **Why it matters**,
   **How to detect**, **Anti-patterns**, **Canonical fix**, **Notes**.
2. Append a row to the **Checks** table above with topic and severity.
3. If the check needs special detection (beyond grep + read), describe it in
   the check file itself rather than baking shell scripts into the skill —
   keeps each check portable across Claude / Codex / future hosts.

## Out of Scope

- GLSL shader correctness (covered by shader-specific tooling)
- Asset pipeline / model authoring concerns (covered by DCC tooling)
- Browser-level perf tracing (use Chrome DevTools / Spector.js directly)

The audit focuses on patterns visible in the JS/TS source.
