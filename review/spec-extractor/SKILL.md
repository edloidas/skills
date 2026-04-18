---
name: spec-extractor
description: >
  Extract a behavioral specification from a source-code bundle — from a handful of files up to a
  whole 500+ file application. Produces reproducible, stack-neutral specs that another engineer or
  LLM could use to rebuild the same observable behavior without reading the original source. Use
  when the user wants to reverse-engineer a library or module's contract, understand an
  application in detail, or prepare input for a reimplementation.
license: MIT
compatibility: Claude Code
allowed-tools: Read Write Glob Grep Task Bash
argument-hint: "[path(s), feature description, or empty for active repo]"
metadata:
  author: edloidas
---

# Spec Extractor

## Purpose

Extract a behavioral specification from a source-code bundle — anywhere from ≤6 files up to a 500+ file application. The output is detailed enough that another engineer or LLM could rebuild the same observable behavior in any language or framework without reading the original source.

The skill orchestrates a pipeline of bundled plugin agents: a scout that maps structure, module analyzers that produce medium-depth summaries, a contract resolver for cross-module events and exports, deep analyzers for flagged critical modules, an auditor that verifies the spec against source, and a synthesizer that assembles the final output directory.

## When to Use

- User says: "extract a spec from X", "analyze what X does", "understand X's contract", "reverse engineer", "produce a reimplementation spec".
- User wants to understand a whole application or a specific module in detail.
- User wants a reproducible, stack-neutral spec — not documentation, not an API reference, but a behavioral contract.

## Invocation Modes

Three forms, detected at invocation time:

| Form | Example | Skill interpretation |
|------|---------|----------------------|
| **No args** | `/spec-extractor` | Walk the active repo from the working directory |
| **Paths** | `/spec-extractor src/foo src/bar.ts modules/lib/src` | Explicit files / folders; folders expanded |
| **Guide** | `/spec-extractor auth flow`, `/spec-extractor the message bus` | Natural-language scope — skill searches with Grep/Glob and proposes a file list |

**Detection rule:** if every argument resolves to an existing file or directory on disk → paths mode. Otherwise → guide mode.

## Tiers

The skill auto-selects a tier based on resolved bundle size:

| Tier | Range | Pipeline |
|------|-------|----------|
| **Small** | ≤ 6 files or ≤ 1500 LOC | `spec-analyzer` → `spec-auditor` → single-file output |
| **Medium** | 7–30 files | `spec-scout` → parallel `spec-module-analyzer` → `spec-contract-resolver` → `spec-synthesizer` → `spec-auditor` |
| **Large** | 31+ files, up to 500+ | Medium pipeline + parallel `spec-analyzer` deep dives on flagged critical modules |

## Dependencies

Bundled plugin agents (`review/agents/`):
- `review:spec-scout` — architecture map + module inventory + critical-module nomination
- `review:spec-module-analyzer` — medium-depth per-module summary
- `review:spec-analyzer` — deep 11-section spec per module
- `review:spec-contract-resolver` — cross-module events, exports, integrations
- `review:spec-synthesizer` — aggregation and final file assembly
- `review:spec-auditor` — verification against source

References:
- `references/spec-template.md` — unified output schema
- `references/severity-rubric.md` — Critical/Warning/Note definitions (mirrors auditor)
- `references/calibration-guide.md` — forward-looking guidance for a future calibration skill

## Workflow

### Phase 1: Scope Resolution

**Step 1: Resolve mode.**

If `$ARGUMENTS` is empty → whole-repo mode. Set `roots = ["."]`.

Else, test each argument against the filesystem. If every argument is a readable file or directory → paths mode. Set `roots = <arguments>`. Otherwise → guide mode. Set `guide = $ARGUMENTS`.

**Step 2: Collect candidate files.**

For paths mode and whole-repo mode: use `Glob` on each root for these extensions by default:
`**/*.{ts,tsx,js,jsx,mjs,cjs}`.

Apply exclusion filter (unconditional):
- `**/node_modules/**`
- `**/build/**`, `**/dist/**`, `**/out/**`, `**/.build/**`, `**/target/**`
- `**/*.d.ts`
- `**/*.test.*`, `**/*.spec.*`, `**/__tests__/**`
- `**/.git/**`
- Any path matched by `.gitignore` (read `.gitignore` and honor its patterns)

For guide mode: use the guide string to drive `Grep` across the project (case-insensitive, token-split). Rank candidate files by number of hits. Take the top 20–40 files as the provisional bundle. Then apply the exclusion filter.

**Step 3: Count and select tier.**

```
file_count = number of files after filtering
loc = sum of line counts (use `Bash: wc -l` for speed)
tier = Small if file_count ≤ 6 or loc ≤ 1500
       Medium if file_count ≤ 30
       Large otherwise
```

**Step 4: Confirm bundle with the user.**

Present a summary and use `AskUserQuestion`:

```
Bundle resolved:
- Mode: <whole-repo | paths | guide>
- Files: N
- LOC: N
- Tier: <Small | Medium | Large>
- Roots: <list>
- Language(s): <detected>
```

Question: "Proceed with this bundle?"
- **Proceed** *(Recommended)* — begin analysis
- **Narrow** — re-ask with a narrower guide or path set
- **Edit** — user supplies a trimmed file list
- **Cancel** — abort

**Budget gates:**
- If `file_count > 200`: include a warning in the bundle summary — "This will dispatch approximately N parallel agents over M minutes. Confirm to proceed."
- If `file_count > 500`: recommend narrowing first. Still allow Proceed if the user insists.

### Phase 2: Destination

**Step 5: Choose destination root.**

`AskUserQuestion`:
- **`docs/` (Recommended)** — project-visible, likely versioned
- **`.claude/docs/`** — agent-scoped, typically gitignored
- **`/tmp/`** — scratch, ephemeral (timestamped filenames)
- **Other** — user supplies a custom path

**Step 6: Collision handling.**

Determine target:
- Small tier → `<dest>/spec.md` (file)
- Medium / Large tier → `<dest>/spec/` (directory)

Check if the target exists. If yes, `AskUserQuestion`:
- **`spec-<N>.md` / `spec-<N>/` (Recommended)** — auto-incremented
- **`spec-<name>.md` / `spec-<name>/`** — user supplies `<name>`
- **Overwrite** — replace existing content
- **Other** — custom filename / subdirectory

`/tmp/` always uses timestamped names, skip collision check.

### Phase 3: Pipeline Dispatch

Resolve the temp directory:

```bash
bash -c 'printf "%s" "${TMPDIR:-/tmp}"'
```

Use it as `<TMP>`. Create a session subdirectory: `<TMP>/spec-extractor-${CLAUDE_SESSION_ID}/`.

#### Small Tier

Skip scout, module analyzers, contract resolver, synthesizer.

1. **Dispatch `spec-analyzer`** via `Task`:
   - `subagent_type: "review:spec-analyzer"`
   - `model: "opus"`
   - `prompt`: file list + role hints + instruction to follow its agent contract

2. **Write raw analyzer output** to `<TMP>/spec-extractor-${CLAUDE_SESSION_ID}/analyzer.md`.

3. **Dispatch `spec-auditor`** via `Task`:
   - `subagent_type: "review:spec-auditor"`
   - `model: "opus"`
   - `prompt`: mode=`per-module`, source file list, path to analyzer output

4. **Write raw auditor output** to `<TMP>/spec-extractor-${CLAUDE_SESSION_ID}/auditor.md`.

5. **Assemble final file.** Use `Write` to produce `<dest>/spec.md`:

```markdown
# Behavioral Specification

**Bundle:** <bundle-name>
**Generated:** <ISO 8601>
**Files:** N
**Tier:** Small

<analyzer output verbatim>

---

## Audit Findings

<auditor output verbatim>
```

6. **Report.** Print output path + `N Critical / N Warning / N Note`.

#### Medium Tier

1. **Scout pass.** Single `Task` dispatch:
   - `subagent_type: "review:spec-scout"`
   - `model: "opus"`
   - `prompt`: bundle file list, file count, LOC, tier
   - Write output to `<TMP>/spec-extractor-${CLAUDE_SESSION_ID}/scout.md`

2. **Parse modules from scout output.** Extract the Module Inventory table. For each row, collect the module name, path, and file subset.

3. **Parallel module analysis.** Dispatch `spec-module-analyzer` per module, capped at **5 concurrent**. For larger module counts, dispatch in batches of 5 in successive messages.
   - Each dispatch: `subagent_type: "review:spec-module-analyzer"`, `model: "opus"`, prompt contains module name, role, files, and scout excerpt.
   - Write each output to `<TMP>/spec-extractor-${CLAUDE_SESSION_ID}/modules/<module-name>.md`.

4. **Contract resolution.** Single `Task` dispatch once all module analyzers return:
   - `subagent_type: "review:spec-contract-resolver"`
   - `model: "opus"`
   - `prompt`: scout output + all module summaries + full file list
   - Write to `<TMP>/spec-extractor-${CLAUDE_SESSION_ID}/contracts.md`

5. **Per-module audit.** Dispatch `spec-auditor` per module, capped at **5 concurrent**. Mode=`per-module`. Write each to `<TMP>/spec-extractor-${CLAUDE_SESSION_ID}/audit/<module-name>.md`.

6. **Global audit.** Single `spec-auditor` dispatch, mode=`global`, with scout + modules + contracts. Write to `<TMP>/spec-extractor-${CLAUDE_SESSION_ID}/audit-global.md`.

7. **Synthesis.** Single `spec-synthesizer` dispatch:
   - `subagent_type: "review:spec-synthesizer"`
   - `model: "sonnet"`
   - `prompt`: destination path, tier, bundle summary, and absolute paths to all upstream output files
   - Synthesizer writes the final directory.

8. **Report.** Print output directory path + consolidated severity totals.

#### Large Tier

Steps 1–4 identical to Medium tier. Then:

5. **Module review (optional).** Present the scout's nominated critical modules to the user. `AskUserQuestion`:
   - **Proceed with scout's selection** *(Recommended)*
   - **Add modules** — user specifies additional modules for deep analysis
   - **Remove modules** — user trims the list
   - **Skip deep dives** — proceed Medium-style

6. **Deep analysis.** For each flagged critical module, dispatch `spec-analyzer`, capped at **3 concurrent**. Write each to `<TMP>/spec-extractor-${CLAUDE_SESSION_ID}/deep/<module-name>.md`.

7. **Per-module audit** — as Medium step 5, but include per-module deep spec as audit input when available.

8. **Global audit** — as Medium step 6.

9. **Synthesis** — as Medium step 7, with `deep/` paths included in the synthesizer's input list.

10. **Report** — as Medium step 8.

### Phase 4: Error Handling

- **Missing file path** — abort before Phase 1 Step 2 completes. Name the failing path.
- **Empty resolved bundle** — refuse with a clear message and stop.
- **Scout failure** — abort pipeline, report failure. No partial files written.
- **Module analyzer failure on one module** — skip that module; log it; continue. Synthesizer notes it under "Missing Coverage" in `audit.md`.
- **Contract resolver failure** — synthesize without `contracts.md`; note in audit.
- **Deep analyzer failure on one module** — skip that module's deep spec; note in audit; continue.
- **Synthesizer failure** — save raw upstream outputs to `<dest>/spec/raw/` for debugging. Report failure.
- **Auditor failure (per-module)** — continue; global audit still runs.
- **Auditor failure (global)** — write spec without consolidated audit.md; note the gap in `README.md`.

## Parallelism Caps

When dispatching N parallel Task subagents where N exceeds the cap, send them in batches of `cap` in successive messages. Caps:

- `spec-module-analyzer`: 5
- `spec-analyzer` (deep): 3
- `spec-auditor`: 5

The caps balance throughput against context and rate-limit pressure. Do not exceed without user direction.

## Output Layout

### Small Tier
```
<dest>/spec.md
```

### Medium / Large Tier
```
<dest>/spec/
├── README.md
├── architecture.md
├── modules.md
├── contracts.md
├── audit.md
└── modules/
    └── <module>.md    (only flagged critical modules in Large tier)
```

## Quality Constraints (Non-negotiable)

1. **Domain-neutral prompts.** No library, framework, or product names in any agent body or in the final output structure.
2. **Evidence-first.** Every claim in every output cites `file:line` or `file:start-end`.
3. **Literal payloads.** Event payloads, state assignments, and branch behaviors are transcribed as constructed in source, not paraphrased.
4. **No placeholders.** Every section in every output file is complete or explicitly marked N/A with reason.
5. **Finish dropped.** Markup, CSS, bundler config, exact private naming, stack-specific primitives — excluded from the spec.
6. **Observable-behavior framing.** Describe what gets emitted, routed, dropped — not syntactic shape.

## Rules

- **Confirm the bundle before dispatching agents.** Bundle size drives budget.
- **Tier auto-select, with user override via Narrow/Edit.**
- **Parallelism capped at agent-specific limits.** Batched dispatch when counts exceed caps.
- **Temp files under `<TMP>/spec-extractor-${CLAUDE_SESSION_ID}/`** — left for OS cleanup.
- **No source modification.** The skill only reads source and writes to the destination.
- **One run per invocation.** Re-running overwrites only if the user accepts.

## Keywords

spec, specification, behavioral spec, reverse engineer, reimplementation, contract extraction, architecture map, module analysis, audit, behavior contract, public API surface
