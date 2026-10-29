---
name: code-to-spec
description: >
  Extract a behavioral specification from a source-code bundle — a handful of files up to a
  whole 500+ file application. Produces reproducible, stack-neutral specs another engineer or
  LLM could use to rebuild the same observable behavior without reading the original source.
when_to_use: >
  When reverse-engineering a library or module's contract, understanding an application in
  detail, or preparing input for a reimplementation. Also on "extract a spec", "what is this
  module's contract", "map the architecture", or "document the public API surface".
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

**Mutation class:** local writes only — it reads source, writes the spec under the destination you pick and scratch files under `<TMP>`, and never modifies the code it reads.

The skill orchestrates a pipeline of bundled plugin agents: a scout that maps structure, module analyzers that produce medium-depth summaries, a contract resolver for cross-module events and exports, deep analyzers for flagged critical modules, an auditor that verifies the spec against source, and a synthesizer that assembles the final output directory.

## Invocation Modes

Three forms, detected at invocation time:

| Form | Example | Skill interpretation |
|------|---------|----------------------|
| **No args** | `/code-to-spec` | Walk the active repo from the working directory |
| **Paths** | `/code-to-spec src/foo src/bar.ts modules/lib/src` | Explicit files / folders; folders expanded |
| **Guide** | `/code-to-spec auth flow`, `/code-to-spec the message bus` | Natural-language scope — skill searches with Grep/Glob and proposes a file list |

Phase 1 Step 1 owns the detection rule that picks between them.

## Tiers

The skill auto-selects a tier based on resolved bundle size:

| Tier | Range | Pipeline |
|------|-------|----------|
| **Small** | ≤ 6 files or ≤ 1500 LOC | `spec-analyzer` → `spec-auditor` → single-file output |
| **Medium** | 7–30 files | `spec-scout` → parallel `spec-module-analyzer` → `spec-contract-resolver` → `spec-synthesizer` → `spec-auditor` |
| **Large** | 31+ files, up to 500+ | Medium pipeline + parallel `spec-analyzer` deep dives on flagged critical modules |

## Dependencies

The six agents named in **Tiers** ship in `review/agents/`. `references/spec-template.md` is the output
schema; `references/severity-rubric.md` defines Critical / Warning / Note, mirroring the auditor.

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

Use it as `<TMP>`. Every stage below is one `Task` dispatch of the bundled agent it names, as
`subagent_type: "review:<agent>"`, on `model: "opus"` except the synthesizer on `"sonnet"`. The
prompt carries the inputs the step names plus the six **Quality Constraints**. Every agent but the
synthesizer returns its output as text; write each return with `Write` to the named file under
`<RUN>` = `<TMP>/code-to-spec-${CLAUDE_SESSION_ID}/`. Leave `<RUN>` in place when the
run ends — the OS reclaims it, and a failed synthesis is unrecoverable without it.

#### Small Tier

Skip scout, module analyzers, contract resolver, synthesizer.

1. **`spec-analyzer`** — file list and role hints → `<RUN>/analyzer.md`.
2. **`spec-auditor`**, mode `per-module` — source file list and the analyzer output's path →
   `<RUN>/auditor.md`.
3. **Assemble** `<dest>/spec.md` with `Write`, per **Small Tier Output** in
   `references/spec-template.md`: the header, the analyzer output verbatim, then the auditor output
   verbatim under `## Audit Findings`.
4. **Report**, per **Run Report** below.

#### Medium Tier

1. **`spec-scout`** — bundle file list, file count, LOC, tier → `<RUN>/scout.md`.
2. **Parse modules** from the scout's Module Inventory table: name, path, file subset. Print
   `Scout: 7 modules, 2 nominated critical.`
3. **`spec-module-analyzer`** per module, capped at **5 concurrent** — module name, role, files, scout
   excerpt → `<RUN>/modules/<module-name>.md`. Print `Modules: 7 analyzed, 1 failed.`
4. **`spec-contract-resolver`**, once every module analyzer has returned — scout output, all module
   summaries, full file list → `<RUN>/contracts.md`.
5. **`spec-auditor`** per module, mode `per-module`, capped at **5 concurrent** →
   `<RUN>/audit/<module-name>.md`.
6. **`spec-auditor`**, mode `global`, with scout, modules and contracts → `<RUN>/audit-global.md`.
7. **`spec-synthesizer`** — destination path, tier, bundle summary, the absolute path to
   `references/spec-template.md` as the output schema, and absolute paths to every upstream output.
   It writes the final directory.
8. **Report**, per **Run Report** below.

#### Large Tier

Steps 1–4 identical to Medium tier. Then:

5. **Module review (optional).** Present the scout's nominated critical modules to the user. `AskUserQuestion`:
   - **Proceed with scout's selection** *(Recommended)*
   - **Add modules** — user specifies additional modules for deep analysis
   - **Remove modules** — user trims the list
   - **Skip deep dives** — proceed Medium-style

6. **`spec-analyzer`** per flagged critical module, capped at **3 concurrent** →
   `<RUN>/deep/<module-name>.md`.
7. **Per-module audit** — as Medium step 5, with the module's deep spec as audit input when available.
8. **Global audit** — as Medium step 6.
9. **Synthesis** — as Medium step 7, with the `deep/` paths in the synthesizer's input list.
10. **Report** — as Medium step 8.

### Run Report

Four lines, then the turn ends:

```
Spec written to docs/spec/ — Medium tier, 24 files, 7 modules, 2 deep dives.
Audit: 1 Critical / 6 Warning / 9 Note.
Missing coverage: modules/legacy-adapter — analyzer failed, noted in audit.md.
Skipped: contract resolution (resolver returned no output).
```

Drop the last two lines when nothing failed and nothing was skipped. Name every stage that did not run and why — a pipeline reported only by its severity totals reads as complete when half of it was skipped.

Then stop. Do not act on the audit findings, do not edit the source the spec describes, and do not re-run the pipeline to improve a severity count.

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

Each dispatch step above names its own cap. Where the count exceeds it, send the agents in batches of that cap in successive messages, and never raise a cap without user direction — the caps balance throughput against context and rate-limit pressure.

## Output Layout

`references/spec-template.md` owns it: `<dest>/spec.md` for Small, the `<dest>/spec/` directory for
Medium and Large.

## Quality Constraints

Restate these six in every agent prompt you dispatch. They are also the rubric the auditor scores against, so an agent that never received them fails its own audit:

1. **Domain-neutral prompts.** No library, framework, or product names in any agent body or in the final output structure.
2. **Evidence-first.** Every claim in every output cites `file:line` or `file:start-end`.
3. **Literal payloads.** Event payloads, state assignments, and branch behaviors are transcribed in a fenced block exactly as constructed in source, never paraphrased. Where a payload is elided, say how many fields were cut.
4. **No placeholders.** Every section in every output file is complete or explicitly marked N/A with reason. `[table of N items]`, `[see above]` and `...and others` are all forbidden.
5. **Finish dropped.** Markup, CSS, bundler config, exact private naming, stack-specific primitives — excluded from the spec.
6. **Observable-behavior framing.** Describe what gets emitted, routed, dropped — not syntactic shape.
