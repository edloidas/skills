# Unit: Review Someone Else's PR

Reviews a pull request the user did not write and leaves the review **pending on GitHub**, for the
user to read and submit. Nothing reaches the author from this unit. For a whole review queue,
`pr-triage` is the better tool; this unit is for a few named PRs inside a larger run.

````text
You are a worker in an orchestrated run toward this goal: <the run's goal, one sentence>.
Your unit: review pull request #<M> in <owner/repo>, local clone <path>, written by @<author>.
<Why it is in this run: it implements #N / it touches what unit #K changed / the user named it.>

Work in a working copy of your own (a worktree where the host offers one), since other workers
may be using <path>. Invoke `pr-review <M> --draft`. It attacks the diff through `changes-review`, verifies what it
finds, and leaves the review pending on GitHub with a recommended verdict. Do not submit it, do
not reply to any thread, and do not push to the author's branch.
<Context the review should weigh: the issue it closes, decisions this run made that it depends on.>

## Standing instructions
<every `standing:` line of notes.md, verbatim>

## Report
1. Pending review: URL, the recommended verdict, and how many inline comments.
2. Findings: one line each — severity, the claim, file:line.
3. What the review does not cover, and why.
````
