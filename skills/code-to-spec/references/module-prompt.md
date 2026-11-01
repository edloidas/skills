# Module Prompt

The orchestrator fills the placeholders and sends everything below the line as the worker's
whole brief. In the Small tier the orchestrator follows it inline, with `{DEPTH}` = `deep` and
the module named after the bundle.

---

You are specifying one module so that someone who never reads its source can rebuild the same
observable behavior in another stack. First read `{RULES}` in full. It defines evidence, claim
states, scoping absence, and the obligation, acceptance-case, and open-question formats used
below.

Inputs:
- Module: `{MODULE}`. Role: {ROLE}
- Depth: `{DEPTH}`
- Source files: `{FILES}`
- Test files: `{TESTS}`
- Architecture map, for orientation only (do not repeat it): `{ARCH}`

Open every source and test file in the lists in one response, before writing anything. Then open
every file the source loads by path at runtime: templates, prompt or message files, schemas,
default config. Their contents are behavior, so their defaults and literals go in the spec. A
loaded file outside the repository, such as a path under the user's home, becomes an open
question. Search other modules only to resolve what a call into them returns. Name those modules
and leave their internals out.

**Depth.** On `deep`, fill every section, and give each obligation every case kind its behavior
has. On `summary`, fill sections 1, 2, 3, 6, 10, 11, and 13, write obligations for interface,
data, and error behavior only, give each one at least a positive and a negative case, and write
`Not traced at summary depth.` in the other sections. That sentence is a recorded gap, not N/A.

Write the module spec to `{OUT_MODULE}` and its cases to `{OUT_ACCEPTANCE}`. If you cannot write
files, return both, separated by a line reading `=== acceptance ===`. Use exactly this structure,
with no preamble:

```markdown
# Module: {MODULE}

## 1. Scope
- Depth: {DEPTH}
- Read: <every file opened>
- Not read: <files listed but not opened, and why, or none>

## 2. Interface
Everything a caller, user, or peer can reach: routes, commands, exported functions and types,
screens and user flows, messages sent and received. For each entry: its shape (parameters and
fields with types, required or optional, defaults), its result, and its citation. Payloads go in
fenced blocks. For screens, give the fields, validations, and transitions, and drop the layout.

## 3. Data
Entities and value types this module owns. Fields with types, constraints, and defaults. How they
are stored: tables, keys, indexes, files, caches. Migrations in scope, in order. Invariants that
every write preserves.

## 4. State and Lifecycle
State machines as a table (state, trigger, guard, next state, effect). Init order, then teardown
order. Every subscription, timer, or handle beside the call that releases it, or `MISSING`.

## 5. Rules
Decision and transform rules as a numbered list. Every flag, enum, or variant branch in the
public API is stated by its observable result. Where an entry point runs several checks, list
them in the order they run, because the first one that fails decides the response. Say which
checks spend or change state (a consumed code, a counter, a lock) before a later check can still
refuse. A reader must never need line numbers to work out the order.

## 6. Errors
| Condition | Observable signal | Location |
|-----------|-------------------|----------|
The signal is literal: status and body, exit code and message, thrown type and message, emitted
error event. Silent swallows are rows too.

## 7. Configuration
| Key | Source | Default | Effect | Location |
|-----|--------|---------|--------|----------|
Env vars, config files, flags, and feature toggles this module reads.

## 8. Integrations
Outbound calls to systems outside the bundle: protocol, request and response shape, timeout,
retry, and behavior on failure. External programs the module runs: their argv, as literals. Where
the module passes another program's output through, say that the port must call the same program
or reproduce its format exactly.

Platform guarantees: what the module relies on from the runtime around it, such as a shared or
clustered store (TTL, eviction, atomic update), a lock, a scheduler, a script engine, or the
container that turns a thrown error into a response. State each guarantee the code depends on.
Where that guarantee lives outside the bundle, it is an open question. A port has to choose a
replacement that keeps the guarantee, so the spec has to name it.

## 9. Concurrency and Timing
Ordering guarantees, partial orders, locks, idempotency (a second init, a repeated request, a
re-entered state), timeouts, schedules, and clock or timezone dependence.

## 10. Obligations
<OB records, numbered from 001, in the format the rules file gives.>

## 11. Open Questions
<Q records, or `N/A — nothing in this module is undecidable from scope.`>

## 12. Suspicious Conditions
| Location | Excerpt | Why suspect | Observable consequence |
|----------|---------|-------------|------------------------|
Conditions that look inverted, unreachable, or contradictory. The rewrite has to choose to
reproduce or fix each one, so state the current behavior exactly.

## 13. Not Carried Over
Finish dropped from this module (named by kind, not listed exhaustively), and deliberate
non-goals visible in source, with citations.
```

The acceptance file holds only AC records, grouped under one `## OB-...` heading per obligation,
in obligation order:

```markdown
# Acceptance: {MODULE}

## OB-{MODULE}-001
<AC records>
```

Every case kind an obligation lists has at least one case. When a test asserts the behavior, use
its literal inputs and outputs. Otherwise derive the case from code and mark it `Source: code`.

Return one line when done: `Wrote {MODULE}: <N> obligations (<o> observed, <i> inferred,
<u> unknown), <C> cases (<t> from tests), <Q> open questions.`
