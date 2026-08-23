---
name: react-audit
description: >
  Find the React problems linters cannot see: effects that should not exist, effects that re-run for
  the wrong reason, memoization that is missing or pointless, state that should be an action or a
  reducer, and components that have outgrown themselves. Reports, never edits. Use after building or
  reworking a React feature, when reviewing a change that touches components or hooks, or when a
  component works but nobody can explain its re-renders.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash(bash:*) Bash(git:*) Bash(jq:*) Bash(grep:*) Bash(mktemp:*) Task Read Glob Grep
argument-hint: "[file, directory, or empty for changed files]"
metadata:
  author: edloidas
---

# React Audit

## Purpose

Deep review of React code across three tracks: architectural analysis inline, mechanical convention
checks in a subagent, and — when the binary is reachable — react-doctor. Finds and reports; it never
edits. Applying what it finds is `review:code-cleanup`'s job, or the caller's.

**Linter-aware.** Biome and ESLint already own hook rules, dependency arrays, self-closing elements,
fragments, type imports, and unused variables. This skill skips all of it.

## When to Use

- After building or reworking a React feature, before it is committed
- Reviewing a change that touches components, hooks, or state
- A component works but has become hard to reason about — unexplained re-renders, an effect chain
  nobody wants to touch, a file that keeps growing
- Invoked as a stack lens by `review:changes-review` when the diff contains React files

Trigger phrases: "review react", "audit react", "check components", "react patterns", "effects
review", "why does this re-render".

## Commands

| Command | Scope |
|---------|-------|
| `/react-audit` | Staged and unstaged changes |
| `/react-audit path/file.tsx` | One file |
| `/react-audit src/components/` | A directory |

---

## Phase 1: Load Context

### 1.1 Confirm this is a React project

Check `package.json` for a `react` dependency. If there is none, stop and say so — do not audit a
non-React codebase against React rules.

### 1.2 Detect the React version and the compiler

Both gate which findings are even valid, so resolve them before analysis, not during it.

```bash
jq -r '.dependencies.react // .devDependencies.react // "none"' package.json
grep -rl "babel-plugin-react-compiler\|reactCompiler" --include="*.config.*" --include="package.json" . | head -3
```

- **React 19+** — `useActionState`, `useTransition` for pending state, `ref` as a plain prop, ref
  callback cleanups, and `use()` are all available. `useEffectEvent` is stable from 19.2.
- **React 18** — none of the above. Do not recommend them.
- **React Compiler enabled** — skip every memoization finding. The compiler inserts memoization
  itself, so `useMemo` / `useCallback` / `memo` advice is noise there.

Carry all three answers into Phase 2; the reference files describe how each one gates their rules.

### 1.3 Read project rules

Read these if they exist, skip silently if not:

```
.cursor/rules/react.mdc
.cursor/rules/typescript.mdc
.cursor/rules/stores.mdc
.claude/rules/react.md
.claude/rules/typescript.md
```

With no project rules, fall back to the defaults in `references/`.

### 1.4 Detect conventions

```bash
grep -rl "\.displayName\s*=" src/ --include="*.tsx" | head -3
grep -rl "data-component" src/ --include="*.tsx" | head -3
```

- `displayName` found in 2+ files → activate the `displayName` and `data-component` checks
- Not found → skip both entirely, so projects without the convention get no false positives
- `props-naming`, `variable-order`, `component-props-ref`, and `destructuring` are always active

### 1.5 Identify target files

- `$ARGUMENTS` given → that file or directory
- Otherwise → `git diff --name-only HEAD` plus `git diff --name-only --cached`
- Filter to `.tsx` and `.ts` files that import React
- Read every target file before analyzing it

If the filter leaves nothing, report that there are no React files in scope and stop.

---

## Phase 2: Dispatch Tracks

Start all applicable tracks at once so they run concurrently.

### Track A: react-doctor (optional)

An external binary, so treat it as a bonus rather than a dependency. Create a summary file and a
diagnostics directory with `mktemp`, then run the bundled script with the scope that matches
Phase 1.5:

```bash
bash <skill-dir>/scripts/run-react-doctor.sh . "$OUT" "$DIAG" --scope files --include-untracked
```

| Phase 1.5 resolved | Scope args |
|--------------------|------------|
| Working-tree changes | `--scope files --include-untracked` |
| A file or directory | none — react-doctor scans the project, so filter its findings to the target paths in Phase 3 |
| A base ref (lens mode) | `--scope changed --base <ref>` |

The script needs nothing installed. It prefers a react-doctor already in the project or on `PATH`,
then falls back to `bunx`, `pnpm dlx`, or `npx` to fetch it for the run. `bunx` is first on purpose:
it resolves from its own cache, where `npx` will populate the nearest `node_modules` when it finds a
`package.json` above the working directory — a side effect an audit should not have. It writes nothing into the
project and opts out of telemetry, the score API, and crash reporting, so no source metadata leaves
the machine — drop `--no-score` from the script if you want the 0-100 health score back and the
network call that computes it is acceptable.

**Read `$DIAG/diagnostics.json`, not the terminal summary.** It is an array of objects with
`filePath`, `line`, `endLine`, `rule`, `severity`, `category`, `title`, `message`, and `help` —
everything Phase 3 needs to merge and dedupe, with no text to parse:

```bash
jq -r '.[] | "\(.filePath):\(.line) [\(.category)/\(.severity)] \(.rule) — \(.title)"' "$DIAG/diagnostics.json"
```

The directory also holds one `.txt` per triggered rule, each with the rule's fix guidance and a docs
URL. Read those only for rules you are about to report.

**Exit code says whether the tool ran, never whether the code is clean.** A warning-level finding
still exits 0. Always read `diagnostics.json`.

| Exit | Meaning | Do |
|------|---------|-----|
| 3 | No react-doctor binary and no bunx/pnpm/npx to fetch one | Skip Track A, continue |
| 4 | Present but would not start — offline, or resolution failed | Skip Track A, continue |
| 0 or 1 | Ran | Read `diagnostics.json` |

A skipped Track A is normal, not an error. Never install anything to satisfy it, never retry, and
never block the other tracks on it. The report says the track was skipped and why; Tracks B and C
carry the audit on their own.

Run it in the background if the host supports that — the other tracks do not depend on it.

### Track B: Mechanical checks (subagent)

1. Read `references/mechanical-checks-prompt.md` for the prompt template
2. Read `references/rules-conventions.md` for the rules
3. Replace `{{CONVENTIONS}}` with only the conventions Phase 1.4 activated, and `{{FILE_LIST}}` with
   the target paths
4. Dispatch a subagent with that prompt to scan the target files against the active convention rules
   and return structured violations, each with a file, a line, and the rule it breaks

These are read-only pattern matches, so a cheap subagent is enough. If the host has no subagent
facility, run the same prompt inline.

### Track C: Deep analysis (inline)

Load `references/rules-effects.md` and `references/rules-patterns.md`, then analyze each target file:

**Effects** — the 16 anti-patterns in `rules-effects.md`. Flag each with its number and the fix.
Patterns 15 and 16 are React 19-only; #4 is void when the compiler is on.

**Patterns** — memoization strategy (skip entirely under the compiler), `ref.current` in dependency
arrays, ref callbacks and their cleanups, early returns versus conditional rendering, throttle and
debounce construction, context splitting, data fetching in effects over ~15 lines, components over
200 lines, and related `useState` calls that should be a `useReducer`.

---

## Phase 3: Collect and Merge

1. Read `$DIAG/diagnostics.json` if Track A ran, whatever its exit code, and filter to the target
   paths. Treat each entry as a hypothesis, not a verdict: open the file at `line` and confirm it
   before reporting, the same standard Track C is held to
2. Collect the Track B violations
3. Combine with Track C

**Deduplicate.** Same file, same line range, same category from more than one track: keep the most
detailed version and record every track that found it. react-doctor and Track C overlap most — a
`no-fetch-in-effect` diagnostic and Effects #13 are usually one finding, and react-doctor's `help`
text plus the rule's `.txt` file often sharpen the fix Track C would have written alone.

**Drop what is out of scope.** Anything Biome or ESLint already reports, and anything outside the
target paths.

---

## Phase 4: Output

### Buckets

| Bucket | Holds | Ordering |
|--------|-------|----------|
| Critical | Causes a bug or wrong behavior — races, stale closures, effects that fire wrong | First |
| Improvements | Architecture and pattern changes that are judgment calls | Second |
| Conventions | Project convention violations from Track B | Last, always |

**Conventions rank below everything else and never gate anything.** They are cleanup-shaped, not
correctness-shaped: report them so the picture is complete, then hand them to `review:code-cleanup`,
which is the skill that actually applies changes.

### Finding format

```markdown
## path/to/Component.tsx

### Critical

**1. Race condition in fetch effect** (`Component.tsx:45-58`) [Effects #13]
**Current:** Raw fetch in useEffect without cleanup — a stale response can overwrite a fresh one
**Fix:** Add an ignore flag in the cleanup, or move to the project's query library
**Found by:** Deep analysis, react-doctor

### Improvements

**2. Extract data fetching to a custom hook** (`Component.tsx:30-72`) [Patterns]
**Current:** 40 lines of fetch logic in the component body
**Fix:** `useItemData`, following the project's existing `use*Data` pattern
**Found by:** Deep analysis

### Conventions

**3. Missing displayName** (`Component.tsx`) [displayName]
**Fix:** `Component.displayName = COMPONENT_NAME;`
**Found by:** Mechanical check
```

### Summary table

After the file sections:

```markdown
## Summary

Tracks: deep analysis, mechanical checks. react-doctor skipped (exit 3 — no runner available).
React 19.1, compiler off.

| # | Finding | Bucket | Location | Found by |
|---|---------|--------|----------|----------|
| 1 | Race condition in fetch effect | Critical | `Component.tsx:45-58` | Deep, RD |
| 2 | Extract data fetching to a hook | Improvement | `Component.tsx:30-72` | Deep |
| 3 | Missing displayName | Convention | `Component.tsx` | Mech |
```

**Always open with the track line.** Which tracks ran, which were skipped and why, the React
version, and whether the compiler is on. A reader cannot judge coverage without it.

The setup recommendation, when it applies, goes after this table — see the next section. Nothing
else follows the findings.

### No findings

```markdown
## React audit: clean

Tracks: deep analysis, mechanical checks, react-doctor. React 19.1, compiler off.
4 files in scope, no findings.
```

---

## Recommending a Permanent Setup

**The audit itself never installs anything.** Track A always uses the ephemeral runner — fetched for
the run, cached outside the project, gone afterwards. That holds even when you are about to
recommend a permanent setup, and it holds if the user says yes: they run the install, not you.

A permanent setup is worth recommending anyway, because the ephemeral run is a snapshot. Installed,
react-doctor runs from a `doctor` script, scans each PR in CI, and is available to the agent between
audits.

Recommend it when **all** of these hold:

- **The repo is large enough to keep paying off.** 20+ React files, or an established component
  tree. A handful of components does not need a CI gate
- **Nothing already sets it up.** No `doctor.config.{ts,mts,cts,js,mjs,cjs,json,jsonc}`, no
  `reactDoctor` key in `package.json`, no react-doctor dependency, no react-doctor CI workflow
- **The scan actually found something.** Recommend on any `error`-severity entry in
  `diagnostics.json`, or on a real volume of `warning`-severity ones. A clean scan is an argument
  against the recommendation, not for it

```bash
jq -r 'group_by(.severity)[] | "\(.[0].severity): \(length)"' "$DIAG/diagnostics.json"
```

**Put it at the very end** — the last lines of the output, after the summary table and after every
finding. It is a suggestion about tooling, and it must never sit between the reader and the findings
they came for:

> react-doctor found N issues here (E errors, W warnings) and is not set up in this repo.
> `bunx react-doctor@latest install` adds it as a dev dependency, a `doctor` package script, a skill
> for your agents, and a CI workflow that scans each pull request.

**Recommend it, never run it — including with `--dry-run`.** Observed behavior of `install` in
0.9.12: it adds a `doctor` script and a `react-doctor` devDependency to `package.json`, writes a
lockfile, populates `node_modules`, adds `.github/workflows/react-doctor.yml`, and drops a skill
directory into the config directory of every agent it detects. `--dry-run` printed a "would install"
list and the same writes still landed, so treat it as an install, not a preview. This skill does not
make repo-wide changes.

Say it once, and drop it if the user has declined before.

## Lens Mode

`review:changes-review` invokes this skill as a stack lens when the diff contains React files. In
that mode:

- The caller supplies the scope. Use exactly the files it resolved — do not widen to the project
- Return findings in the shape the caller asked for, not the format above
- Conventions map to the caller's lowest severity, and never to anything higher
- Track A uses `--scope changed --base <ref>` so it reports only what the change introduced
- Skip the setup recommendation entirely — a review report is not the place for it
- Everything else — the phases, the reference rules, the version gates — is unchanged

Standalone invocation is unaffected and stays the primary path.

## Rules

- **Read before analyzing** — never flag code you have not read
- **Respect the version gates** — a React 19 fix on a React 18 project is a wrong answer, and
  memoization advice under the compiler is noise
- **Conventions are opt-in** — only when Phase 1.4 detected them
- **No linter overlap** — skip anything Biome or ESLint already reports
- **No false positives** — flag only what you are certain of, and say when the current approach is a
  defensible trade-off
- **Never mutate** — no edits, no installs, no config written into the project
- **Show the before and after** for anything non-obvious, and name the project's own pattern when
  one exists

## Keywords

react, audit, review, effects, useEffect, useEffectEvent, hooks, react compiler, memoization,
re-renders, conventions, displayName, data-component, architecture, patterns, react-doctor
