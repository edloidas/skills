# Applying a Tests Audit

`tests-audit` reports and never edits, so Phase 4.5 applies its verdicts itself.

## Scope

Audit only the test files the branch added or modified, taken from the working tree by
the rule Phase 2 → Create branch states. A suite-wide audit on an issue the user called
simple returns a backlog nobody asked for, and every item in it is out of scope for the
commit being built.

## Which verdicts to apply

| Verdict | On a test this branch wrote | On a pre-existing test |
| ------- | --------------------------- | ---------------------- |
| Keep | Nothing | Nothing |
| Tighten | Apply — sharpen the assert, drop the mock round-trip | Note only |
| Rewrite | Apply — as written it pins nothing | Note only |
| Delete | Delete it, and say so in the Phase 6 summary | Note only |

A verdict on a test this branch did not write is not this issue's work: carry it into
the Phase 6 summary as a Note. The one exception is a pre-existing test this branch
modified — you already own those lines, so its verdicts apply in full.

**A Delete is not a coverage regression.** A test that passes for the wrong reason
protects nothing, and keeping it because a percentage would move is the failure mode
`tests-audit` exists to name. Report the deletion rather than defending the number.

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
