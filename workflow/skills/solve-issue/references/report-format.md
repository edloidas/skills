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
- <Note: out of scope | Reject: the context the reviewer lacked>
  > <the finding, quoted verbatim in the reviewer's own words>

**Commit** `<short-sha>` <subject>
```

Omit the **Advisors** detail lines when the reviewers came back clean — a single
`no findings` line is enough. Omit **Tests** when Phase 4.5 was skipped, and **Not
applied** when there is nothing in it.

The blockquote under **Not applied** is not decoration. Reproduce the finding in the
reviewer's own words, unedited; if you shorten it, say how many lines you cut and from
where. The user grades the rejection, and a paraphrase is the implementer grading itself.

### A filled-in summary

```text
## Solved #412: Fix tooltip clipping at the viewport edge

**Changed**
- `src/ui/Tooltip.tsx` — flip placement when the measured rect leaves the viewport
- `src/ui/useAnchorRect.ts` — return the raw rect instead of a clamped one

**Verified**
- type-check: ok
- unit tests: ok (218 passed)
- build: ok
- observation: reproduced — tooltip flips above the anchor at y > 640

**Tests**
- 3 audited — 1 tightened, 0 rewritten, 1 deleted
- `Tooltip.test.tsx` "renders" deleted — asserted only `toBeDefined()`
- `Tooltip.test.tsx` "flips" tightened — now asserts the resolved placement, not a class

**Advisors** (1 round)
- cold · intent · external (codex)
- 4 findings — 2 fixed, 1 noted, 1 rejected
- Flip logic ignored `scrollY`, so the check passed on a scrolled page
- `useAnchorRect` re-measured on every render; memoized on the anchor node

**Not applied**
- Note: out of scope — the same clamp exists in `Popover.tsx`, untouched by this issue
  > `Popover.tsx:88` repeats the clamped-rect bug this change fixes in `Tooltip`.
- Reject: the reviewer could not see `ResizeObserver` is installed by `useAnchorRect`
  > The rect is never recomputed on resize, so the flip is stale after a window resize.

**Commit** `a3f91c2` fix: flip tooltip placement at the viewport edge #412
```

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
