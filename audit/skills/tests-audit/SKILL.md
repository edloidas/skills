---
name: tests-audit
description: >
  Audit an existing test suite for anti-patterns — tautological mock round-trips, weak
  assertions (toBeDefined / assertNotNull), implementation coupling, flaky timing, snapshot
  rubber-stamping, and tests claiming guarantees they cannot provide — and report a keep /
  tighten / rewrite / delete verdict per test.
when_to_use: >
  When asked to audit or review the quality of a test suite, judge whether existing tests are
  worth keeping, diagnose flaky or brittle tests, or find out why a green suite is not
  catching bugs.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Read Grep Glob Bash(grep:*) Bash(rg:*) Bash(fd:*) Bash(cat:*) Bash(wc:*) Bash(xargs:*) Bash(od:*) Bash(git diff:*) Bash(mktemp:*) Bash(cp:*)
argument-hint: "[files | dir]"
---

# Tests Audit

Find the tests that don't pin behavior and report what to do with each. **This skill reports;
it never edits the repo — not the suite, not the code under test.** After it runs, the working
tree is byte-identical and the history untouched. It does run the suite — order dependence and
flakiness cannot be found any other way — with the mutation pass editing a *disposable copy
outside the worktree* and coverage output going to a temp directory; a runner that cannot be
redirected gets no coverage run.

`allowed-tools` covers the read-only scan and the temp copy. Deliberately outside it: **the
suite command**, which is project-specific, and **applying a mutant**, even to the copy. Those
two are the audit's whole cost, so they stay a decision the host makes each time rather than a
blanket grant.

This skill is invoked automatically — by an orchestrator, or loaded on its own when a request
matches. Assume most runs were never asked for by a person, and that nobody is watching the
suite run. Say what a pass will cost before starting it, and take the capped budget whenever
the run is not one somebody requested.

## Core Principle

**A good test fails if and only if a promised behavior breaks.**

Every bad test violates one direction of that biconditional:

| Direction violated | Failure mode | Typical shapes |
| --- | --- | --- |
| Fails when nothing broke | **False alarm** — erodes trust, blocks refactoring | implementation coupling, over-mocking, flaky timing, order dependence |
| Green when something broke | **False confidence** — coverage without protection | tautologies, weak asserts, snapshot rubber-stamps, self-fulfilling setups, over-claimed guarantees, trivia tests |

A suite that cries wolf gets ignored; a suite that never cries protects nothing. Both cost
maintenance and return nothing — fewer, sharper tests beat either. **Deleting a bad test is a
quality improvement**, not a coverage regression.

Corollary: coverage percentage measures neither direction. 0% on a module is real information
(a gap); high coverage proves nothing. A test whose only justification is a coverage number is
a finding, not a defense — read *which* lines are uncovered instead. Uncovered defensive
branches and exhaustiveness guards are correct; a coverage threshold is only worth raising for
a gap in real behavior.

## The Five-Question Gate

Every test must pass all five. Any "no" is a Tighten, Rewrite, or Delete verdict.

1. **Contract** — which one-sentence promise of the public API does it pin, and does the name
   claim no *more* than the assert delivers? No sentence → it tests implementation detail, a
   mock, or nothing. Name (or the CI job around it) over-claims → a false guarantee, worse
   than no test.
2. **Refactor-proof** — would it survive a behavior-preserving refactor of the internals?
   No → it's wrong by definition, regardless of what it has caught before. Non-negotiable.
3. **Falsifiable** — would it fail for a realistic bug? Flip a `<` to `<=`, break the formula,
   swap an argument. Sharpest form: name the dumbest implementation that still passes — if a
   constant, the identity function, or the test's own Arrange step satisfies the assert, it
   constrains nothing. Second form, for a test that already looks precise: name a *different*
   real branch of the SUT that produces the same assert. If one exists, the test pins the
   outcome but not the rule. **Measure this one where the scope allows it** — the mutation pass
   (`references/audit-procedure.md` §2c) answers it with a red/green matrix instead of a guess,
   and a guessed answer must never be reported in the register of a measured one.
4. **Diagnostic** — does the name plus the failure diff identify the broken rule without a
   debugger?
5. **Deterministic** — same result every run, in any order: no real time, no real network,
   no shared mutable state, no sleeps.

## Test Double Policy

The most-violated rule in real suites, so it gets its own section:

- **Double only unmanaged boundaries**: network, clock, filesystem, randomness, other
  processes/services. Use real collaborators for everything you own — often free, since the
  case under test may short-circuit before it reaches the boundary at all.
- **A double must be able to happen**: it may only throw what the real dependency throws at
  that call site, and return what it can really return. An impossible stub runs a scenario
  production never reaches (1.12).
- **Prefer hand-rolled fakes** (in-memory repo) over interaction mocks — fakes verify state,
  mocks verify your assumptions about choreography.
- **Interaction asserts** (`toHaveBeenCalledWith`, Mockito `verify`) are legitimate only when
  the outgoing call *is* the contract — the amount sent to a payment gateway, the params
  forwarded to an external API. Call counts only when the count is documented behavior
  ("retries exactly once"), never as a change detector.
- **Thin adapter caveat**: when the module under test is a thin layer over a mocked service,
  asserting the response echoes the mock is a tautology. The real contract of an adapter is
  the *translation*: parameter mapping (an outgoing-call assert), response shaping, error
  mapping, authorization gating. Test those; if there's no translation, there's nothing to
  unit-test — cover it in an integration test or not at all.
- **Hard to test without heavy mocking?** That's design feedback about the code under test,
  not a mocking problem — a hidden `new Date()` wants to be a parameter, buried IO wants to be
  injected, a god object wants splitting. Report it as a design finding on the module. Do not
  refactor production code to make a test cleaner; that is outside this skill.

## Workflow

1. **Scope**: explicit argument → exactly that. Otherwise the test files in the working
   tree's changes; otherwise the project's test suite — read whole at 30 test files or fewer,
   and above that sampled to a floor of 20 files or a quarter of the suite, whichever is
   larger, mixing small and large files, pure-logic and mock-heavy, plus any e2e specs.
   Diff-scoped is a first-class mode, not a borrowed one: `review:changes-review` judges
   whether the change is correct, this skill judges whether the tests pin anything. Scope
   bounds the *verdicts*, not the reading — a Delete for duplicate coverage still means
   reading the neighbouring tests the diff never touched.
   End with one line: `Scope: 24 of 96 test files (sampled) · vitest 3, wdio 9`.
2. **Mechanical scan** for grep-able smells (weak asserts, sleeps, `.skip`/`@Disabled`,
   `.only`, loops in test bodies, mock round-trips, catch-only error tests) — commands in
   `references/audit-procedure.md`. End with one line: `Scan: 31 leads across 12 files`.
3. **Dynamic checks**: the baseline run, the shuffled repeat run, and the coverage run.
   Isolation, flakiness, and runtime don't grep — a green shuffled run is evidence no static
   audit can produce, and a red one is a High finding that names itself.
3b. **Mutation pass** — break one rule at a time on a disposable copy and record which tests
   go red. Its feasibility conditions, operator priority, and how to read the matrix are in
   `references/audit-procedure.md` §2c. Its *size* is set by how this skill was invoked, not
   by what it can afford: a person asking for a measured audit gets the full pass; auto-loaded
   or called by another skill, it is capped hard or skipped.

   **Every one of the four runs that did not happen is named in the report header with its
   reason** — skipped by budget, aborted on a wrong flag, unsupported by the runner. This
   applies to all four equally: a shuffle that never ran is not a green shuffle, an unrun
   coverage pass is not full coverage, and verdicts without a matrix are read, not measured,
   and must never be written as if they were. End with one line naming what ran:
   `Dynamic: baseline green 1.8s · shuffle ×5 green · coverage skipped (runner path not redirectable) · 12 mutants, 4 survived`.
4. **Per-test pass**: run each test through the Five-Question Gate and the catalog in
   `references/anti-patterns.md`. Assign a verdict:

   | Verdict | When |
   | --- | --- |
   | **Keep** | Passes the gate |
   | **Tighten** | Right contract, weak execution — imprecise asserts, bad name, sleep |
   | **Rewrite** | Real contract worth pinning, but the test pins implementation or a mock |
   | **Delete** | No contract sentence, duplicate coverage, trivia, rotting disabled test |

5. **Report** using `references/audit-procedure.md` §5, which is a filled-in example of the
   deliverable rather than a blank template — match its shape, its header lines and its
   section order. Name what the suite does *well* alongside the defects; an unnamed good
   pattern is one refactor from deletion. Close with an overall verdict and an ordered fix
   path.

The report is the deliverable. For whoever applies it, `references/audit-procedure.md` §6
gives the fix-pass order and verification steps, and `references/writing-tests.md` gives the
contract-first procedure for rewriting a flagged test. Reference both in the fix path so the
report is actionable without this skill. Then stop: do not apply the report, do not offer to
apply it, and do not start a second audit pass.

## Quick Reference

| Smell | Verdict → fix |
| --- | --- |
| Mock returns X, assert X comes back | Delete, or Rewrite against the translation the module performs |
| Stub throws/returns what the real dependency can't at that call site | Rewrite against the dependency's actual contract — read its source if the signature won't say |
| Assert reads the result through a friendlier idiom than the consumer uses | Rewrite: assert through the consumer's idiom, or cross the real boundary |
| Test named for success proves it by sabotaging a *later* step | Rewrite to assert the named rule's own outcome |
| One status/variant shared by N branches, asserted alone | Tighten: assert the discriminator, or admit the branch isn't pinned |
| Name/CI claims a property (complexity, perf, security) the assert can't measure | Rewrite to what it does pin + rename, or Delete the claim |
| Arrange — or a grep of the SUT's own source — establishes what the Assert checks | Rewrite around the real producer: run it, inspect the artifact |
| All assertions live inside `catch` | Tighten: `toThrow` / a helper that fails when nothing throws |
| Property — or a size/length/count assert — a constant, empty or identity would satisfy | Tighten to the exact value, two-sided, or metamorphic; else Delete |
| N feature tests all re-proving one mechanism | Not a finding — suite-level observation only |
| Expected value computed with SUT's formula | Tighten: replace with hand-computed constant |
| `toBeDefined` / `assertNotNull` / `not.toThrow` as the only assert | Tighten: assert the precise value or shape |
| Asserting internal call order/counts (undocumented) | Rewrite against observable output, or Delete |
| Mocking code you own (incl. whole UI libraries) | Rewrite with real collaborators; mock only the boundary |
| 300-line snapshot nobody reads | Rewrite as explicit asserts on the parts that matter |
| `sleep` / `Thread.sleep` / real clock | Tighten: fake timers, injected clock, condition-based waits |
| `if`/`for`/`try-catch` in a test body; conditional mocks | Tighten: table test, or split into one test per branch |
| Loop over cases with one assert (which case failed?) | Tighten: `it.each` / `@ParameterizedTest` |
| Giant `beforeEach` / deep base-class setup (mystery guest) | Tighten: builders with defaults; DAMP over DRY |
| `it('fixes JIRA-4521')` | Tighten: rename to the rule the bug violated |
| Test depends on a previous test's state | Rewrite: each test arranges its own world |
| e2e: `waitFor...` with no assertion after it | Tighten: assert the outcome explicitly |
| Fixture's bytes don't match its label — a plain space named no-break, an escape TS ate | Tighten: fix the literal, then confirm the case still goes red for its rule |
| Red only when two independent mechanisms break at once, and sole cover for neither | Delete — no single realistic regression reddens it |
| Test asserts an acknowledged-wrong value ("should be 4, left as is") | Report separately: that's a bug, not a test defect |
| `.skip` / `@Disabled` / commented-out for months | Delete (git remembers) — Rewrite if its intent names an uncovered promise |
| Getters, framework wiring, generated code under test | Delete — cost > 0, information = 0 |

Full catalog with mechanisms, detection, and worked fixes: `references/anti-patterns.md`.

## Common Mistakes

- **Verdicting Delete on a test whose intent was real.** Check question 1 of the gate first —
  a badly-written test for a real rule earns Rewrite, not Delete.
- **Reading repetition as duplication.** Copy-pasted arrange blocks are a real Low finding
  (3.4), but test code optimizes for the reader of a failure, not for zero duplication. Never
  recommend DRY-ing tests into a shared-helper labyrinth as the fix.
- **Auditing e2e suites with unit-test rules.** e2e tests legitimately chain steps and share a
  browser; hold them to determinism, explicit asserts, and independence — not to one-Act purity.
- **Writing an inference in the register of a measurement.** A claim about runtime behavior —
  dead code, which branch fires, how many times something is called, what an output contains —
  is either observed, and the report says how and shows the command, or it is a hypothesis,
  labeled as one and carrying the command that would settle it. Reading the source never
  licenses "verified". This is the failure mode a strong audit is most likely to have, because
  the measured findings around it lend it their credibility.
- **Reporting defects without calibration.** "12 findings" reads the same for an excellent
  suite as for a rotten one. Name the strengths, rank the findings, and don't lead with
  redundant deterministic tests — they cost little, and a pass to lower a test count costs
  more review than it returns. Count measures effort; ask instead what each test is the only
  one to catch.

## References

- `references/audit-procedure.md` — scan commands, dynamic checks, the mutation pass and when
  it is worth running, verdict rubric, report template, and the fix-pass order for whoever
  applies the report
- `references/anti-patterns.md` — full catalog: symptom, mechanism, detection, fix
- `references/writing-tests.md` — how to rewrite a flagged test: contract listing, naming, case
  selection, doubles, worked example, per-stack idioms (Vitest/TS, R3F, JUnit/Mockito,
  WebdriverIO)
