---
name: test-quality
description: >
  Write behavior-pinning tests and audit existing test suites for anti-patterns — tautological
  mock round-trips, weak assertions (toBeDefined / assertNotNull), implementation coupling,
  flaky timing, snapshot rubber-stamping — then tighten, rewrite, or delete the offenders.
  Use when asked to write tests for new or existing code, review or audit test quality,
  improve a test suite, fix flaky or brittle tests, or decide whether tests should be kept,
  fixed, or removed.
license: MIT
compatibility: Claude Code, Codex
argument-hint: "[files | dir] [write | audit | improve]"
---

# Test Quality

Write tests that pin behavior, find tests that don't, and fix or delete them.

## Core Principle

**A good test fails if and only if a promised behavior breaks.**

Every bad test violates one direction of that biconditional:

| Direction violated | Failure mode | Typical shapes |
| --- | --- | --- |
| Fails when nothing broke | **False alarm** — erodes trust, blocks refactoring | implementation coupling, over-mocking, flaky timing, order dependence |
| Green when something broke | **False confidence** — coverage without protection | tautologies, weak asserts, snapshot rubber-stamps, trivia tests |

A suite that cries wolf gets ignored; a suite that never cries protects nothing. Both cost
maintenance and return nothing — fewer, sharper tests beat either. **Deleting a bad test is a
quality improvement**, not a coverage regression.

Corollary: coverage percentage measures neither direction. 0% on a module is real information
(a gap); high coverage proves nothing. Never write a test whose only justification is a
coverage number.

## The Five-Question Gate

Every test — new or existing — must pass all five. Any "no" → fix or delete.

1. **Contract** — which one-sentence promise of the public API does it pin? Can't name the
   sentence → it tests implementation detail, a mock, or nothing.
2. **Refactor-proof** — would it survive a behavior-preserving refactor of the internals?
   No → it's wrong by definition, regardless of what it has caught before. Non-negotiable.
3. **Falsifiable** — would it fail for a realistic bug? Mentally flip a `<` to `<=`, break the
   formula, swap an argument — does it go red?
4. **Diagnostic** — does the name plus the failure diff identify the broken rule without a
   debugger?
5. **Deterministic** — same result every run, in any order: no real time, no real network,
   no shared mutable state, no sleeps.

## Test Double Policy

The most-violated rule in real suites, so it gets its own section:

- **Double only unmanaged boundaries**: network, clock, filesystem, randomness, other
  processes/services. Use real collaborators for everything you own.
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
- **Hard to test without heavy mocking?** That's design feedback, not a mocking problem:
  a hidden `new Date()` wants to be a parameter, buried IO wants to be injected, a god object
  wants splitting. Extract the pure logic and test it with zero mocks; leave a thin shell.

## Modes

Infer the mode from the request; explicit arguments override. "Write tests for X" → Write.
"Are these tests any good?" / "review the tests" → Audit (report only — don't edit).
"Fix / clean up the tests" or an approved audit → Improve.

### Write

1. **List the contract first.** Enumerate the module's promises as one-sentence rules, from its
   public surface, types, docs, and callers. Each sentence becomes a test name. Can't write the
   sentences → you don't understand the module yet; read more code, don't write tests.
2. **Pick cases by equivalence class, not by code path.** One test per behavior class, plus the
   boundaries between classes (`<` vs `<=`, empty input, rounding edge, error path). Same rule
   with several data points → one table test (`it.each` / `@ParameterizedTest`), never a loop.
3. **Shape**: Arrange–Act–Assert, exactly one Act. Builders with valid defaults keep Arrange to
   a line. Expected values are hand-computed constants — never re-derived with the SUT's own
   formula. No ifs, loops, or try/catch in test bodies.
4. **Doubles** per the policy above. Fake timers instead of sleeps; clock as an argument where
   the design allows.
5. **Verify**: run the suite. Then mutation spot-check the riskiest rule — break the SUT on
   purpose (flip a boundary, change a constant), confirm the test goes red, revert.

Details, naming rules, and a worked example: `references/writing-tests.md`.

### Audit

1. **Scope**: explicit argument → that. Otherwise test files touched by uncommitted changes;
   otherwise ask, or sample the suite (mix of small/large, logic/mock-heavy files).
2. **Mechanical scan** for grep-able smells (weak asserts, sleeps, `.skip`/`@Disabled`,
   `.only`, loops in test bodies, mock round-trips) — commands in
   `references/audit-procedure.md`.
3. **Per-test pass**: run each test through the Five-Question Gate and the catalog in
   `references/anti-patterns.md`. Assign a verdict:

   | Verdict | When |
   | --- | --- |
   | **Keep** | Passes the gate |
   | **Tighten** | Right contract, weak execution — imprecise asserts, bad name, sleep |
   | **Rewrite** | Real contract worth pinning, but the test pins implementation or a mock |
   | **Delete** | No contract sentence, duplicate coverage, trivia, rotting disabled test |

4. **Report** using the template in `references/audit-procedure.md`. Audit mode never edits.

### Improve

1. Start from audit verdicts (run an audit first if there isn't one).
2. Apply the **smallest transformation** per smell — the catalog maps each anti-pattern to its
   fix. Tighten before rewriting; rewrite before deleting.
3. **Never weaken an assertion to make a test pass.** A red test is a claim about behavior —
   resolve the claim (fix code, or consciously change the contract), don't blur it.
4. **Before deleting**, extract the test's intent: if it names a real, otherwise-untested
   promise, rewrite it against the contract instead. Delete only when the intent is empty
   (tautology, trivia, duplicate) or dead (disabled with no plan).
5. **Verify**: full suite green, then mutation spot-check every rewritten test — a rewrite that
   never goes red on a broken SUT just moved the theater around.
6. Report what changed, grouped by verdict, with before/after counts.

## Quick Reference

| Smell | Verdict → fix |
| --- | --- |
| Mock returns X, assert X comes back | Delete, or Rewrite against the translation the module performs |
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
| Test asserts an acknowledged-wrong value ("should be 4, left as is") | Surface it: that's a bug tracker entry wearing a test costume |
| `.skip` / `@Disabled` / commented-out for months | Delete (git remembers), or fix now |
| Getters, framework wiring, generated code under test | Delete: cost > 0, information = 0 |

Full catalog with mechanisms, detection, and worked fixes: `references/anti-patterns.md`.

## Common Mistakes

- **Weakening an assert to stop a flake.** The flake is the bug — fix the determinism, keep the
  precision.
- **"Fixing" a tautology by asserting more of the mock.** More tautology is still tautology;
  re-anchor to what the module *does* to the data, or delete.
- **Deleting a bad test whose intent was real.** Check question 1 of the gate before deleting —
  a badly-written test for a real rule gets rewritten, not removed.
- **Mock-padding a slow test instead of extracting logic.** Slowness is design feedback; pull
  the pure part out and test it mock-free.
- **DRYing tests into a helper labyrinth.** Test code optimizes for the reader of a failure,
  not for zero duplication — a little repetition that keeps each test self-explanatory wins.
- **Renaming tests without re-anchoring them.** A behavior-sentence name on an
  implementation-coupled body is worse than before — the label lies.
- **Auditing e2e suites with unit-test rules.** e2e tests legitimately chain steps and share a
  browser; hold them to determinism, explicit asserts, and independence — not to one-Act purity.

## References

- `references/writing-tests.md` — contract listing, naming, case selection, doubles, worked
  example, per-stack idioms (Vitest/TS, JUnit/Mockito, WebdriverIO e2e)
- `references/anti-patterns.md` — full catalog: symptom, mechanism, detection, fix
- `references/audit-procedure.md` — scan commands, verdict rubric, report templates
