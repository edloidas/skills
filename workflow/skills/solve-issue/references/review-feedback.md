# Waiting for Review Feedback

Phase 7 runs after the pull request exists. Its only job before handing off to
`pr-review` is deciding **whether anyone is coming, and how long to hold the door**.

Two questions, two different endpoints. Do not try to answer both with one query — the
previous version of this file did, and the query it chose could not answer either.

## Question 1 — has a bot been asked?

The pull request's **timeline** carries a durable `review_requested` event for every
review request, however it was made: an automatic request, a `gh` call, or a human
assigning the bot by hand in the UI.

```bash
gh api --paginate "repos/{owner}/{repo}/issues/<N>/timeline" \
  --jq '[.[] | select(.event == "review_requested"
                      and .requested_reviewer.type == "Bot")
             | {login: .requested_reviewer.login, at: .created_at}]'
```

Non-empty → a bot was asked, and `created_at` says when. Empty, once the attach window
below has passed → **no automated reviewer has been requested on this pull request**. That
is an observation about a durable event log, not an inference from a snapshot, which is
what makes it safe to report.

## Question 2 — has it reported on *this* head?

```bash
head=$(gh pr view <N> --json headRefOid --jq .headRefOid)
gh api "repos/{owner}/{repo}/pulls/<N>/reviews" \
  --jq "[.[] | select(.user.type == \"Bot\" and .commit_id == \"$head\")] | length"
```

**Every clause here is load-bearing.** Counting all reviews instead breaks three ways:
a drive-by human review makes the count non-zero and reads as the bot reporting; on
round 2 the count already starts at 1, so a "0 → 1" test never fires; and a bot review
of the *previous* head satisfies the wait before it starts.

### Matching the bot

Use REST, and match on `.type == "Bot"`. Copilot's login is spelled differently on each
surface, and GraphQL exposes no bot marker for it at all:

| Surface | Copilot's login | Bot marker |
| --- | --- | --- |
| REST `pulls/<N>/reviews` → `.user` | `copilot-pull-request-reviewer[bot]` | `.type == "Bot"` |
| REST timeline → `.requested_reviewer` | `Copilot` | `.type == "Bot"` |
| GraphQL `latestReviews` → `.author` | `copilot-pull-request-reviewer` | none — `is_bot` is `null` |

That last row is why this file no longer uses `gh pr view --json latestReviews` for
detection, and why no login match is needed.

## The decision

| Bot requested (Q1) | Bot review at head (Q2) | Meaning | Action |
| --- | --- | --- | --- |
| yes | no | Asked, has not reported on this head | **Wait**, within the budget |
| yes | yes | Reported on this head | Go straight to `pr-review` |
| no | yes | Reported without a recorded request | Work it — and see the disproof below |
| no | no | Nobody has been asked — once the attach window has passed | **No wait** — see **No bot attached** |

A requested **human** reviewer is never a reason to wait. People answer in hours or days,
and this flow does not hold a branch open for that. Comments a human has *already* left
are worked in the same pass as the bots'.

### What would disprove this

The old table wrote down its own falsification condition, the field run tripped it, and
that is the only reason the mechanism was fixed rather than defended. Keep the habit.

**This table is disproved if a bot review appears in `pulls/<N>/reviews` whose request
never appeared as a `review_requested` timeline event.** That would mean the timeline is
not the complete request record, and the `no / no` row is unsafe again. Say so in the
report and stop trusting this file.

One thing here is **assumed, not observed**: that a re-request after a force-push writes
a *second* `review_requested` event rather than reusing the first. That is how GitHub's
event log behaves everywhere else, but it was not watched happening. Round 2 leans on it
— if a repository that visibly re-reviews shows no new event, this assumption is the
first thing to suspect.

### Never claim absence you did not observe

The report says what was checked and when:

> No automated reviewer was requested on this pull request (timeline checked at 14:02Z);
> none was attached by 14:03Z; merged when CI passed.

Never `No automated reviewers`. The old wording asserted a property of the repository
from a query that could not see one; the sentence above asserts only what was read.

## What not to look at

- **`reviewRequests` / the `requested_reviewers` endpoint.** A pending Copilot request is
  invisible in both — verified against a review watched in flight: the timeline recorded
  the request while `reviewRequests` stayed empty for the whole ~100-second window, then
  the review landed. Anything keyed on a bot *appearing* there never fires, and anything
  keyed on one *leaving* there is true before the wait begins. It answers "which standard
  requests are outstanding right now", which this flow never needs to ask.
- **`statusCheckRollup`.** Copilot registers no check run.
- **`.github/` app config, or the repository's other pull requests.** Not evidence about
  this one.

## The attach window

A repository that attaches Copilot automatically does so a few seconds after the pull
request opens, so Q1 read at once can say `no` for a bot that is about to be asked. Until
one minute after the pull request was created (`gh pr view <N> --json createdAt`), a `no`
is not an answer: re-run Q1 about every 15 seconds and decide when it turns `yes` or the
minute is up. The same window applies after every force-push in **Rounds**.

This flow requests no bot up front. It waits for one the repository attached, or that the
user or the repository's instruction file asked for. Re-requests after substantive fixes
belong to `pr-review`.

## The budget — both endgames

When Q1 says a bot was asked and Q2 says it has not reported: five minutes from the
request event, polled about every 30 seconds. **Exit when Q2 returns non-zero**, then work
its review. Wait with repeated short checks that keep the turn alive; a background wait
that ends the turn hands the pull request back with nobody watching it.

A bot still silent at five minutes is skipped, not waited out. On `PR + merge` the merge
goes ahead; on `PR only` the flow stops. Either way the report names the bot and the
times: `Copilot requested 14:02Z, no review by 14:07Z — merged without it.` A review that
lands later is a new round for whoever picks the pull request up, not a reason to hold
this one.

Never extend the budget because a review "should" be coming.

### Overlap the wait on the merge path

`issue-flow` Step 6 waits on CI before it merges, and CI on a real repository outlasts a
bot review. So poll **while CI is running**; Step 6 is still invoked only after the
review is worked and the deferrals are filed, but its own CI wait then returns almost
immediately. The added cost is `max(bot, CI)` rather than `bot + CI` — except on a round
whose fixes were pushed, which restarts CI.

## No bot attached

Q1 reads `no` both when a repository has no automated reviewer and when a person is about
to assign one by hand. No endpoint separates those, and this flow does not wait on intent:
with `no / no` once the attach window has passed, `PR + merge` merges when CI is green and
`PR only` stops. **Never default to waiting** — on a repository with no automated reviewer
that turns every run into a permanently unmerged branch. A person who wants a bot's review
asks for it before the run, and the request then shows on the timeline.

## Rounds

After the amend and force-push, run Q1 and Q2 again against the **new** head.

- A new `review_requested` event later than the push → a review is coming; wait, with a
  fresh five-minute budget.
- No new event once the attach window after the push has passed → nothing was
  re-triggered; proceed. A repository that re-requests
  automatically and one where a human assigns by hand are told apart here by what the
  timeline records, not by an assumption about how the repository is configured.

Q2's `commit_id` filter is what keeps this honest: the round-1 review is pinned to the
old head and cannot satisfy round 2.

Run this phase at most **twice**. After the second round, list what is still open in the
report; a third loop trades wall clock for findings the pull request's own reviewers can
raise.

Carry the verdicts `pr-review` reached in round 1 into the report. It is blind to
previous rounds by design, so a claim it already rejected can come back — recognizing
that is this flow's job, not its. The same applies to `defer`: a claim deferred in round
1 already has an issue filed against it, so carry the issue number forward and reference
it rather than filing a duplicate.

## Doubting Rejects

Phase 4.6, under `auto` only. Once per round, after the Fix / Note / Reject split and before
the Round 2 triggers are counted, invoke `doubt` on that round's Rejects. Each claim is the
reviewer's finding, verbatim, with the files it names — never your reason for rejecting it,
which is the reasoning `doubt` must not see.

| `doubt` on the finding | The Reject becomes |
| ---------------------- | ------------------ |
| *holds* | Fix |
| *holds only in a narrower case* | Fix, scoped to that case |
| *nobody can settle it* | Fix — uncertainty defaults to Fix |
| *true but not worth the fix* | Note |
| *falls* | Reject, standing, with `doubt`'s verdict beside it |

The Round 2 triggers and the closing line count the Rejects that stand. The Phase 6 summary
marks every converted one `overturned by doubt` in its Outcomes row, so no Reject
disappears from the report. Without `doubt`, the Rejects stand and the summary says
`doubt` was unavailable.

## Filing the deferrals

On `PR + merge` only, before the merge intent, and never when the user said not to file
follow-ups — SKILL.md Phase 4.6 → **Outcomes**. One `issue-flow` `"create an issue"`
invocation per `defer` in `pr-review`'s report:

- **Title** — the reviewer's claim, reduced to a title.
- **Body** — the claim quoted verbatim in a blockquote, the pull request number, and
  `pr-review`'s stated reason for deferring.

Put the issue numbers in the Phase 7 report block.

`pr-review` lists every `defer` even though it resolved those threads, and that list is
the handoff the merge destroys: the pull request closes and the resolved thread carrying
the deferral goes with it. Filing any earlier is impossible — `pr-review` owns those
threads and replies and resolves in one pass, so the in-thread reply cannot carry a number
that does not exist yet.

**Notes, under `auto` only.** Unattended, nobody reads the summary until the run is over,
so Notes are filed here alongside the deferrals, subject to the bar **Outcomes** states,
and their `filed: pending Phase 7` rows get their numbers. `doubt`
rules first: *falls*, *nobody can settle it*, and *true but not worth the fix* become
`declined` with that verdict as the reason; *holds only in a narrower case* is filed with
that narrowing in the body. A Note under the bar is `declined` with the bar it missed. An
attended run files no Note: one the bar would admit is `blocked: decision — file it or fix
it here?` under **Needs you**.
Notes naming the same file or mechanism go into one issue; the rest get one each. A
`filed: pending Phase 7` row that nothing files — no `doubt`, or `issue-flow` unreachable —
becomes `blocked: decision — file it or fix it here?` under **Needs you**.
Body: the Note quoted verbatim in a blockquote, `doubt`'s verdict, the pull request
number, and the reviewer that raised it.

Nothing deferred files nothing. `PR only` files nothing either — the pull request stays
open with the report in front of the user, and each `defer` is `blocked: decision` there.
Where the host cannot reach `issue-flow` to file, do **not** merge silently: report each
deferral as `blocked: issue-flow unreachable` and leave the pull request open, because
that is the state the merge was going to destroy.
