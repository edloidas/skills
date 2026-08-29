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

**Only half of that is observed.** The reported half was checked against real pull
requests — `reviewRequests` empty, Copilot present in `latestReviews`. A bot actually
sitting in `reviewRequests` while it works has *not* been seen; that half is inferred
from the shape of the other. The whole `no / no` row rests on it, which is why the merge
path treats that row as unknown rather than as an answer. If a bot ever turns up in
`latestReviews` on a pull request where it never appeared as requested, the inference is
disproved: say so in the report and stop trusting this table.

| `reviewRequests` has a bot | `latestReviews` has a bot | Meaning | Wait |
| --- | --- | --- | --- |
| yes | no | Requested, still working | Yes |
| yes | yes | Reported, then re-requested by a new push | Yes |
| no | yes | Already reported | **None** — go straight to `pr-review` |
| no | no | Nobody is coming, *or* a pending bot this table cannot see | **None** on `PR only`; on `PR + merge` see below |

A reviewer counts as a bot when its `__typename` is `Bot`, when its login ends in
`[bot]`, or when it is `copilot-pull-request-reviewer` — Copilot's login, which carries
neither marker. Match all three; the login is the only one that catches Copilot.

A requested **human** reviewer is never a reason to wait. People answer in hours or days,
and this flow does not hold a branch open for that. Comments a human has *already* left
are worked in the same pass as the bots'.

## The confirm

GitHub adds an automatic review request within seconds of the pull request opening, not
instantly, so a single query at creation time can read `no / no` before the request lands.
Re-run the query **once, about 20 seconds later**. The confirm is not an optimisation to
drop: without it a request landing three seconds late prints as `No automated reviewers`,
which is a wrong report, not a saved wait. Twenty seconds is itself a guess at how fast
the request lands — another reason the merge path does not treat `no / no` as final.

That confirm is also the entire allowance for review apps that comment without ever
being requested. They are invisible until they speak, so there is nothing to poll for.

**Do not look anywhere else.** Copilot registers no check run, so scanning
`statusCheckRollup` for a review bot costs a query and finds nothing. Do not read
`.github/` for app config, and do not scan the repository's other pull requests to learn
what usually comments.

## The budget — `PR + merge` only

`PR only` never polls. Nothing downstream consumes the answer there, so a bot still
pending is reported as pending and the flow stops. Detection and its confirm still run:
a review that has *already* landed is worked, and that is the highest-value thing one
free query can buy.

On `PR + merge`: ten minutes from the pull request opening, polled about every 30
seconds. **Exit the moment no bot is left in `reviewRequests`** — not when one has
appeared in `latestReviews`. The two differ on the row that matters most: a bot that
reported and was then re-requested by a push is in *both* lists, so an exit keyed on
`latestReviews` is satisfied before the wait starts and round 2 never waits at all.

A `no / no` reading here is **unknown**, not nobody. Keep polling until the CI wait
resolves — which costs nothing, per the overlap below — and never merge with a bot
unresolved. A timeout is not a resolution: report which bot never answered and leave the
pull request open rather than merging through it.

Never extend the budget because a review "should" be coming, and never read silence as
approval. Silence is reported on `PR only` and blocks the merge on `PR + merge` — an
incomplete review is not permission to proceed, which is the whole reason this phase
sits before the merge.

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
