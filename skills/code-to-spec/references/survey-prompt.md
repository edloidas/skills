# Survey Prompt

The orchestrator fills the placeholders and sends everything below the line as the worker's
whole brief.

---

You are mapping a source bundle so that later workers can specify it module by module, for a
rewrite in another stack. Map it, but do not specify behavior. Sample the bundle rather than
reading every file. Open every manifest, README, entry point, schema, and migration file, then the
10 files with the most inbound imports, or every file when the bundle has 15 or fewer. Use search
to count. Treat any README or architecture doc
as a hint and check its claims against source.

First read `{RULES}` in full. It defines evidence, claim states, and the record formats. This file
writes no obligations, but its citation and literal rules apply.

Inputs:
- Bundle files: `{FILE_LIST}`
- Test files in scope: `{TEST_LIST}`
- Counts: {FILE_COUNT} files, about {LOC} lines, tier {TIER}

Group files into modules. A module is a set of files with one purpose you can state in one
sentence: a workspace package, a feature directory, or files that share imports and a name
prefix. Most modules hold 1–20 files, and every module holds at least one bundle source file.
Map each test file to the module whose source it exercises. A test that exercises no bundle
source goes under Not Covered, never into a module of its own.

Nominate a module for `deep` depth when any of these holds: it sits on the public boundary, it
holds an entry point or bootstrap, many modules import it, it owns persistent data or a state
machine, or it coordinates async work. Every other module gets `summary` depth. Nominate at least
one module, at most 5 on Medium and 15 on Large, and never more than half the modules, rounded
up. When more qualify,
keep the ones a rewrite would most likely get wrong: state machines, security checks, and
cross-module coordination.

Write the result to `{OUT}`. If you cannot write files, return the content instead. Use exactly
this structure, with no preamble:

```markdown
# Architecture

## Purpose
<One paragraph: what the application does and for whom, with citations.>

## Runtime Model
<Server, client, CLI, library, worker, or a mix. Process and threading model, sync or async,
scheduled work. Cited.>

## Semantic Dependencies
<Only the technologies whose semantics leak into behavior, per the rules file. One line each:
the behavior, then `source relies on <X>`, then a citation. `N/A — <reason>` if none.>

## Entry Points
| Entry | Kind | Location | What it starts |
|-------|------|----------|----------------|

## Glossary
| Term | Meaning in this system | Where defined |
|------|------------------------|---------------|

## Module Inventory
| Module | Path | Files | LOC | Tests | Depth | Role |
|--------|------|-------|-----|-------|-------|------|

## Module Files
### <module>
- Source: `<path>`, `<path>`
- Tests: `<path>` or none in scope

## Deep Nominations
### <module>
- Why: <which criterion, with citations>
- Risk: <state, async, or cross-cutting signals>

## Cross-Module Signals
<Event channels, buses, shared stores or registries, shared entities, global config, external
systems. Each with a citation.>

## Not Covered
<Generated, vendored, or unreadable files you found and left out, and why.>
```

Module names are lowercase-hyphenated and unique. Later workers use them in IDs and file names.
Return one line when done: `Wrote {OUT}: <N> modules, <M> deep, <T> test files mapped.`
