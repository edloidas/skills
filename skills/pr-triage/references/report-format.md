# Report format

One shape for every message this skill ends on: the proposal it waits on (Phase 3, Phase 6), each
deep review (Phase 4), and the final report. The reviewer may not have seen any earlier session, so each
pull request has to make sense from its own section, without opening it. Reports are written in the
language the reviewer writes to this session in; markers, code, and text quoted for posting stay
as they are.

## Shape

1. **Title and run line.** `## PR triage · <N> PRs in <M> repositories`, with the owner or
   repository after `PR triage ·` only when the run was scoped with `owner`, `repo` or `current`,
   and `· <K> yours` at the end when the own set is not empty. `<N>` counts the pull requests
   waiting on your review. Then one line saying how far to trust
   the report: what ran, the counts from triage to verdicts, and anything that degraded the run — no
   outside judge, a capped queue, a repository read without a clone, a check that did not run.
2. **One section per pull request**, in this order: ready to act, send back, deep review, held.
3. **Dropped** and **Skipped**, one line each, under those two headings.
4. **Summary table.**
5. **Your pull requests** — the own set, when it is not empty.
6. **Final report only:** one line each for *Writes on others' branches*, *Not run*, *Rules
   broken*, and *Local*.
7. **Needs your call** — the questions, last, so they are what the reviewer reads before replying.

Omit a part that would be empty. Nothing follows the questions: no plan sentence, no "shall I
proceed", no list of next steps to pick from.

## Action markers

Every standard action is written with one marker, in capitals inside backticks, and never in other
words: `APPROVE`, not "approve it" or "LGTM". Plain text may sit around a marker — the merge method,
the branch, the reason — or replace it where no marker fits.

| Marker | Proposed | In the final report |
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
| `**Since your review:**` | Recheck: what the author changed, how each of your points stands, and which threads wait on you |
| `**Found:**` | Each finding as a bullet — severity, the defect in plain words with the consequence, `pre-existing` or `made worse` when the pull request did not introduce it, then how it was confirmed — read, ran a command, observed in a browser — and where (`file:line`). `Nothing above minor` when that is the case |
| `**Check by hand:**` | When the change alters what a user sees or does: the 2-4 steps from triage that would show a regression. Omitted otherwise |
| `**Proposed:**` | The action markers, then what they write and where, how many settled threads it resolves, and what it waits on. A `FOLD` lists each exact change — `file:line`, before → after — because a reply naming the row authorizes a force-push of exactly those |
| `**Done:**` | Final report: replaces `**Proposed:**` with the outcome markers and their commit or review link |

A finding says what goes wrong and for whom, not only where: "a group key passed as a role adds the
user to a locked group, past the guard", never "unchecked cast in `applyMemberships`". Every
finding appears in exactly one section.

## Summary table

Right after the last pull request section. One row per pull request, the number linked:

| PR | Now | Proposed |
| -- | --- | -------- |
| the linked `repo#N` | its state today in a few words — `open`/`draft`, CI, your last verdict | the proposed markers, with a question id when the row depends on one |

In the final report the last column is headed *Result* and holds the outcome markers.

## Your pull requests

Under `### Your pull requests`, one table, grouped in the order *Needs you*, *Ready to merge*,
*Waiting*. These are never triaged, so there is no section per pull request:

| PR | State | Why |
| -- | ----- | --- |
| the linked `repo#N` and its title | the state from the queue's `SET` column | the columns that put it there, in words: "changes requested by bob, 2 open threads", "approved, CI green, clean", "no reviews yet" |

A *Ready to merge* row carries `MERGE` when the run has `merge` and the row is in the plan, and
`MERGED` with the commit in the final report. A *Needs you* row ends with the next step, run by the
reviewer: `pr-review <url>`.

## Needs your call

Each question is written so the reviewer can answer it without opening the pull request:

```markdown
**Q<n>. <the question, one short sentence>** [#N](url), <the part of it: file, feature or step, in the reviewer's terms>. <What the code does there now and what goes wrong, with the concrete case.> <What makes it a call rather than a finding: the trade-off, the policy it depends on, what the author said.>
- **<option>** (my pick) — <what happens to the row and to the author>; <why it is the pick, one clause>
- **<option>** — <what happens to the row and to the author>
```

The bold line is the question alone. Context follows it in plain text in the same paragraph — which
pull request and which part of it — then the description. Options sit under it as a list, two to
four, each saying what it does to the row. Mark one `(my pick)` only when there is a reason to
prefer it; a question with a safe default marks that default.

Keep only questions whose answer changes a row or what gets posted, at most five; the rest hold
their rows (`HOLD`) and are asked in the next report. A question the reviewer can answer from a
one-line option label belongs in a structured prompt instead, per SKILL.md's **Asking the User**.

## Dropped and Skipped

One line each — the claim and what refuted it, or the pull request and why it was not triaged. A
drop nobody can see reads as a finding nobody checked.

## A filled-in final report

Same shape and same three pull requests as the Phase 3 report example in SKILL.md's **Report**;
only the parts that change are shown. The run line is replaced by what was done, each section's
last line becomes `**Done:**`, the summary table's last column becomes the result, and the
final-only lines close it before the questions:

````markdown
Run: Acted: 2 merged, 1 changes requested · outside judge: codex · every write named in a reply

### [#686](https://github.com/enonic/app-ai-translator/pull/686) · … — Upgrade Gemini models
…
**Done:** `APPROVED` and `MERGED` (rebase) as 21cfe78.

### [#11491](https://github.com/enonic/app-contentstudio/pull/11491) · … — Dependencies widget opens filter instead of item list on mobile
…
**Done:** `FOLDED` into skjulestad's commit (96986601f, force-pushed with lease), `APPROVED`, `MERGED` (squash) as 9398d47.
### [#2793](https://github.com/enonic/app-users/pull/2793) · … — ID provider mode in the Users and Groups sections
…
**Done:** `CHANGES_REQUESTED`, 3 inline comments: https://github.com/enonic/app-users/pull/2793#pullrequestreview-5461908059

| PR | Now | Result |
| -- | --- | ------ |
| [ai-translator#686](https://github.com/enonic/app-ai-translator/pull/686) | merged | `APPROVED` `MERGED` 21cfe78 |
| [contentstudio#11491](https://github.com/enonic/app-contentstudio/pull/11491) | merged | `FOLDED` `APPROVED` `MERGED` 9398d47 |
| [app-users#2793](https://github.com/enonic/app-users/pull/2793) | open, waits on the author | `CHANGES_REQUESTED` |

Writes on others' branches: contentstudio#11491 — amended to 96986601f, force-pushed with lease.
Not run: none.
Rules broken: none.
Local: 3 clones back on their branches; `triage/*` and `fold/*` deleted.
````

## The concise form

For `short`, or when the reviewer asks for a shorter version of a report already shown: no per-PR
sections, no run line, no dropped or skipped lines, and the summary table links the bare number.
One bullet per pull request — the linked number, what it does in a few plain words, its markers,
and the one finding that drives them — then the summary table, and the questions last. `short`
shortens a question's context to one sentence, never drops it, and keeps its options as a list. A
write on someone else's branch or a broken rule still gets its own line above the questions.

In a report waiting on a reply, `short` never trims what a reply would authorize: every row that will post a review lists
each of its points as a sub-bullet, every `FOLD` row its exact changes, and *Dropped* stays.

````markdown
- **[#686](https://github.com/enonic/app-ai-translator/pull/686) translator model bump** — `APPROVE` `MERGE`. Swaps a retiring model; checked against the provider docs.
- **[#11491](https://github.com/enonic/app-contentstudio/pull/11491) mobile dependency view** — `FOLD` `APPROVE` `MERGE`. Two small fixes I'd fold in.
- **[#2793](https://github.com/enonic/app-users/pull/2793) ID provider mode** — `REQUEST_CHANGES`. A crafted role key still writes to a locked group.

| PR | Now | Proposed |
| -- | --- | -------- |
| [#686](https://github.com/enonic/app-ai-translator/pull/686) | open, CI green | `APPROVE` `MERGE` |
| [#11491](https://github.com/enonic/app-contentstudio/pull/11491) | open, CI green | `FOLD` `APPROVE` `MERGE` |
| [#2793](https://github.com/enonic/app-users/pull/2793) | open, CI green | `REQUEST_CHANGES` |

**Q1. Should deleting users also respect the provider mode?** [#2793](https://github.com/enonic/app-users/pull/2793), the delete action: editing a synced user is locked, deleting it is not.
- **Leave delete as is** (my pick) — the next sync recreates the user.
- **Lock delete too** — one more point for the author.
````
