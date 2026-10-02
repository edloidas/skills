# Slices

Loaded only in slice mode (**Conventions → Slices**). A slice is one small, complete
increment of the issue: it compiles, passes the checks, and leaves the project working. How
big a slice is and how to cut one is the repo's rule, from its instruction file; this file
owns only the loop.

## Planning (Phase 2)

Print the plan per `plan-format.md` with its **Slices** block: each slice is one
conventional subject line and the Changes items it carries, in landing order. Every Changes
item belongs to exactly one slice. Never cut by layer — types in one slice and the logic
that uses them in the next are two halves of one slice.

A list of parts in the issue body is input to the cut, never the switch that turns slice
mode on. Track progress per Changes item as usual, grouped under their slice.

## The loop

For each slice `k`, in order. Its **slice base** is the previous slice's commit, or the
`Fork:` SHA for slice 1.

1. **Phase 3** — implement only this slice's Changes items.
2. **Phases 4, 4.4, 4.5** — scoped to the working tree against the slice base, not the fork.
3. **Phase 4.6** — `changes-review --base <slice base> --issue <N>`. The round cap applies
   per slice. No extra round over the whole branch afterwards: every line was reviewed in
   its slice.
4. **Phase 5** — commit with intent `"commit slice <k> of #<N>: <subject>"`. Its commit is
   the next slice base.
5. Print the slice report below.

Attended, end the turn after the slice report: the next slice starts on the user's go,
and that wait is a gate, not an early stop. Under `auto`, continue to the next slice in the
same turn. Phases 6 and 7 run once, after the last slice.

## Changing the cut

Committed slices are never re-cut or reordered. When the remaining plan turns out wrong —
a slice too large, an order that does not build, a missing piece — re-cut only the
uncommitted slices, reprint the **Slices** block, and continue. Under `auto`, record
`Re-sliced after slice <k>: <reason>` in the Phase 6 summary.

## Resuming

Entered on an existing `issue-<N>` branch, read `git log --reverse --format=%s <fork>..HEAD`:
commits that are not `wip:` are finished slices, in order; trailing `wip:` snapshots and
the working tree are the open one. Re-plan with finished slices marked done and continue
from the open one. Git history is the only record — never write a slice file.

## Slice report

```text
**Slice <k>/<total>** `<short-sha>` <subject>
- Changed: <one line per logical change>
- Verified: <groups, as Phase 4's closing line>
- Advisors: <N> findings — <N> fixed, <N> noted, <N> rejected
- Not applied: <entries in the Phase 6 shape, reviewer's words verbatim>
- Next: <k+1> <subject> | none — Phase 6 next
```

The Phase 6 summary then lists **Commits**, one `<short-sha> <subject>` line per slice, in
place of the single **Commit** line, and carries every slice's Not applied entries.

## Review feedback (Phase 7)

Fixes land in the last slice, per `issue-flow` Amend. A fix that belongs to an earlier
slice is reported in the Review feedback block as shipped in the last one, not rebased into
history.
