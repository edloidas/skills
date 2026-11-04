# Longer Issue Bodies

Three bodies past the prose-paragraph size of the `SKILL.md` Step 7 draft, one per shape the
material can force. Each covers the Step 6 slots in a different form; none is a mold. Take the
form the material needs, not the example nearest in kind.

## A Feature With Limits

Lists appear because the limits and the done conditions are parallel items. No headers: the
body has no distinct parts yet.

````markdown
**Title:** `feat: let next-issue skip issues blocked by open dependencies`

`next-issue` recommends issues that cannot start yet: it ranks by size and type but never reads
GitHub's blocked-by relationships, so #58 topped the list in two runs while #57, which blocks
it, was still open. Every such pick costs a wasted session, which is why this goes before the
ranking change in #61.

Read each candidate's `blockedBy` in the GraphQL query that already fetches labels, and drop a
candidate with at least one open blocker before ranking. A dropped issue frees its slot, so
the user still gets the full number of picks.

Ranking of unblocked issues stays as it is, and the query stays a single call — no per-issue
follow-up requests.

Limits:
- fetch up to 20 blockers per issue; an issue with more is treated as blocked
- a blocker in another repository counts when the query returns its state, and is ignored
  otherwise

Done when:
- an issue with any open blocker never appears among the picks, and the pick count is unchanged
- an issue whose blockers are all closed ranks as if it had none
- the report's "what blocks the rest" section lists each skipped issue with every open
  blocker's number
- `bash tests/run.sh` passes with a new case covering zero, one, and several open blockers
````

## A Refactor With a Decided Design

Headers appear because the body has distinct parts: what is wrong, the behaviour to keep, the
design, scope. The free headers state their content; `Done when` and `Out of scope` keep their
fixed names. The tie-breaking and menu-order rules stay in the design — they are what an
implementer cannot recover from the code, and without them the design contradicts the table.

`````markdown
**Title:** `OverflowActionRow: replace primaryOverflowActionId with primaryRank`

#11474 added `primaryOverflowActionId` to `OverflowActionRow` so Preview takes the split
button's main slot when the toolbar overflows, and #11488 copied it into the browse toolbar.
The behaviour is right; the API encodes a ranking as one hard-coded id plus a special case.
This replaces the prop with a rank on the row item and keeps the behaviour identical at every
width. The design below is decided.

All paths are under `modules/lib/src/main/resources/assets/js/v6/widgets/browse-toolbar/`.

### What is wrong today

- **A one-off flag instead of a rule.** `getOverflowActions(actions, visibleCount, primaryOverflowActionId)`
  moves one id to the front of the overflow, but only when `visibleCount > 0`. That hidden
  condition is what keeps Save and New as the main action when everything collapses.
- **String magic.** `"preview"` is a literal in both toolbars; `'Preview'` compiles and does
  nothing.
- **A dependency that triggers nothing.** `primaryOverflowActionId` sits in both
  `useLayoutEffect` dependency arrays, but `calculateVisibleActions` never reads it.

### Behaviour that must not change

`k` is the number of buttons that fit in the row:

```
wizard [save, reset, localize, archive, duplicate, move, preview]
k=6..1  row = first k items   split main = preview
k=0     row = []              split main = save, preview last in the menu
browse [new, edit, archive, duplicate, move, sort, preview]
k=6..1  row = first k items   split main = preview
k=0     row = []              split main = new, preview last in the menu
```

### Target design

1. `OverflowActionRowItem` gains `primaryRank?: number`. It decides only which overflowed item
   takes the split button's main slot, never which buttons stay in the row. The
   `primaryOverflowActionId` prop is removed.
2. `getOverflowLayout(items, visibleCount)` in `OverflowActionRow.utils.ts` replaces
   `getOverflowActions` and returns `{ rowItems, overflowItems }`. The highest-ranked
   overflowed item comes first; every other overflowed item keeps source order. Unranked
   counts as 0, and a tie goes to the earlier item. There is no `visibleCount > 0` branch:
   the `k=0` row of the table follows from Save and New holding the highest rank.
3. `OverflowActionRow.tsx` calls it for both the rendered and the offscreen-measured split
   button, so the two cannot disagree.
4. `ContentWizardToolbar.tsx` sets `primaryRank: 2` on Save and `1` on Preview;
   `BrowseToolbar.tsx` sets `2` on New and `1` on Preview.

### Out of scope

- The disabled Preview shown as the main action — #11495, a later change to
  `getOverflowLayout`.
- Moving `SplitActionButton` to `@enonic/ui`.

### Rejected alternatives

- **Rank decides row retention too.** It changes which buttons are visible at most widths and
  needs a design decision first; if it comes, it gets its own field.

### Done when

- [ ] `primaryOverflowActionId`, the `visibleCount > 0` branch, and the `"preview"` literals are gone
- [ ] both toolbars match the table at every width, pinned by a `k = 0..n` test for each
- [ ] `pnpm -C ./modules/lib run check` and `pnpm -C ./modules/lib run test:run` pass
`````

## A Spike

There is nothing to implement yet, so Done when names the decision that closes the spike,
not a behaviour.

````markdown
**Title:** `Measure whether the v6 tree view needs virtualization`

The content tree renders every loaded node, and a project with 4,000 children under one folder
takes 2.8 s to expand on a 2021 MacBook Air (Chrome 131 profile attached). Virtualizing it
would touch selection, keyboard navigation, and drag-and-drop, so it is worth knowing first
whether rendering is the cost at all. Likely cause: layout from per-row `ResizeObserver`s, not
the node count — confirmed if the profile time drops when they are removed.

Done when the issue records the expand time at 1,000, 4,000, and 10,000 children with and
without per-row observers, and states one decision: virtualize, remove the observers, or
neither — with the follow-up issue opened for the chosen one.
````
