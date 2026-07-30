# Spec Output Template

Unified schema for all spec-extractor output files. Use this as the authoritative reference when reviewing extracted specs by hand, when writing calibration targets, or when extending the pipeline in a future version.

## Small Tier Output

Single file: `<dest>/spec.md`.

```markdown
# Behavioral Specification

**Bundle:** <name>
**Generated:** <ISO 8601>
**Files:** N
**Tier:** Small

<11-section deep spec from spec-analyzer>

---

## Audit Findings

<audit report from spec-auditor>
```

## Medium / Large Tier Output

Directory: `<dest>/spec/`.

```
<dest>/spec/
├── README.md
├── architecture.md
├── modules.md
├── contracts.md
├── audit.md
└── modules/
    └── <module-name>.md     (Large tier only, per flagged critical module)
```

### README.md

Bundle overview and map of the spec. Contains:
- Bundle name, generated timestamp, tier, file count, LOC, detected languages.
- "How to read this spec" — brief map of the files.
- List of flagged modules with deep specs (linked).
- Known gaps from the audit.

### architecture.md

From `spec-scout`. Contains:
- **Purpose** — one paragraph on what this application or library does.
- **Runtime Model** — client/server/hybrid/CLI/library, sync/async patterns, threading/process model.
- **Tech-Stack Signals** — detected ecosystems with evidence `file:line`, no product evangelism.
- **Entry Points** — table of entry files with roles.
- **Top-Level Structure** — brief description of workspace/directory relationships.
- **Module Inventory** — table of all modules.
- **Critical Modules** — which modules were flagged and why, with links to deep specs.
- **Cross-Module Signals** — named event channels, buses, registries.

### modules.md

Module catalog + per-module medium-depth summaries. Contains:
- **Catalog** — table: module, role, primary files, has-deep-spec.
- **Per-module sections** — each contains:
  - Purpose (one paragraph).
  - Public Surface — Exports table + Public Members table.
  - State Bindings — target / source / read-by / written-by.
  - Lifecycle — Construction / Initialization / Listener Registration / Teardown.
  - Events and Messages — Fired table + Listened table.
  - Flag and Branch Audit — flag parameters + switch/case decisions.
  - Error Surfaces.
  - Lifecycle Contract for Consumers.
  - Non-goals.
  - Cross-Module References.
  - Suspicious-Condition Flags.

### contracts.md

From `spec-contract-resolver`. Contains:
- **Event / Message Contracts** — table with classification (internal/outbound/inbound/bidirectional).
- **Asymmetries** — fired-without-listener, listened-without-fire-site.
- **Public Export Map** — in-bundle consumers + external-only / unused.
- **Shared Registries / Singletons / Global State**.
- **External Integration Points** — network / filesystem / database / message-channel / scheduled-job.
- **Contract Invariants** — cross-module invariants.
- **Observations for Synthesizer** — subsystems, circular deps, drift.

### audit.md

Consolidated verification findings. Contains:
- Header: reviewed-module count + totals (Critical / Warning / Note).
- **Verdict** — would a reimplementer succeed from this spec alone?
- **Critical** — findings by severity.
- **Warning**.
- **Note**.
- **What the Spec Got Right** — calibrating strengths.
- **Missing Coverage** — modules where analysis failed or was skipped.

### modules/<name>.md

Deep 11-section spec from `spec-analyzer`. See below.

## Deep 11-Section Spec Schema

Used by `spec-analyzer` for Small-tier output and Large-tier deep dives.

1. **Contract Surface** — Imports and Exports + Public Members.
2. **Params / Options Unboxing** — every params/payload object's fields with origin and use sites.
3. **State Bindings** — every this.X / module-level let / static with read-by and written-by sites.
4. **Lifecycle Segments** — Construction, Public Init, Listener Registration, Teardown.
5. **Boolean / Enum / Discriminated-Union Flag Audit** — every flag parameter with observable branches.
6. **Switch / Case / Empty-Handler Audit** — every dispatch site with per-case observable behavior.
7. **Bidirectional Event / Message Tracing** — fire sites + listen sites + literal payloads + asymmetries.
8. **Register / Unregister Symmetry Audit** — subscription / teardown pairs; missing teardowns flagged.
9. **Suspicious-Condition Flags** — inverted, unreachable, contradictory conditions.
10. **Domain Spec — Primary Unit** — Purpose, Shape, Rules, Example Table, Error Surfaces, Idempotency, Lifecycle, Non-goals.
11. **Secondary Units — Brief Specs** — per-unit Purpose, Shape, Rules, Error Surfaces, Lifecycle.

## Hard Rules Across All Outputs

1. Every factual claim cites `file:line` or `file:start-end`.
2. Payloads are transcribed literally, never paraphrased.
3. No placeholders — `[table of N items]`, `[see above]`, `...and others` are all forbidden.
4. No product or library identifiers in output structure. Library usage is stated as a signal with evidence, not as an identifier.
5. Describe observable behavior, not syntactic shape.
6. TypeScript contract attributes (`type` on exports/imports) are preserved.
7. Tables may be long; prose across Domain Spec + Secondary Units is capped at ~2000 words combined.
