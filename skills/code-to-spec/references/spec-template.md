# Spec Output

The layout of what code-to-spec writes, and the two files the orchestrator writes itself: the
spec `README.md`, and the Small tier's `spec.md`. Every other file is copied from a worker's
output, whose structure its prompt owns.

## Medium and Large: `<dest>/spec/`

```
spec/
├── README.md              # orchestrator: index, coverage, how to use
├── architecture.md        # survey worker
├── contracts.md           # contracts worker
├── audit.md               # every audit file concatenated, global first
├── modules/<module>.md    # one per module
└── acceptance/
    ├── <module>.md        # one per module
    └── x.md               # cross-module cases
```

A reimplementer porting one module loads `README.md`, `architecture.md`, `modules/<m>.md`, and
`acceptance/<m>.md`, and opens `contracts.md` only for the module's boundary.

### Building the indexes

Build the obligation and question tables from the heading lines the rules file fixes. Do not
read the files whole to build them:

```bash
grep -H '^### OB-' modules/*.md contracts.md
grep -H '^### Q-' modules/*.md contracts.md
grep -c '^### AC-' acceptance/*.md
```

Each `### OB-auth-003 · rule · observed` line becomes one index row. The obligation text is not
copied. The row links to the file.

### README.md

```markdown
# Behavioral Specification: <bundle name>

Generated <ISO 8601 date> by code-to-spec from <N> files (about <LOC> lines), <tier> tier.

## How to use this spec

1. Read `architecture.md` for purpose, runtime model, glossary, and module map.
2. Port module by module. For each, `modules/<m>.md` is the behavior and `acceptance/<m>.md`
   is the test list. A module is done when every case passes in the new stack.
3. `contracts.md` holds the flows and agreements between modules. `acceptance/x.md` tests them.
4. Every open question below needs a decision before its module is ported.
5. `audit.md` lists where this spec is known to be wrong or thin.

`observed` claims were read in source or asserted by a test. `inferred` claims carry their
basis. `unknown` claims point at an open question.

## Coverage

| Module | Depth | Files | Obligations | Cases | Open questions | Audit |
|--------|-------|-------|-------------|-------|----------------|-------|

<Then one line per gap: a module that failed, a stage skipped, files listed but not read.
`No gaps.` if there are none. Then `check-spec: <P> mechanical problems, reported in audit.md.`>

## Obligations

| ID | Layer | State | File |
|----|-------|-------|------|

## Open Questions

| ID | Severity | File |
|----|----------|------|
```

## Small: `<dest>/spec.md`

One file. Its parts keep their own heading levels, so `### OB-` and `### AC-` lines stay
greppable:

```markdown
# Behavioral Specification: <bundle name>

Generated <ISO 8601 date> by code-to-spec from <N> files (about <LOC> lines), Small tier.
Port it by making every acceptance case pass in the new stack. Decide every open question first.

<module spec, sections 1–13, without its `# Module:` line>

## Acceptance Cases

<acceptance file without its `# Acceptance:` line; its `## OB-...` groups and `### AC-...` records unchanged>

## Audit

<the audit output, or `Not run: <reason>`>
```

## Worked index rows

Three index rows built from a real-shaped run, for reference:

```markdown
| ID | Layer | State | File |
|----|-------|-------|------|
| OB-auth-003 | rule | observed | [modules/auth.md](modules/auth.md) |
| OB-billing-011 | integration | inferred | [modules/billing.md](modules/billing.md) |
| OB-x-002 | timing | unknown | [contracts.md](contracts.md) |
```
