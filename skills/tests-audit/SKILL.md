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
allowed-tools: Read Grep Glob Bash(grep:*) Bash(rg:*) Bash(fd:*) Bash(cat:*) Bash(wc:*) Bash(xargs:*) Bash(od:*) Bash(git diff:*) Bash(git log:*) Bash(git show:*) Bash(mktemp:*) Bash(cp:*)
argument-hint: "[files | dir]"
metadata:
  tier: routed
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

Corollary: coverage percentage measures neither direction — 0% is a real gap, high coverage proves
nothing, and uncovered defensive branches are correct. A test justified only by a coverage number
is a finding; raise a threshold only for a gap in real behavior.

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
  processes. Use real collaborators for everything you own.
- **A double must be able to happen**: it throws and returns only what the real dependency can
  at that call site (1.12; numbers index `references/anti-patterns.md`).
- **Prefer hand-rolled fakes** over interaction mocks — fakes verify state, mocks verify choreography.
- **Interaction asserts** only when the outgoing call *is* the contract; call counts only when
  the count is documented behavior, never as a change detector.
- A thin adapter's contract is its translation, not the mock's echo (1.1). Heavy mocking is
  design feedback on the module, reported as such, never refactored here (`references/writing-tests.md` §6).

## Workflow

1. **Scope**: explicit argument → exactly that. Otherwise the test files in the working
   tree's changes; otherwise the project's test suite — read whole at 30 test files or fewer,
   and above that sampled to a floor of 20 files or a quarter of the suite, whichever is
   larger, mixing small and large files, pure-logic and mock-heavy, plus any e2e specs.
   Diff-scoped is a first-class mode, not a borrowed one: `edloidas:changes-review` judges
   whether the change is correct, this skill judges whether the tests pin anything. Scope
   bounds the *verdicts*, not the reading — a Delete for duplicate coverage still means
   reading the neighbouring tests the diff never touched.
   End with one line: `Scope: 24 of 96 test files (sampled) · vitest 3, wdio 9`.
2. **Mechanical scan** for grep-able smells (weak asserts, sleeps, `.skip`/`@Disabled`,
   `.only`, loops in test bodies, mock round-trips, catch-only error tests, exports only tests
   import) — commands in
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

## Common Mistakes

- **Reading repetition as duplication.** Copy-pasted arrange blocks are a real Low finding
  (3.4), but test code optimizes for the reader of a failure, not for zero duplication. Never
  recommend DRY-ing tests into a shared-helper labyrinth as the fix.
- **Auditing e2e suites with unit-test rules.** e2e tests legitimately chain steps and share a
  browser; hold them to determinism, explicit asserts, and independence — not to one-Act purity.
- **Writing an inference in the register of a measurement.** A runtime claim is either observed,
  with the command shown, or a labeled hypothesis carrying the command that would settle it. Reading
  the source never licenses "verified".
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
