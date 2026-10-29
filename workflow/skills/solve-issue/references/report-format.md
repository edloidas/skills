# Report Format

## Phase 6 summary

Print this shape, omitting rows that do not apply:

```text
## Solved #<N>: <title>

**Changed**
- <bullet per logical change>

**Related work**
- <Skip | Prepare | Correct from the plan, one line each, with its source issue>

**Verified**
- type-check: ok
- unit tests: ok (N passed)
- build: ok
- observation: skipped (not behavioral) | reproduced | refuted | unverified (<reason>)

**Tests**
- N audited — N tightened, N rewritten, N deleted, N noted
- <one line per test changed by the audit>

**Advisors** (N round(s))
- cold (<model>) · intent (<model>) · external (<cli>|skipped)
- N findings — N fixed, N noted, N rejected

**Outcomes**
| State | Finding | Where / why |
| --- | --- | --- |
| fixed | <one line> | `<file:line>` |
| filed | "<verbatim>" | #<issue> |
| declined | "<verbatim>" | refuted, not worth the fix, already tracked by #<M>, or under the bar — <why; for refuted, the context the reviewer lacked> |
| blocked | "<verbatim>" | <the credential or live service it waits on> |

**Needs you**
- blocked: decision — <the question only the user can answer>

**Commit** `<short-sha>` <subject>
**Stashed** `<stash message>` — in `git stash list`
```

Omit, when they do not apply:

- the **Advisors** detail lines when the reviewers came back clean — a single
  `no findings` line is enough
- **Tests** when Phase 4.5 was skipped
- **Outcomes** and **Needs you** when there is nothing in them
- **Related work** when the plan had none — it is the record of where the commit departs
  from the issue text, so a Skip or Correct the plan made is never left out of it
- **Stashed** when Phase 2 took no stash. The summary prints before any merge, so the row
  never claims a restore; on the merge path the line after the merge settles it

Every finding and observation the run produced is one row, in the state SKILL.md's Phase
4.6 → **Outcomes** assigns; a `blocked: decision` row goes under **Needs you** instead,
phrased as the question. There is no free-form notes list: an entry with no state is the
open end this table exists to close.

The quoted finding is not decoration. Every row but `fixed` carries the source's own words,
unedited; if you shorten it, say how many sentences you cut and from where. The user grades
the rejection, and a paraphrase is the implementer grading itself.

**Outcomes is a record to be graded, not a backlog proposal.** List rows flat, in the
order found. Do not rank them, single any out, or close the report by offering to file or
fix them — the state already says what happens. A report ending in a pitch turns finished
work back into pending work.

### A filled-in summary

```text
## Solved #412: Fix tooltip clipping at the viewport edge

**Changed**
- `src/ui/Tooltip.tsx` — flip placement when the measured rect leaves the viewport
- `src/ui/useAnchorRect.ts` — return the raw rect instead of a clamped one

**Related work**
- Skip: `Popover` placement — #413 owns it
- Prepare: exported `resolvePlacement(rect, viewport)` — for #415
- Correct: resolves once after first paint, per a comment on #412, not on every scroll

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
- 5 findings — 2 fixed, 2 noted, 1 rejected

**Outcomes**
| State | Finding | Where / why |
| --- | --- | --- |
| fixed | Flip logic ignored `scrollY`, so the check passed on a scrolled page | `Tooltip.tsx:41` |
| fixed | `useAnchorRect` re-measured on every render | `useAnchorRect.ts:18`, memoized on the anchor node |
| declined | "`Popover.tsx:88` repeats the clamped-rect bug this change fixes in `Tooltip`." | already tracked — #413 owns `Popover` placement |
| declined | "The rect is never recomputed on resize, so the flip is stale after a window resize." | refuted — `useAnchorRect` installs a `ResizeObserver` |

**Needs you**
- blocked: decision — the 300 ms open delay feels slow on touch; the issue never mentions it. Drop it to 0 on touch?

**Commit** `a3f91c2` fix: flip tooltip placement at the viewport edge #412
**Stashed** `issue-412 from master` — in `git stash list`
```

## Phase 7 block

Phase 7 appends to the summary above rather than reprinting it:

```text
**Review feedback** (N round(s))
- <bot> — reported | silent after <budget>, skipped
  | none requested on this PR (timeline checked <time>)
- N threads — N fixed, N rejected, N discuss, N deferred
- Re-requested: <who, or none>
- Outcomes: one row per thread acted on, and one per Phase 6 row whose state changed —
  a `filed` Note gets its number — in the Phase 6 table's shape
- Shipped after the summary above: <files and one line each, or `nothing`>
- Held unsent: <human thread, and the draft reply composed for it>
```

When Phase 2 took a stash and the merge ran, print one more line after `issue-flow`'s
Step 6 report: `Stash: restored` when that report has no `Stashed:` line, otherwise
`Stash: still in git stash list (<other branch | conflict>)`. A run that did not merge
prints nothing here — the Phase 6 row already says where the stash is.

The reviewer line reports **what was read, not what exists**. "None requested on this PR"
with the time it was checked is a fact about the timeline; `No automated reviewers` is a
claim about the repository that no query supports.

Thread verdicts map onto the states: fix is `fixed`, reject is `declined: refuted`, defer
is `filed`, and `discuss` is `blocked: decision` under **Needs you**. A `filed` row is a
deferral's only durable home on the merge path: the pull request closes and takes the
resolved thread with it, so a deferral without an issue number here has been lost. A
`defer` nothing files — `PR only`, or a user who said not to file — is not left as a
thread: it is fixed, declined, or `blocked: decision`.

The **Shipped after the summary** line is not optional when it is non-empty. Phase 6
printed a summary of the commit, and any fix applied here changes what merges — a merge
whose content the user never saw described is the thing that line exists to prevent.

A bot skipped after its budget is still listed. So is a thread `pr-review` left open because
its verdict was `discuss` — a decision waiting on a person is the one thing in this
report that has to survive the run ending.
