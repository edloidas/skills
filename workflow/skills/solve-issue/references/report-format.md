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
- <bot> — reported | timed out after <budget> | still pending (not waited on)
  | none requested on this PR (timeline checked <time>)
- N threads — N fixed, N rejected, N discuss, N deferred
- <one line per thread acted on>
- Deferred to: #<issue> — <claim>   (merge path only; `—` when nothing was deferred)
- Shipped after the summary above: <files and one line each, or `nothing`>
- Held unsent: <human thread, and the draft reply composed for it>
```

The reviewer line reports **what was read, not what exists**. "None requested on this PR"
with the time it was checked is a fact about the timeline; `No automated reviewers` is a
claim about the repository that no query supports.

The **Deferred to** line is the deferral's only durable home on the merge path: the pull
request closes and takes the resolved thread with it, so a deferral without an issue
number here has been lost.

The **Shipped after the summary** line is not optional when it is non-empty. Phase 6
printed a summary of the commit, and any fix applied here changes what merges — a merge
whose content the user never saw described is the thing that line exists to prevent.

A reviewer that timed out is still listed. So is a thread `pr-review` left open because
its verdict was `discuss` — a decision waiting on a person is the one thing in this
report that has to survive the run ending.
