# Report format

One shape for every message this skill ends on: the plan at a gate (Phase 3, Phase 6), each deep
review (Phase 4), and the final report. The reviewer may not have seen any earlier session, so each
pull request has to make sense from its own section, without opening it.

## Shape

1. **Title and run line.** `## PR triage · <N> PRs in <M> repositories`, with the owner or
   repository after `PR triage ·` only when the run was scoped with `owner`, `repo` or `current`,
   and `· <K> yours` at the end when the own set is not empty. `<N>` counts the pull requests
   waiting on your review. Then one line saying how far to trust
   the report: what ran, the counts from triage to verdicts, and anything that degraded the run — no
   outside judge, a capped queue, a repository read without a clone, a check that did not run.
2. **One section per pull request**, in plan order: ready to act, send back, deep review, held.
3. **Summary table.**
4. **Your pull requests** — the own set, when it is not empty.
5. **Needs your call** — the questions, at most three; the plan question is the fourth.
6. **Dropped** and **Skipped**, one line each, under those two headings.
7. **The decision**, one bold sentence, last.

Omit a part that would be empty.

## Action markers

Every standard action is written with one marker, in capitals inside backticks, and never in other
words: `APPROVE`, not "approve it" or "LGTM". Plain text may sit around a marker — the merge method,
the branch, the reason — or replace it where no marker fits.

| Marker | At a gate | In the final report |
| ------ | --------- | ------------------- |
| `APPROVE` | Approve the pull request | `APPROVED` |
| `MERGE` | Merge it, method in parentheses | `MERGED`, with the commit |
| `FOLD` | Amend the author's last commit with the small fixes, force-push with lease | `FOLDED`, with the new head |
| `REQUEST_CHANGES` | Request changes with the listed points | `CHANGES_REQUESTED`, with the review link |
| `COMMENT` | A comment-only review | `COMMENTED`, with the review link |
| `DEEP_REVIEW` | Send to Phase 4 | — (a deep review ends in one of the others) |
| `HOLD` | Wait on a question before acting | `HELD`, with the question id |
| `SKIP` | Not triaged: stale, no change, unreadable | `SKIPPED` |

Markers chain in the order they run: `FOLD`, then `APPROVE`, then `MERGE`.

## A pull request's section

The heading links the number to the pull request and the repository name to the repository, and
carries the title:

```
### [#2793](https://github.com/enonic/app-users/pull/2793) · [enonic/app-users](https://github.com/enonic/app-users) — ID provider mode in the Users and Groups sections
```

Then labelled lines, each readable by someone who knows nothing about the pull request:

| Line | Holds |
| ---- | ----- |
| `**Does:**` | First report: what the change does for a user or a caller, in one or two sentences, and its size |
| `**Since your review:**` | Recheck: what the author changed, and how each of your points stands |
| `**Found:**` | Each finding as a bullet — severity, the defect in plain words with the consequence, then how it was confirmed and where (`file:line`). `Nothing above minor` when that is the case |
| `**Proposed:**` | The action markers, then what they write and where, and what they wait on. A `FOLD` lists each exact change — `file:line`, before → after — because the gate authorizes a force-push of exactly those |
| `**Done:**` | Final report: replaces `**Proposed:**` with the outcome markers and their commit or review link |

A finding says what goes wrong and for whom, not only where: "a group key passed as a role adds the
user to a locked group, past the guard", never "unchecked cast in `applyMemberships`". Every
finding appears in exactly one section.

## Summary table

Right after the last pull request section. One row per pull request, the number linked:

| PR | Now | After, if you accept |
| -- | --- | -------------------- |
| the linked `repo#N` | its state today in a few words — `open`/`draft`, CI, your last verdict | the markers of the state it ends in, with a question id when the row depends on one |

In the final report the last column is headed *Result* and holds the outcome markers.

## Your pull requests

Under `### Your pull requests`, one table, grouped in the order *Needs you*, *Ready to merge*,
*Waiting*. These are never triaged, so there is no section per pull request:

| PR | State | Why |
| -- | ----- | --- |
| the linked `repo#N` and its title | the state from SKILL.md's own-set table | the columns that put it there, in words: "changes requested by bob, 2 open threads", "approved, CI green, clean", "no reviews yet" |

A *Ready to merge* row carries `MERGE` when the run has `merge` and the row is in the plan, and
`MERGED` with the commit in the final report. A *Needs you* row ends with the next step, run by the
reviewer: `pr-review <url>`.

## Needs your call

`**Qn. [#N](url): <question>** Assumed: <the answer the plan used>. → if not: <what changes>`

The assumed answer lets the report read the same whether the reviewer answers or the run continues
unattended. Keep only questions whose answer changes a row. When more than three would, the rest
hold their rows (`HOLD`) and are asked at the next gate.

## Dropped and Skipped

One line each — the claim and what refuted it, or the pull request and why it was not triaged. A
drop nobody can see reads as a finding nobody checked.

## The decision

One bold sentence under a rule (`---`), headed `### Plan` at a gate and `### Next` in the final
report. When a question's answer would change a row, the sentence carries the flip: `… — unless Q1
is "no", then #687 goes back too.` The final report adds, before the rule, one line each for
*Writes on others' branches*, *Not run*, *Rules broken*, and *Local*.

## A filled-in final report

````markdown
## PR triage · 3 PRs in 3 repositories

Run: Acted: 2 merged, 1 changes requested · outside judge: codex · every write from an approved row

### [#686](https://github.com/enonic/app-ai-translator/pull/686) · [enonic/app-ai-translator](https://github.com/enonic/app-ai-translator) — Upgrade Gemini models
**Does:** moves the translator's default model from `gemini-3.1-flash-lite`, which Google retires, to `gemini-3.5-flash-lite`. Two files, +5/−5.
**Found:** nothing above minor.
**Done:** `APPROVED` and `MERGED` (rebase) as 21cfe78.

### [#11491](https://github.com/enonic/app-contentstudio/pull/11491) · [enonic/app-contentstudio](https://github.com/enonic/app-contentstudio) — Dependencies widget opens filter instead of item list on mobile
**Does:** on mobile, "Show all incoming/outgoing dependencies" now opens the filtered item list with a removable dependency header instead of the filter panel. +908/−66, most of it tests.
**Found:**
- Nit — a double space in a class string, and a store imported past its module's public index (`SearchToggle.tsx:14`), which a refactor of that module would break silently. Both folded in.
**Done:** `FOLDED` into skjulestad's commit (96986601f, force-pushed with lease), `APPROVED`, `MERGED` (squash) as 9398d47.

### [#2793](https://github.com/enonic/app-users/pull/2793) · [enonic/app-users](https://github.com/enonic/app-users) — ID provider mode in the Users and Groups sections
**Does:** marks each ID provider as local, mixed, external or unavailable, and locks editing of users and groups that an external system owns — in the UI and with server-side write guards. +1283/−186.
**Found:**
- Blocker — a group key passed in the role list goes straight to XP's `addMembers`, which accepts any principal, so a user can be put into a locked provider's group past the guard. Outside judge; read in `user.source.ts:423` and XP's `AddMembersHandler`.
- Major — the groups step offers every group and pins none when provider modes fail to load (`UserEditorDialogGroupsStep.tsx:25`); confirmed by two judges.
**Done:** `CHANGES_REQUESTED`, 6 inline comments: https://github.com/enonic/app-users/pull/2793#pullrequestreview-5461908059

| PR | Now | Result |
| -- | --- | ------ |
| [ai-translator#686](https://github.com/enonic/app-ai-translator/pull/686) | merged | `APPROVED` `MERGED` 21cfe78 |
| [contentstudio#11491](https://github.com/enonic/app-contentstudio/pull/11491) | merged | `FOLDED` `APPROVED` `MERGED` 9398d47 |
| [app-users#2793](https://github.com/enonic/app-users/pull/2793) | open, waits on the author | `CHANGES_REQUESTED` |

### Needs your call
- **Q1. [#2793](https://github.com/enonic/app-users/pull/2793): should deleting users and groups also respect the provider mode?** Assumed: no, as before. → if yes: one more point for the author.

Writes on others' branches: contentstudio#11491 — amended to 96986601f, force-pushed with lease.
Not run: none. Rules broken: none.
Local: 3 clones back on their branches; `triage/*` kept in 2.

---

### Next
**Nothing waits on you except Q1; run `recheck` when #2793 moves.**
````

## The concise form

For `short`, or when the reviewer asks for a shorter version of a report already shown: no per-PR
sections, no run line, no dropped or skipped lines, the summary table links the bare number, and the
decision is a bold line with no heading. One bullet per pull request — the linked number, what it
does in a few plain words, its markers, and the one finding that drives them — then the summary
table, the questions in plain words, and the decision. A write on someone else's branch or a broken
rule still gets its own line above the decision.

At a gate, `short` never trims what the answer authorizes: every row that will post a review lists
each of its points as a sub-bullet, every `FOLD` row its exact changes, and *Dropped* stays.

````markdown
- **[#686](https://github.com/enonic/app-ai-translator/pull/686) translator model bump** — `APPROVE` `MERGE`. Swaps a retiring model; checked against the provider docs.
- **[#11491](https://github.com/enonic/app-contentstudio/pull/11491) mobile dependency view** — `FOLD` `APPROVE` `MERGE`. Two small fixes I'd fold in.
- **[#2793](https://github.com/enonic/app-users/pull/2793) ID provider mode** — `REQUEST_CHANGES`. A crafted role key still writes to a locked group.

| PR | Now | After |
| -- | --- | ----- |
| [#686](https://github.com/enonic/app-ai-translator/pull/686) | open, CI green | `MERGED` |
| [#11491](https://github.com/enonic/app-contentstudio/pull/11491) | open, CI green | `MERGED` |
| [#2793](https://github.com/enonic/app-users/pull/2793) | open, CI green | `CHANGES_REQUESTED` |

**Your call:** should deleting users respect the provider mode? I assumed no.

**Plan: merge two, send one back.**
````
