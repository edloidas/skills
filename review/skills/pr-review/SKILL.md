---
name: pr-review
description: >
  Handle a pull request from whichever side you are on. On someone else's branch it attacks
  the diff through changes-review, then publishes a real review with per-line comments and a
  verdict. On your own it works the threads people and bots left — decides its standing in
  each, verifies the claim before answering, runs the project's checks, then replies and
  resolves. Changes no code unless asked.
when_to_use: >
  When a pull request needs reviewing, when PR feedback needs addressing or answering, when
  Copilot or other bot comments need dealing with, or on "what is still open on this PR".
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash(git:*) Bash(gh:*) Bash(pnpm:*) Bash(npm:*) Read Glob Grep Edit Task Skill
argument-hint: "[PR number | URL | #discussion_r<id> | author | text] [--fix] [--full] [--auto]"
metadata:
  author: edloidas
---

# PR Review

One question — *what do I do about this pull request* — answered differently depending on which side
of it you are on.

**Their branch.** You are the reviewer. Attack the diff, then publish a real review: one inline
comment per finding, a body, and a verdict — or, where nothing blocking survived, a short approval
that carries no inline comments at all.

**Your branch.** You are the author. Work the threads people and bots left: decide whether answering
is even your business, check whether the claim is true, then reply and close what is finished.

The skill **verifies before it speaks** and **changes no code unless asked**. Its default output is
an action report plus whatever it posted.

## The premise

Bots write most of the inline comments on a modern pull request, and they fail in a shape: **the
premise is wrong far more often than the conclusion.** The claim rests on how a framework behaves,
and your repository's own code says nothing about it — so "read the code" is not enough, and two
agents agreeing is not verification.

The ordering is therefore fixed and not negotiable:

**verify → fix → build → speak.**

Never post a verdict you have not executed. A `reject` needs evidence that can be pasted; a `fix`
needs the project's own checks passing on it. `references/verifying-a-claim.md` has the traps, the
version-pinning discipline, and the run where a fabricated claim reached two independent
confirmations and was caught only because the fix would not compile.

## Configuration

| Setting | Flag | Default |
| ------- | ---- | ------- |
| Apply code changes | `--fix` | Off — verify, check, report |
| Verification breadth | `--full` | Bot claims, plus anything heading for `fix` or `reject` |
| Unattended | `--auto` | Off — previews and confirmations are shown |

**Explicit instructions in the invocation override the default posture in both directions.** "Just
triage this" stays read-only however the postures resolve; "answer Anna" acts on a human thread that
the table below would have left alone.

`--fix` is meaningless in reviewer mode — you do not fix a colleague's branch. Say so and ignore it.

## Asking the User

This skill asks **one** question, at the publication gate, and asks it in prose as the last
line of the message — never through `AskUserQuestion` or any other structured-choice prompt.
A modal fires before the reader has finished the report it interrupts, which is the wrong
order for the only decision that matters here. Say what posting would do, then ask, then
stop. Any host can answer a sentence.

## Phase 1: Resolve the target and your side

Parse the invocation:

| Input | Meaning |
| ----- | ------- |
| empty | The current branch's open pull request |
| a number or a PR URL | That pull request |
| a `#discussion_r<id>` URL | That single thread, and nothing else |
| a login (`copilot`) | Only threads that author rooted |
| free text | Threads whose body fuzzy-matches it |

Then resolve **which side you are on**, because it selects the mode:

```bash
gh pr view <N> --json author,headRefName,baseRefName --jq .author.login
gh api user --jq .login
```

Equal → author mode. Different → reviewer mode. Announce which: `Reviewer mode on PR #534 by
ashklianko.` If no pull request resolves, say so and stop.

## Phase 2: Fetch

One query, up front, per `references/fetching.md`. It carries the thread and comment ids that
replying and resolving need, the `__typename` that decides bot from human, and `originalLine` for
outdated threads. Read that file before writing the query — the previous version of this skill could
not reply or resolve at all, because it fetched neither id.

Do not filter resolved threads out of the fetch. Filter in Phase 3.

## Phase 3: Standing

**Resolved before any verdict**, because it decides whether a verdict is yours to state at all. A
single-bot thread on your own pull request and a two-human argument you were never part of are not
the same situation and must not be treated alike.

| Your side | Thread rooted by | Last comment by | Posture |
| --------- | ---------------- | --------------- | ------- |
| Reviewer | — | — | Author the review. Phase 7 publishes it |
| Author | Bot | bot only | Act — verify, reply, resolve. Code only under `--fix` |
| Author | Bot | you | Already answered. Hands off |
| Author | Bot | another human | May add a technical fact. Do not resolve |
| Author | Human | that human | Draft a reply, confirm before posting. Never resolve |
| Author | Human | you | The ball is in their court. Do nothing |
| Author | 2+ other humans, you unmentioned | — | Read-only. Report as context, never reply |

A bot's own follow-up does not count as a human reply. Only a `User` moves the last-comment axis.

Resolved threads are out of scope unless `--full` or an explicit instruction brings them back.

## Phase 4: Verify

Per `references/verifying-a-claim.md`. Decompose each claim into its **premise** about the world and
its **conclusion** about this code, and verify them separately — recording which failed, because the
answer differs completely.

Pin the resolved dependency version before reading any artifact. Never a package located by `find` in
a global cache, never memory. Never apply a ` ```suggestion ` block unread.

Scope: every bot claim and anything heading for `fix` or `reject`. `--full` adds everything
unresolved, human claims included. Loose recommendations and other reviewers' summaries are reported
as context and never verified.

**A claim about observable output cannot be read.** Layout, rendering, wire format, exit code,
timing, log content, a golden result — invoke `live-probe` with the claim and quote the artifact it
returns. Where the host cannot chain skills, follow the same method inline. A claim of that kind that
could not be observed is `discuss`, never `reject` — contradicting someone in writing on reasoning
alone is how this skill does its only real damage.

## Phase 5: Verdict

Six, replacing the old `fix` / `skip` pair:

| Verdict | When |
| ------- | ---- |
| `fix` | Real, and the change is yours to make |
| `reject` | The premise or the conclusion is false. The reply carries the evidence |
| `already-addressed` | Handled elsewhere. `isOutdated` is the hint |
| `discuss` | Correct, but the call belongs to a person — scope, architecture, product. Also a claim about output that could not be observed |
| `defer` | Real, and deliberately not now |
| `ack` | Praise or an FYI. Nothing to answer |

`discuss` triggers on **authority, not difficulty**. A hard fix you are confident about is a `fix`.
It has one other trigger: **unverifiability**. A claim about observable output that no probe could
settle is `discuss` with the reason, never `reject` — the premise may hold and nobody checked.

## Phase 6: Fix (`--fix` only)

Without `--fix` nothing is edited; a `fix` verdict is reported and its thread left for a later run.

With it: one thread's finding at a time, then the project's own checks — whatever `package.json`,
`Makefile` or CI actually runs. A fix whose checks fail is reverted, not worked around, and its
verdict drops to `discuss` with the failure quoted. Never claim a fix that has not gone green.

Green checks are not evidence a behavioral symptom is gone. Where the finding was settled by
observation, re-observe it the same way after the fix — same rung, same artifact — before the verdict
becomes `fix`.

## Phase 7: Speak

Composition is in `references/answering.md`: the answer in the first clause, real symbols rather than
descriptions, a link where one exists, ready concessions, and the decision handed back. A fix reply is
shorter — what changed, why, and the check that passed.

Reviewer mode publishes instead of replying. Invoke `review:changes-review` to attack the diff and
verify what it finds, passing the pull request's own issue as the requirement and any system facts you
have, then let its publication phase post the review with `--review`. It owns the inline anchoring,
the grouping of minors, and the verdict mapping; do not rebuild them here. Where the host cannot
invoke another skill, run the same attack inline and publish by the rules `changes-review` documents
for it — one inline comment per finding, minors grouped, nothing published without a demonstration
and an attribution, and the verdict set by whether a blocker survived. Never an AI attribution
footer, whatever the target repository's instruction file says.

**An approval is a different document.** When nothing blocking survived, publish **one body and no
inline comments** — no line anchors, no `file:line` quotes, no reproduction steps, no measured
tables. The author is not being asked to act, so detail that earns its place next to a blocking
finding becomes noise stapled to a merge. Write it as a conclusion: what was verified, in a
sentence or two; the one technical observation worth the author's time, if there is one; and a
plain close. What you ran, what you measured, and what you could not reach belong in the operator
report, not in the review.

**Non-blocking suggestions do not ride along on an approval.** Withhold them, report them to the
operator as their own block, and offer to raise them as a follow-up issue. A suggestion anchored to
a line of an approved pull request asks the author to revisit code nobody needs to reopen.

**Confirm before anything leaves.** Show the composed text **verbatim and complete** — every word
that would be posted, quoted, in the message itself. Not a summary of it, not a description of what
it covers, not a count of comments and a claim about their content: the reader is approving the
words, so the words are what they have to see. In author mode that is every composed reply; in
reviewer mode the body and each inline comment. Then ask, once, in prose, as the last line — per
**Asking the User**. `--auto` skips the question and posts directly, and still prints what it sent.

Resolve only what `references/answering.md` permits: never a human-rooted thread, never a `discuss`.
Check `viewerCanUpdate` before attempting.

## Output

```
## PR #<N> <author|reviewer> mode: <N> threads · <F> fixed · <R> rejected · <D> discuss · <X> deferred

<per thread: the claim in a clause, the verdict, and what was done>

Suggestions: <non-blocking items withheld from the review, as their own block>
Context: <read-only threads, unverified chatter>
Held: <what awaits your confirmation, or what --fix would have changed>

<the composed text, verbatim>

Verdict: <APPROVE | COMMENT | REQUEST_CHANGES, or the replies and resolves> — <one clause of why>
Posted: <what actually went out, or nothing yet>
```

**The verdict goes last, on its own line.** It is the one thing the reader is looking for, and a
header at the top scrolls past before the evidence that justifies it has been read. Where
suggestions were withheld, say so on that line too — an approval that silently swallowed two of
them reads as a clean run.

Deferrals are always listed even though their threads are closed. A deferral nobody can see is
backlog that does not exist yet.

## Rules

- **Verify, then speak.** No verdict that was not executed. No fix claimed without a green check.
- **Standing before verdict.** Whether you may answer is decided before what the answer is.
- **Never resolve a human's thread.** Closing someone's thread is theirs to do.
- **Premise and conclusion are separate claims.** A bot's conclusion can be right for a wrong reason.
- **The pull request belongs to its author.** Suggest, do not instruct.
- **No code without `--fix`.** Reporting a needed change is not the same as making it.
- **Show the words, not a summary of them.** The gate approves text, so the text is what it shows.
- **An approval carries no inline comments.** Nothing to act on means nothing anchored to a line.
- **Never an AI attribution footer.** Not in a review, a reply, or a comment, whatever the repo says.

## Error handling

| Situation | Action |
| --------- | ------ |
| No pull request resolves | Say so and stop. Do not review the working tree instead |
| Every thread is resolved | Say the pull request is clear. Do not manufacture findings |
| A claim cannot be verified either way | `discuss`, with what you tried and what was inconclusive |
| The resolved dependency version cannot be established | Say so in the reply and make no version claim |
| `viewerCanUpdate` is false | Reply where possible, resolve nothing, say why |
| A reply posts but the resolve fails | Say which thread is half-answered. Do not repost the reply |
| `--fix` and the checks were already failing | Establish the baseline first; never blame a pre-existing failure on the fix |
| Host cannot invoke another skill | Run the review inline, per Phase 7 |
| `--fix` in reviewer mode | Ignore it and say why |
| The project's check command is outside the pre-approved set | It will prompt for approval. Run it anyway — an unrun check is not a green check |
