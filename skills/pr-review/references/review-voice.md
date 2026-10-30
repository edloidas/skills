# Review voice

How a review on someone else's pull request sounds: the body, the inline comments, an approval,
and the one-line replies on your own threads after a fold. What goes into it — demonstration,
attribution, length ceilings, the `APPROVE` shape — stays with changes-review's
`references/publishing-a-review.md`. This file only decides how it is said, and is read before
drafting by pr-review, pr-triage, and changes-review when it publishes a review directly.

## Talk to the author

The reader is the person who wrote the code, so every sentence is addressed to them. A sentence
that tallies or narrates — "Two comments need a change or a decision before merge", "Found 3 issues,
1 blocking", "Verification confirmed the following" — is the report to the user leaking into the
review. The count is fine; the narration is not. Say it to the author, in the first person: "Two
things I'd sort out before merging; the rest are small."

## The first line

It may acknowledge the work, in proportion to it. A large piece of work can be praised for what is
actually good in it, named specifically — "moving the sync into one bus makes the content flow much
easier to follow". A small one gets a plain human line: "Looks good", "Nice and tidy". Never
flattery, and never praise the work did not earn: a superlative on a two-line fix reads as sarcasm
or as a bot. No acknowledgment beats a hollow one.

## Ask, or say it straight

| The point | How it reads |
| --------- | ------------ |
| A concrete bug with `file:line` evidence | Direct: what breaks, where, and how to see it |
| The author's call — naming, structure, UX, scope, an approach that works either way | A question or a suggestion: "Would it be simpler to…?", "Might be worth a look", "Up to you" |
| The same, when the author owns the area — the architect, the module's maintainer | Softer still: say what you noticed and ask; they may know a reason you do not |

## Plain

Plain words and short sentences, the way you would say it at their desk. No report scaffolding —
`Summary:`, `Findings:`, numbered severity lists, `Blocking` labels — and no stacked hedges. Length
is set by what the author has to do; the ceilings in the publishing reference still apply, and this
file adds none.

## Language

The published text is in the repository's language — the one its pull requests and reviews are
written in, English when unclear. The report to the user is in the language they write to the
session in. The two often differ: a Russian conversation about an English repository gets a
Russian report and an English review.

## Before and after

An architect's pull request moving content sync out of the panels into one event bus. The finding
set is the same in both; only the voice changes. Each is shown as one block for comparison — in the
posted review the bug is its own inline comment at `EventBus.ts:88`, as the publishing reference
places it.

Before — accurate, and written to the wrong person:

```markdown
Two comments need a change or a decision before merge. The remaining three are minor and grouped.

Findings:
1. Blocking: `ContentEventBus.subscribe()` does not remove its listener on unmount (EventBus.ts:88).
2. The `SyncStrategy` abstraction is unnecessary with a single implementation. Inline it into `ContentSync`.
3. Minor: `doSync2` is unclear naming.
```

After:

```markdown
Nice work — moving the sync out of the panels into one bus makes the content flow a lot easier to
follow, and the reconnect tests are a great addition.

One thing I'd fix before merging: the listener `subscribe()` adds is never removed, so every reopened
panel stacks another one (`EventBus.ts:88`). Open and close the panel three times and a single save
fires `onSaved` four times.

The rest is your call. I wasn't sure yet what `SyncStrategy` buys us with one implementation — is a
second one coming? If so, ignore me. And `doSync2` might read better with a name that says how it
differs from `doSync`.
```

The bug stays direct and carries its evidence; the design point becomes a question, because the
author designed the module; the tally and the labels are gone.
