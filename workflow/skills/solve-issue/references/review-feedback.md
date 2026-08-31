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

Non-empty → a bot was asked, and `created_at` says when. Empty → **no automated reviewer
has been requested on this pull request**. That is an observation about a durable event
log, not an inference from a snapshot, which is what makes it safe to report.

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
| yes | no | Asked, has not reported on this head | **Wait** |
| yes | yes | Reported on this head | Go straight to `pr-review` |
| no | yes | Reported without a recorded request | Work it — and see the disproof below |
| no | no | Nobody has been asked | **No wait.** On `PR + merge`, offer the seam below |

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
> none had reported by 14:12Z.

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

## The budget — `PR + merge` only

`PR only` never polls. Nothing downstream consumes the answer there, so a bot still
pending is reported as pending and the flow stops. Q1 and Q2 still run once: a review
that has *already* landed is worked, and that is the highest-value thing two free queries
can buy.

On `PR + merge`, when Q1 says a bot was asked and Q2 says it has not reported: ten
minutes from the request event, polled about every 30 seconds. **Exit when Q2 returns
non-zero.** A timeout is not a resolution — report which bot never answered and leave the
pull request open rather than merging through it.

Never extend the budget because a review "should" be coming, and never read silence as
approval. An incomplete review is not permission to proceed, which is the whole reason
this phase sits before the merge.

### Overlap the wait on the merge path

`issue-flow` Step 6 waits on CI before it merges, and CI on a real repository outlasts a
bot review. So poll **while CI is running** and invoke Step 6 once the poll resolves: its
own wait then returns almost immediately, and the added cost is `max(bot, CI)` rather
than `bot + CI` — for a pipeline of more than a few minutes, nothing at all.

## The one thing no API can see

Q1 reads `no` both when a repository has no automated reviewer and when a human is about
to assign one by hand and has not yet. No endpoint can separate those: the difference is
intent in a person's head. On `PR + merge` with `no / no`, ask, per **Asking the User**:

- **Option 1** — header `Merge now`, label `Merge without review` `(Recommended)` — `No automated reviewer was requested. Merge once CI is green.`
- **Option 2** — header `Assign`, label `Pause, I'll assign one` — `Hold here. Assign a reviewer, then say go — I'll re-check the timeline and wait for the review.`

On resume, re-run Q1 rather than trusting the answer: a request that was never actually
made leaves no event, and holding the merge for a review nobody asked for is the same
failure in the other direction. If no new event appears, say so and re-ask.

Where the host cannot prompt, take Option 1. **Never default an unattended run to
waiting** — on a repository with no automated reviewer that turns every `PR + merge` into
a permanently unmerged branch, which is a worse outcome than merging without a review
nobody was ever going to give.

## Rounds

After the amend and force-push, run Q1 and Q2 again against the **new** head.

- A new `review_requested` event later than the push → a review is coming; wait.
- No new event → nothing was re-triggered; proceed. A repository that re-requests
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
