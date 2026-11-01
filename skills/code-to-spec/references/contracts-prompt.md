# Contracts Prompt

The orchestrator fills the placeholders and sends everything below the line as the worker's
whole brief.

---

You are reconciling per-module specs into the contracts between modules: what crosses a module
boundary, the flows that run end to end, and the obligations that belong to no single module.
First read `{RULES}` in full. It defines evidence, claim states, and the record formats.

Inputs:
- Architecture map: `{ARCH}`
- Module specs: `{MODULE_SPECS}`
- Bundle source files, for checking: `{FILE_LIST}`

Read the architecture map and every module spec in one response. Read source only to check a
claim: an asymmetry, a shared entity, a flow hop. A `not found` needs a search you actually ran,
named beside it.

Write the contracts to `{OUT_CONTRACTS}` and the cross-module cases to `{OUT_ACCEPTANCE}`. If you
cannot write files, return both, separated by a line reading `=== acceptance ===`. Use exactly
this structure, with no preamble:

```markdown
# Contracts

## Flows
One section per end-to-end flow, from an entry point to its final effect: a user action, a
request, a job. Pick the flows that cross two or more modules and that the architecture map's
entry points start. Each flow is a numbered list of hops, `module — what happens — location`,
and ends with the observable result. Mark a nondeterministic step with its partial order.

## Messages and Events
| Name | Kind | Producers | Consumers | Literal payload |
|------|------|-----------|-----------|-----------------|
Kind is `internal`, `outbound` (no consumer in scope), or `inbound` (no producer in scope). Below
the table, list each outbound or inbound entry with the search that found no counterpart, and
whether it reads as an external integration, dead code, or a leak.

## Shared Data
Entities read or written by more than one module: the owner, every other writer and reader, and
the invariant that spans them.

## Shared State
Registries, singletons, caches, and global config used across modules: the declarer and the
consumers.

## External Systems
| System | Kind | Direction | Modules | Location |
|--------|------|-----------|---------|----------|

## Disagreements
Places where two module specs describe the same boundary differently. Cite both specs and the
source, and say which one source supports.

## Obligations
<OB-x records, numbered from 001, for behavior that only holds across modules: flow order,
cross-module invariants, and the producer–consumer agreement on a payload.>

## Open Questions
<Q-x records, or `N/A — <reason>`.>
```

The acceptance file uses the module acceptance format, with `x` as the module name.

Return one line when done: `Wrote contracts: <F> flows, <E> messages (<o> outbound, <i> inbound),
<N> cross-module obligations, <D> disagreements, <Q> open questions.`
