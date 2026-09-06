# Applying a Tests Audit

`tests-audit` reports and never edits, so Phase 4.5 applies its verdicts itself.

## Scope

Audit only the test files the branch added or modified, taken from the working tree by
the rule Phase 2 → Create branch states. A suite-wide audit on an issue the user called
simple returns a backlog nobody asked for, and every item in it is out of scope for the
commit being built.

## Which verdicts to apply

| Verdict | Test this branch wrote | Pre-existing test it modified | Other pre-existing test |
| ------- | ---------------------- | ----------------------------- | ----------------------- |
| Keep | Nothing | Nothing | Nothing |
| Tighten | Apply — sharpen the assert, drop the mock round-trip | Apply | Apply when the fix is a line or two; otherwise Note |
| Rewrite | Apply — as written it pins nothing | Apply | Note only |
| Delete | Delete it, and say so in the Phase 6 summary | Note only | Note only |

**Deleting a pre-existing test is never this issue's work**, even one this branch edited —
a test the issue enumerated is one the user expects to still exist. Carry it as a Note.

**A small Tighten beside it is worth taking**: a line or two, and it strengthens an oracle
rather than removing one. Holding it back files an issue nobody wants to read.

**A Delete is not a coverage regression.** A test *this branch wrote* that passes for the
wrong reason protects nothing, and keeping it because a percentage would move is the
failure mode `tests-audit` exists to name. Report the deletion rather than defending the
number.

## Re-running the suite

Re-run the unit test script after applying. A tightened assert that now fails is one of
two things, and Phase 4.5 states the rule for telling them apart:

- **The defect the loose assert was hiding.** Fix the code. This is the payoff.
- **A bad tightening** — the assert now pins something the contract never promised.
  Revert that one assert.

## When `tests-audit` is not installed

Run its gate inline against each test this branch added, and act on the same table:

1. **Contract** — which one-sentence promise of the public API does it pin, and does its
   name claim no more than the assert delivers?
2. **Refactor-proof** — would it survive a behavior-preserving refactor of the internals?
3. **Falsifiable** — would it fail for a realistic bug? Name the dumbest implementation
   that still passes; if a constant or the test's own Arrange step satisfies the assert,
   it constrains nothing.

Any "no" is a Tighten, Rewrite, or Delete.
