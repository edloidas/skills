---
name: solve-issue
description: >
  End-to-end GitHub issue workflow: analyze the issue, plan and implement, verify with
  available tests/build/lint and an optional live observation, simplify, audit the tests it
  added, attack the change with parallel adversarial reviewers and fix what they find, trim
  comments and artifacts, then choose a push / PR / merge endgame — holding the merge while
  Copilot and other automated reviewers report, and answering and resolving their threads.
  The lifecycle's git and GitHub writes are delegated to `issue-flow`, the review threads to
  `pr-review`.
when_to_use: >
  When a single autonomous command is wanted for an issue already considered simple enough to
  delegate end-to-end — `/solve-issue 69`, or a bare `/solve-issue` to be asked which issue
  first.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash(git diff:*) Bash(git status:*) Bash(git log:*) Bash(gh pr view:*) Bash(gh api:*) Bash(sleep:*) Bash(jq:*) Bash(rm:*) Bash(ls:*) Read Edit Write Glob Grep Task Skill AskUserQuestion
argument-hint: "[issue-number] [auto]"
metadata:
  author: edloidas
---

# Solve Issue

Runs the full issue workflow in one command; **Flow Overview** below is the phase list.
Designed for issues the user already judged simple. When uncertainty appears, pause and
ask.

**Mutation class: writes to external services.** It edits the working tree, and through
`issue-flow` it commits, pushes, opens pull requests, files issues, and merges.

**This skill owns engineering judgment only.** Every git and `gh` write in the
lifecycle — issue selection, branch, snapshot, commit, squash, push, PR, merge — belongs
to `issue-flow`, and its rules stay its own: do not restate its commit format or squash
rules here, and do not run a write its loaded instructions did not direct. The one write
it does not own is the pull request's own review threads: `pr-review` posts and resolves
those in Phase 7.

Read-only `git diff` / `git status` / `git log`, and `gh pr view` plus `gh api` **GET**s,
are yours — for scoping and for reading review state. `allowed-tools` cannot express a
method restriction, so its `gh api` grant is wider than that: this sentence is the limit,
not the declaration. A `gh api` call with `-X`, `-f`, or `--input` is a write — it belongs
to `issue-flow`.

## Conventions

### Asking the User

Every question in this skill is written as `AskUserQuestion` options. Use that tool where
the host offers it, or the host's nearest structured-choice equivalent. Where the host has
neither, ask the same question in normal chat as a numbered list of 2–5 options —
recommended first, one short line of description each — and wait for the user to reply
with a number.

Every gate defaults to proceeding, so a host that cannot prompt still completes the flow.
A user who picks a `Stop` option exits the run cleanly, leaving local state as it stands.
The Phase 6 endgame is the one exception — always asked, unless `$ARGUMENTS` carries `auto`.
That is an unattended run: take the `(Recommended)` option at every gate, this one and the
Phase 7 seam question included. A bare `auto` with no issue number still asks Phase 0.

### Delegating to Other Skills

This skill is an orchestrator: it invokes `issue-flow`, `issue-analyze`, `changes-review`,
`tests-audit`, `live-probe`, `code-cleanup`, and `pr-review` rather than reimplementing
them. "Invoke `<name>`" means hand control to that skill however the host chains skills.
Where chaining means loading its instructions into *this* context, it means following
them — its commands included. They stay its rules, not yours.

**`issue-flow` and `issue-analyze` are hard prerequisites**: the lifecycle's writes live
in one and the scope analysis in the other, so a host that cannot invoke another skill
cannot run this one. Stop with `solve-issue needs to invoke issue-flow and issue-analyze;
this host cannot chain skills.` rather than reimplementing the lifecycle inline. The rest
are graceful — each call site names its inline fallback in two lines or less.

### Editing Files

Apply targeted edits per hunk; never rewrite a whole file to change part of it — in
implementation, simplification, advisor fixes, the comment pass, and Phase 7 fixes alike.

### Tracking Progress

Where the host has a task list, put one entry per **Changes** item in it and update
entries as you go. Where it does not, keep the printed numbered Changes list as the
tracker and state which item you are on before starting it. Either way, progress is
visible per item — never a single opaque "implementing" step.

## Flow Overview

| Phase | Step                              | Asks user?                              |
| ----- | --------------------------------- | --------------------------------------- |
| 0     | Resolve issue number              | Only if `$ARGUMENTS` is empty           |
| 1     | Analyze via `issue-analyze`       | No                                      |
| 2     | Plan + create branch              | Only if plan is genuinely uncertain     |
| 3     | Implement                         | Only on hard blockers                   |
| 4     | Verify (checks + optional probe)  | Only to opt into a live observation     |
| 4.4   | Subtle simplification pass        | No                                      |
| 4.5   | Tests audit (only if tests moved) | No                                      |
| 4.6   | Advisor round(s) + apply fixes    | No                                      |
| 5     | Comment cleanup + commit          | No                                      |
| 6     | Summary + choose endgame          | Always — unless `auto` (takes Option 1) |
| 7     | Review feedback, then merge       | Through `pr-review`'s own gate          |

## Phase 0: Resolve Issue

If `$ARGUMENTS` holds an issue number or GitHub issue URL, use it and skip to Phase 1.
If it carries no number, ask, per **Asking the User**:

- **question**: "No issue number provided. How should I pick one?"
- **Option 1** — header `Next issue`, label `Let issue-flow pick` `(Recommended)` — `Rank the backlog and recommend the most relevant open issue.`
- **Option 2** — header `Manual`, label `Stop and ask` — `Exit so you can re-run with an explicit issue number.`

- Option 1 → invoke `issue-flow` with intent `"pick an issue"`. Its Step 0 ranks the
  backlog, lets the user choose, and chains into `issue-analyze` on the selection —
  continue from Phase 2 with the number and the analysis it returns. Two outcomes are not
  a selection: the user picks `None`, or the branch it short-circuited on carries no issue
  number. Both end the run — stop and say which. Phase 5 commits under the issue title, so
  never continue without one.
- Option 2 → print `Re-run with an issue number, e.g. /solve-issue 42.` and stop.

Two preconditions stop the run before anything else: `gh` unauthenticated, which
`issue-flow` or `issue-analyze` reports — relay it — and no git repository, which stops
with `Not inside a git repository.`

## Phase 1: Analyze

Invoke `issue-analyze` on `<N>`. Do not duplicate its work inline — capture the Scope
Analysis and Implementation Tasks it emits. It is a prerequisite, not a nice-to-have: it
resolves the issue title this flow commits under, and the blockers Phase 1 stops on.

Stop conditions from the analyzer:
- Issue is closed → print its status line and stop.
- Issue has an open blocker → print the blocker and stop. Do not implement
  through an open blocker without explicit user approval.
- Issue is assigned to another user (`> Note:` line) → continue, but flag the
  condition in the final summary.

End Phase 1 with one line: `Phase 1: #<N> "<title>" — <N> tasks, <N> blockers.` Then go to
Phase 2. Nothing is edited before the plan is printed.

## Phase 2: Plan

Before drafting, list every file the Changes list will name plus its immediate callers,
and open all of them in one batch. A plan naming a file nobody read is a guess. Do **not**
edit anything yet.

Then print the plan inline, in the exact structure `references/plan-format.md` specifies —
goal, numbered file-level Changes, explicit out-of-scope, risks or decisions. That file
also carries the rules the body has to satisfy. **Never write a plan file.**

After printing it, set up progress tracking per **Conventions → Tracking Progress** — one
entry per Changes item.

### When to pause for approval

Default: proceed to Phase 3 immediately after printing the plan. The printed plan is the
checkpoint, and the user can interrupt if they disagree — do **not** ask for approval on a
simple issue. `references/plan-format.md` lists the conditions that override that default
and the shape of the one question to ask when any of them fires.

### Create branch

A dirty working tree on the base branch stops the run here: `Uncommitted changes on base
branch — resolve first.`

Otherwise invoke `issue-flow` with intent `"start work on #<N>"`. That runs its Step 2,
which checks out `issue-<N>` off the correct base branch and updates the project board to
"In Progress" when available. If `issue-<N>` already exists, let `issue-flow` handle the
switch-vs-recreate prompt.

Record the `Fork:` SHA from its Step 2 report — later phases diff against it to scope
verification and pass it to the reviewers. Use `Fork:`, not `Base:`: `Base:` is a branch
*name*, and an epic branch that exists only on the remote fails `git diff <name>..HEAD`
with `unknown revision`. A SHA always resolves.

**Every phase that scopes by the fork reads the working tree, never `<fork>..HEAD`.** The
form is `git diff --name-only <fork>` plus `git ls-files --others --exclude-standard`,
stated once here so no phase or reference restates it. Snapshots are optional until Phase
4.6, so on a run that never took one `HEAD` still *is* the fork and that range is empty
while the changes sit unstaged — silently scoping a phase to nothing.

Do not detect the base yourself; `issue-flow` owns it, and its `detect-base.sh` handles
the `epic-*` cases a naive `origin/HEAD` lookup gets wrong. Entered on an existing branch
with no Step 2 report, ask `issue-flow` for the fork point.

End Phase 2 with one line: `Phase 2: branch issue-<N> off <base>, fork <sha>, <N> changes
planned.`

## Phase 3: Implement

Work through the tracked Changes items sequentially. Mark each one started when you begin
it and done as soon as it is done — no batching.

For a checkpoint mid-implementation, invoke `issue-flow` with intent `"snapshot"` — its
Step 3 snapshot mode freezes the tree into a content-free `wip:` commit. Phase 5 squashes
those away. Do **not** push between tasks.

If a task hits a hard blocker (missing credentials, external service down, decision
required), stop and ask the user.

End Phase 3 with one line: `Phase 3: <N>/<N> changes implemented, <N> files touched.` Then
go to Phase 4 — do not run the project's checks ad hoc as you go; Phase 4 selects them.

## Phase 4: Verify

Detect the verification set from `package.json` + repo conventions. Do not
skip verification on "simple" changes.

### Choosing what to run

`references/verification-set.md` has the script groups, the runner-from-lockfile rule,
and which groups the changed file set selects. Scope it with the `Fork:` SHA recorded in
Phase 2, not a branch name.

A repo that declares nothing runnable is not a pass: report verification as `unverified`
and name what was missing, rather than inventing a command the project never declared.

### Observe it running (opt-in)

Checks prove the change compiles and that nothing already covered broke. They do not prove
a claim about **observable output** — layout, rendering, wire format, exit code, timing,
log content, a golden result. Where the issue asked for a change of that kind, ask, per
**Asking the User**:

- **Option 1** — header `Skip probe`, label `Skip observation` `(Recommended)` — `Checks cover this scope.`
- **Option 2** — header `Observe`, label `Run and observe` — `Run it the way this project declares and read the result.`

The default is to skip: starting things is slow and leaves an artifact to clean up. On
opt-in, invoke `live-probe` with the behavior the issue asked for; it reads the project's
declared way to run and observe from the instruction layer first (`CLAUDE.md`, `AGENTS.md`,
rules files), then the repo's declared commands, and reports `unverified` rather than
inventing one. Expect **one** such tool, not a matched pair. Where the host cannot chain
skills, follow the same method inline.

### On failure

If any verification step fails:

1. Go back to Phase 3, fix the cause, and re-run **only** the failing check.
2. If the same check fails twice after two fix attempts, stop and hand back to the user
   with the failure output. Do not proceed past Phase 4 with failing verification. Do not
   rationalize skipping it.

### Ending the phase

Phase 4 is over when every check the verification set selected is green. End it with one
line naming every group, including the ones that did not run and why: `Phase 4: type-check
ok, unit tests ok (<N> passed), build ok, lint not configured — observation skipped.`

Then stop. Do not re-run the whole suite on top of the selected set, do not add a check
the set did not select, and do not re-read the diff for a second opinion. Phase 4.6 is
where the change gets attacked, by reviewers who are not you.

## Phase 4.4: Simplify

Run this **before** the advisor round, so the reviewers attack the code that will actually
ship. A simplification applied after review ships unreviewed.

Dispatch one subagent over the changed files with a single instruction: apply subtle,
behavior-preserving simplifications against the bar below, and nothing else. If the host
has no subagent facility, run the same instruction inline.

### The simplification bar

Apply only when **all** hold:

- Behavior is provably unchanged
- The change is contained to a single function or a local symbol
- No public export, API shape, or file layout is touched
- It makes the code shorter *and* clearer, not merely shorter

Anything heavier — splitting functions, reshaping control flow, extracting utilities,
renaming exported symbols — is **not applied**. Record it for the Phase 6 summary and move
on: a refactor that is merely nice is out of scope for an issue the user called simple.

Re-run the Phase 4 checks the simplifications could plausibly break. Revert anything that
fails rather than fixing around it — behavior-preserving was the bar, and a failing check
is proof it was not met.

End Phase 4.4 with one line: `Phase 4.4: <N> simplifications applied, <N> reverted, <N>
recorded as out of scope.` Then stop — one pass only. A second pass over the result is how
a subtle simplification turns into a refactor nobody reviewed.

## Phase 4.5: Tests Audit

Take the changed test files from the working tree, per **Phase 2 → Create branch**.
Skip this phase only when that set carries no test file.

Otherwise dispatch a plain subagent and have it invoke `tests-audit` over those files. Its
brief is the changed test paths and the code under test and nothing else — not the plan,
not what you were trying to do: its gate asks which promise each test pins and what
dumbest implementation still passes it, and your justification is the one thing that would
let a weak test through. Where the host has no subagent facility, run it inline under the
same restriction. `tests-audit` is a skill, not an agent type, so the subagent is a general
worker that loads it; asking the host for an agent named after the skill fails. It runs
**before** the advisor round for the reason Phase 4.4 does, and it earns its place there by
running the suite — order dependence and flakiness are invisible to anyone reading only
the diff.

`tests-audit` reports and never edits, so applying its verdicts is this phase's job.
`references/tests-audit-pass.md` has which verdicts to apply against a test this branch
wrote versus one it merely lives beside, and the gate to run inline when the skill is
not installed.

The rule that never bends: a tightened assert that now fails is either the defect the
loose one was hiding — fix it, that is the payoff — or a bad tightening, in which case
revert that assert. Never loosen it back to make the suite green.

End Phase 4.5 with one line: `Phase 4.5: <N> tests audited — <N> tightened, <N> rewritten,
<N> deleted, <N> noted.` Then stop. Do not widen the audit to tests this branch never
touched; a verdict on one of those is a Note for Phase 6, not work for this issue.

## Phase 4.6: Advisor Round

Independent reviewers attack the change in parallel; the findings are then triaged and
fixed. This always runs once verification is green.

The review itself belongs to `changes-review`. This phase owns only workflow policy:
freezing the diff, triaging findings, and deciding whether to run a second round. Do not
duplicate the reviewer prompts here, and do not invoke `consilium` — that board ranks
candidate approaches and has nothing to say about whether a finished diff is correct.

### Freeze the diff first

Every reviewer must see the same change set. Before dispatching, delete the cruft listed
under Phase 5 → Remove cruft — the snapshot stages everything, so scratch files and
screenshots would otherwise be baked in where Phase 5's untracked-file check can no longer
see them.

Then, if the tree is dirty, take a snapshot per **Phase 3** — `issue-flow` with intent
`"snapshot"`.

Each round freezes again — round 2 must snapshot the round-1 fixes before dispatching, or
the reviewers re-review the diff they already saw. Round 2 and later also pass
`--mode simple` with the previous round's snapshot as the base, so the reviewers attack
the fix rather than re-reading the whole branch to check a two-line change.

Carry your own list of findings you accepted rather than fixed. The reviewers are blind to
previous rounds by design, so an accepted decision comes back every round — recognizing it
is your job, not theirs.

### Run the review

Invoke `changes-review` with `--base <fork>` and `--issue <N>`, using the `Fork:` SHA
recorded in Phase 2 — it resolves as a rev where a branch name may not. It dispatches the
reviewers, re-attacks its own findings — verification is on by default for a `--base` run
— and returns what survives. It changes nothing.

Pass **no other context**. Not the Phase 2 plan, not the Risks/decisions section, not a
summary of what you were trying to do, not the previous round's findings or how you
triaged them. The skill's entire value is that its reviewers are blind to your reasoning;
handing it a summary destroys that.

If `changes-review` is not installed, note that in the Phase 6 summary, skip this phase,
and go to Phase 5. Do not hand-roll a reviewer round in its place.

### Triage and fix

Classify every returned finding:

| Class      | Meaning                                                          | Action                    |
| ---------- | ---------------------------------------------------------------- | ------------------------- |
| **Fix**    | Real defect or a genuine requirement gap                          | Apply now                 |
| **Note**   | Valid but out of scope for this issue                             | Report in Phase 6         |
| **Reject** | Wrong, or the reviewer lacked context that makes the code correct | Report in Phase 6         |

Rules that keep triage honest — you are judging reviews of your own work, and the pull
toward dismissal is real:

- **Uncertainty defaults to Fix.** If you cannot show a finding is wrong, it is not rejected.
- **A Reject must name the specific context the reviewer lacked** — the file it could not
  see, the invariant it did not know. "I don't think that's right" is not a rejection.
- **Rejects survive verbatim.** Phase 6 carries the reviewer's own wording, not your
  paraphrase of it. The user grades the rejection, not your summary.

Apply the Fix items, then re-run the Phase 4 checks the fixes could plausibly break.
Verification must be green again before continuing. If a check the fixes broke still fails
after two attempts, revert those fixes, list them as Notes, and go to Phase 5.

### Round 2

Run a second round if **any** of these hold:

- The fixes touched a file that was not in the round-1 diff
- The fixes changed more than ~30% of the round-1 changed-line count
- You rejected any intent-reviewer finding
- You rejected more than half of all findings

The last two matter because rejects do not change the diff, so a wrongly rejected bug is
invisible to a size-based trigger. A high reject rate is the signal that the implementer
is grading itself generously.

Otherwise stop at one round. **Hard cap: two rounds.** If round 2 surfaces another large
batch, do not run a third — apply the clear fixes, list the rest as Notes, and let the PR
review catch them.

End each round with one line: `Phase 4.6 round <N>: <N> findings — <N> fixed, <N> noted,
<N> rejected.` A round ends only in one of three states: no findings, findings triaged
with the Fix items applied and verification green, or the cap reached. A description of
what a further round would attack is not a state — either run it or go to Phase 5.

## Phase 5: Cleanup + Commit

### Trim comments

Invoke `code-cleanup --comments-only`, scoped to the change — it removes comments that
restate the code, compacts genuine gotchas to a line or two, and surfaces design rationale
for the body. This is the step that stops verbose AI commentary from reaching the commit.

`--comments-only` is deliberate — **no code changes at commit time.** Any simplification
opportunity belongs to Phase 4.6, where it was reviewed. Carry suggested refactors into
the Phase 6 summary as Notes; do not apply them here.

Its **Suggested for commit message** section is an *input* to the commit body — it answers
why the code is built the way it is, which is the first thing the body has to establish.
Pass it along under Commit below; `issue-flow` folds it into that paragraph rather than
tacking it on at the end.

If `code-cleanup` is not installed, do the comment pass inline: delete comments that
narrate what the code already says, that repeat what a nearby comment carries, or that
point at an issue or PR instead of stating the fact. Keep non-obvious gotchas at one to
two lines. Leave documentation comments and `HACK`/`FIXME`/`TODO` markers alone.

### Remove cruft

Delete anything that should not ship with the commit:

- Plan and scratch files under `.claude/plans/`, `.claude/plan/`, or `docs/superpowers/` —
  gitignored working artifacts. Only files this run created; never a config directory.
- Temp files under `tmp/` or `.tmp/` at the repo root created during this run
- Captured probe artifacts — screenshots, traces, dumps — wherever the instruction layer
  puts them. Nothing this run captured ships in the commit, a retained frame included

Use `git status --short` to sanity-check that no untracked scratch files are about to be
staged, and that every intended deletion shows up.

### Commit

Invoke `issue-flow` with intent `"commit #<N>"`. Its Step 3 squashes the branch to one
commit, writes the subject and body, and reports the result. It owns the subject format,
the body, and the squash rules for every `wip:` snapshot Phase 4.6 created — do not
restate any of them here, and do not run the git commands yourself.

Pass along, as context for the commit body:

- The issue title and number, so the subject can be built.
- The design rationale `code-cleanup` pulled out of the source, if any — that text is why
  the comment pass could delete it, and it answers the body's first question. It is not a
  block to append at the end.

Capture the short SHA and subject from Step 3's report for the Phase 6 summary. If Step 3
comes back with a dirty tree or more than one commit, re-invoke it rather than fixing the
history here. The endgame pushes the commit, not the working copy.

End Phase 5 with one line: `Phase 5: <N> comments trimmed, <N> cruft files removed,
committed <short-sha> <subject>.` Then stop. Nothing leaves the machine until Phase 6
asks — no push, no pull request.

## Phase 6: Summary + Endgame

Print the summary `references/report-format.md` specifies — what changed, what was
verified, what the tests audit moved, what the advisors found, and the commit. That file
carries the shape and a filled-in example of it.

Never omit a Reject: a rejected finding the user never sees is the one failure mode this
whole phase is built to prevent, and Phase 4.6 requires the reviewer's own wording.

Then ask, per **Asking the User**:

- **question**: "What's next for this commit?"
- **Option 1** — header `PR + merge`, label `Push, PR, auto-merge` `(Recommended)` — `Push, open a PR, answer the automated reviewers, file an issue for anything deferred, merge once no reviewer is left unresolved.`
- **Option 2** — header `PR only`, label `Push and open PR` — `Push, open a PR, answer any review already in, stop before merge.`
- **Option 3** — header `Push only`, label `Push the branch` — `Push the branch. No PR.`
- **Option 4** — header `Nothing`, label `Leave it local` — `Keep the commit local. No push.`

Route via `issue-flow`:

| Choice     | `issue-flow` intent                           | Then                       |
| ---------- | --------------------------------------------- | -------------------------- |
| PR + merge | `"push and open PR for #<N>"` — Steps 4 and 5 | Phase 7, then Step 6 merge |
| PR only    | `"push and open PR for #<N>"` — Steps 4 and 5 | Phase 7, then stop         |
| Push only  | `"push #<N>"` — Step 4                        | Stop                       |
| Nothing    | Stop — commit stays local                     | —                          |

**The merge is not part of the endgame invocation.** `PR + merge` opens the pull request,
hands to Phase 7, and merges only after the automated reviewers have had their window.
Asking `issue-flow` for `"push, PR, and merge"` in one intent merges past them. Let it
handle the per-step questions it already owns — squash confirmation, reviewer selection,
merge pre-checks — and do not duplicate those prompts here.

### Do not stop at "PR created"

Both PR endgames end with a mergeability verdict, not just a PR URL. `issue-flow` Step 5
produces a `Mergeable:` line — report it. Do not claim a pull request is ready without it,
and if it comes back `CONFLICTING` the flow is not done: rebase, force-push, re-check,
report the resolved state. Neither path is finished at Step 5; both continue into Phase 7.

End Phase 6 with one line: `Phase 6: <endgame chosen> — PR #<M>, Mergeable: <state>.`

## Phase 7: Review Feedback

Runs on both PR endgames. Skipped for `Push only` and `Nothing`.

**Detect, then decide whether waiting buys anything.** A bot is *expected* when the pull
request's timeline records a bot `review_requested` event, and it has *reported* when its
review appears against the current head SHA. A review already in is worked on either
endgame; only `PR + merge` ever polls for one that is not.

**Report what was observed, never absence you inferred.** `No automated reviewers` is a
claim about the repository that no query supports; "no bot review was requested on this
pull request, checked at `<time>`" is a fact about a durable event log.
`references/review-feedback.md` has both queries, the decision table, the bot-matching
rule, the budget, the one question no API can answer, and what would disprove any of it.

Then invoke `pr-review <N> --fix`, which owns the step: author-side standing, verifying
each claim's premise separately from its conclusion, the six verdicts, the reply, the
resolve. Do not re-triage its findings or restate its rules. On `PR + merge` add `--auto`
— which posts unattended on bot-rooted threads only, holding any human thread as an
unsent draft — plus the instruction to publish nothing until the fixes are pushed, since
a reply naming a landed fix is false the moment it posts otherwise and its thread is then
resolved on a claim that never became true. The order is fix, check, push, publish.

Code that `--fix` applied is uncommitted work on the squashed commit. It runs the
project's checks per fix, so re-run only the wider Phase 4 set once over the final tree,
then invoke `issue-flow` with intent `"amend and push #<N>"`, keeping the message
verbatim. Skip the amend when nothing changed: an all-`reject` round would force-push an
identical tree, re-trigger CI and the reviewers, and buy a second round for nothing.

After the push, run both detection queries again against the new head, per
`references/review-feedback.md` → **Rounds**. Run this phase at most **twice**.

### File the deferrals before merging

On `PR + merge` only. Before the merge intent, invoke `issue-flow` with intent `"create an
issue"` for each `defer` in `pr-review`'s report, and put the numbers in the report.
Choosing `PR + merge` is the approval — this is the one mutation with no gate of its own.
`references/review-feedback.md` → **Filing the deferrals** has what goes in each issue, why
filing any earlier is impossible, and what to do when the host cannot reach `issue-flow`.

### Report and close

Append the **Review feedback** block `references/report-format.md` specifies — including
what the fixes changed, because the merge ships code the Phase 6 summary did not describe
— then close the endgame:

- **PR + merge** — invoke `issue-flow` with intent `"merge #<N>"`, once no reviewer is
  left unresolved. That is this phase's half of the gate; Step 6 supplies the other half
  by waiting on CI. A bot that timed out counts as unresolved: report it and leave the
  pull request open rather than merging through it. A human thread held for a person does **not** block
  the merge — it can never be resolved, so waiting on it has no achievable meaning.
- **PR only** — print the open-thread state and stop.

If `pr-review` is not installed, list the open threads with their authors and claims and
stop there. Do not hand-roll replies: this skill carries no verification discipline for
someone else's claim, and an unverified rejection posted in public cannot be taken back.

End Phase 7 with one line: `Phase 7: <N> threads — <N> fixed, <N> rejected, <N> discuss,
<N> deferred (filed #<...>); merged | left open (<reason>).` Then stop. Do not open a
third round, and do not re-review the diff after the merge — the run is over.
