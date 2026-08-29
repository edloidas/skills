# Report Format

## Phase 6 summary

Print this shape, omitting rows that do not apply:

```text
## Solved #<N>: <title>

**Changed**
- <bullet per logical change>

**Verified**
- type-check: ok
- unit tests: ok (N passed)
- build: ok
- observation: skipped (not behavioral) | reproduced | refuted | unverified (<reason>)

**Tests**
- N audited — N tightened, N rewritten, N deleted
- <one line per test changed by the audit>

**Advisors** (N round(s))
- cold (<model>) · intent (<model>) · external (<cli>|skipped)
- N findings — N fixed, N noted, N rejected
- <one line per fixed finding>

**Not applied**
- <finding, in the reviewer's own wording> — <Note: out of scope | Reject: the
  context the reviewer lacked>

**Commit** `<short-sha>` <subject>
```

Omit the **Advisors** detail lines when the reviewers came back clean — a single
`no findings` line is enough. Omit **Tests** when Phase 4.5 was skipped, and **Not
applied** when there is nothing in it.

## Phase 7 block

Phase 7 appends to the summary above rather than reprinting it:

```text
**Review feedback** (N round(s))
- <bot or human> — reported | timed out after <budget>
- N threads — N fixed, N rejected, N discuss, N deferred
- <one line per thread acted on>
```

A reviewer that timed out is still listed. So is a thread `pr-review` left open because
its verdict was `discuss` — a decision waiting on a person is the one thing in this
report that has to survive the run ending.
