# Severity Rubric

The single source of severity for code-to-spec audits. The audit prompt carries none of its own.

## Critical

A finding is Critical when any of these holds:

- A reimplementer following the spec would produce observable behavior that differs from source.
- Source has a behavior the spec omits entirely, and no finish or non-goal entry covers it.
- A claim is wrong against its citation, or the cited code does not exist.
- An obligation is marked `observed` but rests on inference.
- A case kind an obligation lists has no acceptance case, or a case's `Then` contradicts source.
- A case marked `Source: test` points at a test that does not assert it.
- A `not found` or `MISSING` claim is contradicted by a search.
- A secret is transcribed unredacted.

## Warning

A finding is Warning when any of these holds:

- A gap a reimplementer would notice and have to fill by reopening the source.
- A payload, message, default, or branch result is paraphrased instead of literal.
- An `inferred` obligation has no `Basis:`, or an `unknown` has no open question.
- A summary-depth gap hides interface, data, or error behavior.
- A messaging asymmetry or a missing teardown went unflagged.
- An open question is rated below `high` although guessing wrong changes visible behavior.

## Note

A finding is Note when any of these holds:

- A minor omission or imprecision that does not change what a reimplementer builds.
- A missing cross-reference.
- A wording slip a reimplementer would read through.

## Precheck Lines

The script's problem lines map onto the levels above:

| Problem | Severity |
| ------- | -------- |
| case kind with no case, case for an unknown obligation, `Source: test` citing a non-test file, cited file not found, cited line past the end of the file | Critical |
| possible secret, unless the auditor confirms it is a public test fixture or a documented example, which is a Note | Critical |
| malformed heading, missing `Cases`, `Source`, or `Basis` line, dangling `Depends on`, bare file name or absolute path in a citation | Warning |

## Fail-closed Rules

- An unverified check counts as a gap, never as a pass. It goes under `Unverified`, and the run
  report counts it.
- A skipped or truncated input is a finding.
- `blocked`, `skipped`, `truncated`, and `unknown` never add up to covered.
- An audit can lower a claim's state. It never raises one.
- Severity follows the impact on the rewrite, never the effort a fix would take. A finding that
  is true but does not affect the rewrite is a Note. A finding that misreads the scope is
  dismissed with one line of reason.
