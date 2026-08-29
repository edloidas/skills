# Waiting for Review Feedback

Phase 7 runs after the pull request exists. Its only job before handing off to
`pr-review` is deciding **whether anyone is coming, and how long to hold the door**.
The default is not to hold it at all.

## The one query

```bash
gh pr view <N> --json reviewRequests,latestReviews
```

Those two fields answer the whole question, because GitHub **moves** a reviewer between
them: a bot sits in `reviewRequests` while its review is pending, and the request
disappears the moment it reports, at which point it appears in `latestReviews`.

| `reviewRequests` has a bot | `latestReviews` has a bot | Meaning | Wait |
| --- | --- | --- | --- |
| yes | no | Requested, still working | Yes |
| yes | yes | Reported, then re-requested by a new push | Yes |
| no | yes | Already reported | **None** — go straight to `pr-review` |
| no | no | Nobody is coming | **None** — close the endgame |

A reviewer counts as a bot when its `__typename` is `Bot`, when its login ends in
`[bot]`, or when it is `copilot-pull-request-reviewer` — Copilot's login, which carries
neither marker. Match all three; the login is the only one that catches Copilot.

A requested **human** reviewer is never a reason to wait. People answer in hours or days,
and this flow does not hold a branch open for that. Comments a human has *already* left
are worked in the same pass as the bots'.

## The confirm

GitHub adds an automatic review request within seconds of the pull request opening, not
instantly, so a single query at creation time can read `no / no` before the request lands.
Re-run the query **once, about 20 seconds later**. Two consecutive `no / no` readings mean
nobody is coming: print `No automated reviewers` and close the endgame with no further
waiting.

That confirm is also the entire allowance for review apps that comment without ever
being requested. They are invisible until they speak, so there is nothing to poll for.

**Do not look anywhere else.** Copilot registers no check run, so scanning
`statusCheckRollup` for a review bot costs a query and finds nothing. Do not read
`.github/` for app config, and do not scan the repository's other pull requests to learn
what usually comments.

## The budget

Ten minutes from the pull request opening, polled about every 30 seconds. **Exit the
moment every pending bot has moved into `latestReviews`** — the budget is a ceiling, not
a duration, and most reports land inside a minute.

A timeout is a result, not a failure. Say which bot did not report and continue. Never
extend the budget because a review "should" be coming, and never read silence as
approval: on `PR only` the silence is simply reported; on `PR + merge` the merge proceeds
because the user authorized it, and the report says the bot never answered.

## Overlap the wait on the merge path

`issue-flow` Step 6 waits on CI before it merges, and CI on a real repository outlasts a
bot review. So on `PR + merge`, poll **while CI is running** and invoke Step 6 once the
poll resolves: its own wait then returns almost immediately, and the added cost is
`max(bot, CI)` rather than `bot + CI` — for a pipeline of more than a few minutes,
nothing at all. Only the remainder is ever a real delay, and the ten minutes still run
from the pull request opening, not from CI turning green.

## Rounds

Amending and force-pushing re-triggers a repository configured to request review
automatically, so a second batch of comments is the normal case. Run the detection again
after the push, confirm included, and let it decide — a repository that does not
re-request reads `no / no` twice and costs no second wait.

Run this phase at most **twice**. After the second round, list what is still open in the
report; a third loop trades wall clock for findings the pull request's own reviewers can
raise.

Carry the verdicts `pr-review` reached in round 1 into the report. It is blind to
previous rounds by design, so a claim it already rejected can come back — recognizing
that is this flow's job, not its.
