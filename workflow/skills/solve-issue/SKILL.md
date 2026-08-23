---
name: solve-issue
description: >
  End-to-end GitHub issue workflow: analyze the issue, plan and implement,
  verify with available tests/build/lint (and optionally Playwright +
  Storybook), simplify, attack the change with parallel adversarial reviewers
  and fix what they find, trim comments and artifacts, then choose a push / PR /
  merge endgame via AskUserQuestion. Every git and GitHub action is delegated to
  `issue-flow`. Use when the user wants a single autonomous command for an issue
  they already consider simple enough to delegate end-to-end, e.g.
  `/solve-issue 69` or `/solve-issue` (asks which issue first).
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash(git diff:*) Bash(git status:*) Bash(git log:*) Bash(jq:*) Bash(rm:*) Bash(ls:*) Read Edit Write Glob Grep Task Skill AskUserQuestion
argument-hint: "[issue-number]"
metadata:
  author: edloidas
---

# Solve Issue

Runs the full issue workflow in one command: analyze → branch → plan →
implement → verify → advisors → cleanup → commit → push/PR/merge.
Designed for issues the user already judged simple. When uncertainty appears,
pause and ask rather than guess.

**This skill owns engineering judgment only.** Every git and `gh` action —
issue selection, branch, snapshot, commit, squash, push, PR, merge — is
delegated to `issue-flow`, which owns them. Do not run a git or `gh` write
command here, and do not restate `issue-flow`'s commit format or squash rules;
read-only `git diff` / `git status` / `git log` for scoping verification is
fine.

## Conventions

### Asking the User

Every question in this skill is written as `AskUserQuestion` options. Use that tool where
the host offers it, or the host's nearest structured-choice equivalent. Where the host has
neither, ask the same question in normal chat as a numbered list of 2–5 options —
recommended first, one short line of description each — and wait for the user to reply
with a number.

The endgame question in Phase 6 is never skipped. Every other gate defaults to
proceeding, so a host that cannot prompt still completes the flow.

### Delegating to Other Skills

This skill is an orchestrator: it invokes `issue-flow`, `issue-analyze`,
`changes-review`, `code-cleanup`, and `commit-summary` rather than reimplementing them.
"Invoke `<name>`" means hand control to that skill however the host chains skills.

**`issue-flow` and `issue-analyze` are hard prerequisites.** Every git and GitHub
action in the flow lives in `issue-flow`, and the scope analysis it works from comes from
`issue-analyze`; a host that cannot invoke another skill cannot run this one. Stop with
`solve-issue needs to invoke issue-flow and issue-analyze; this host cannot chain
skills.` rather than reimplementing the lifecycle inline. The other three —
`changes-review`, `code-cleanup`, `commit-summary` — are graceful: each call site says
what to do when that skill is missing.

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
| 4     | Verify (tests, build, lint, PW)   | Only to opt into Playwright             |
| 4.4   | Subtle simplification pass        | No                                      |
| 4.5   | Advisor round(s) + apply fixes    | No                                      |
| 5     | Comment cleanup + commit          | No                                      |
| 6     | Summary + choose endgame          | Always — 4 options via AskUserQuestion  |

## Phase 0: Resolve Issue

If `$ARGUMENTS` holds an issue number or GitHub issue URL, use it directly and
skip to Phase 1.

If empty, ask via `AskUserQuestion`:

- **question**: "No issue number provided. How should I pick one?"
- **Option 1** — header `Next issue`, label `Let issue-flow pick` `(Recommended)` — `Rank the backlog and recommend the most relevant open issue.`
- **Option 2** — header `Manual`, label `Stop and ask` — `Exit so you can re-run with an explicit issue number.`

- Option 1 → invoke `issue-flow` with intent `"pick an issue"`. That runs its
  Step 0, which ranks the backlog, lets the user choose, and chains into
  `issue-analyze` on the selection — so continue from Phase 2 with the number and
  the analysis it returns.

  Two of its outcomes are not a selection: the user picks `None`, or the branch it
  short-circuited on carries no issue number. Both end the run — stop, and say which
  one happened. Do not continue to Phase 2 without a scope analysis and a resolved
  issue title; Phase 5 commits under that title.
- Option 2 → print `Re-run with an issue number, e.g. /solve-issue 42.` and
  stop.

## Phase 1: Analyze

Invoke `issue-analyze` on `<N>`. Do not duplicate its work inline — capture the
Scope Analysis and Implementation Tasks it emits. It is a prerequisite, not a
nice-to-have: it resolves the issue title this flow commits under, and the
blockers Phase 1 stops on.

Stop conditions from the analyzer:
- Issue is closed → print its status line and stop.
- Issue has an open blocker → print the blocker and stop. Do not implement
  through an open blocker without explicit user approval.
- Issue is assigned to another user (`> Note:` line) → continue, but flag the
  condition in the final summary.

## Phase 2: Plan

Produce a structured plan before any implementation, in the same shape Plan
mode produces — goal, file-level change list, explicit out-of-scope, risks
or decisions. Do not write a plan file; print the plan inline only.

Before drafting, do enough read-only investigation to make the plan
file-specific (Read, Grep, Glob). Do **not** edit anything yet.

### Plan output format

Print exactly this structure:

````markdown
## Plan for #<N>: <title>

**Goal**
<1–2 sentences stating what "done" looks like for this issue.>

**Changes**
1. `<relative/path/to/file>` — <concrete change: what is added, modified, or
   removed, and why>
2. `<relative/path/to/file>` — <concrete change>
3. ...

**Out of scope**
- <thing the issue might imply but you are not touching, with one-line reason>
  (or: `None — scope is contained to the files above.`)

**Risks / decisions**
- <any judgment call with tradeoff; name the alternative you considered>
  (or: `None — implementation is mechanical.`)
````

Rules for the plan body:

- Every Changes entry references a concrete file path. No "investigate X" or
  "figure out Y" items — investigation belongs to pre-plan reading.
- 3–10 Changes for a normal issue. If you're over 10, that's a trigger for
  the approval gate below.
- Out of scope is mandatory. If nothing is out of scope, say so explicitly —
  it forces you to have thought about it.
- Risks section names alternatives. `None` is valid when the choice is
  forced.

After printing the plan, set up progress tracking per **Conventions → Tracking
Progress** — one entry per Changes item.

### When to pause for approval

Default: proceed to Phase 3 immediately after printing the plan. Do **not**
ask for approval on simple issues — the printed plan is the checkpoint, and
the user can interrupt if they disagree.

Pause and ask via `AskUserQuestion` only if **any** of these fire:

- Multiple valid implementation approaches exist where picking one is a real
  judgment call (new API shape, data model, public-facing contract change)
- The issue text is ambiguous about what "done" means
- Implementation would clearly touch files outside what the issue title
  implies
- Changes list grew beyond ~10 items during planning
- The analyzer surfaced a dependency that is unresolved

When one of the above fires, ask one focused question:

- **Option 1** — header `<≤12 chars>`, label `<proposed plan name>` `(Recommended)` — `<one-line reason>`
- **Option 2** — header `<≤12 chars>`, label `<alternative>` — `<one-line reason>`
- **Option 3** — header `Stop`, label `Exit without implementing` — `Leave the branch unstarted.`

Wait for the reply before continuing.

### Create branch

Invoke `issue-flow` with intent `"start work on #<N>"`. That runs its Step 2,
which checks out `issue-<N>` off the correct base branch and updates the project
board to "In Progress" when available.

If `issue-<N>` already exists, let `issue-flow` handle the switch-vs-recreate
prompt.

Record the `Fork:` SHA from its Step 2 report — later phases diff against it to
scope verification and pass it to the reviewers. Use `Fork:`, not `Base:`:
`Base:` is a branch *name*, and an epic branch that exists only on the remote
fails in `git diff <name>..HEAD` with `unknown revision`. A SHA always resolves.

Do not detect the base yourself; `issue-flow` owns base detection, and its
`detect-base.sh` handles the `epic-*` cases a naive `origin/HEAD` lookup gets
wrong. If the flow was entered on an existing branch and no Step 2 report was
printed, ask `issue-flow` for the fork point.

## Phase 3: Implement

Work through the tracked Changes items sequentially. Mark each one started when
you begin it and done as soon as it is done — no batching.

For a checkpoint mid-implementation, invoke `issue-flow` with intent
`"snapshot"` — its Step 3 snapshot mode freezes the tree into a content-free
`wip:` commit. Phase 5 squashes those away. Do **not** push between tasks.

If a task hits a hard blocker (missing credentials, external service down,
decision required), stop and ask the user.

## Phase 4: Verify

Detect the verification set from `package.json` + repo conventions. Do not
skip verification on "simple" changes.

### Script detection

Read `package.json` if present. Pick the first script that exists in each
group:

| Group      | Candidates (first wins)             |
| ---------- | ----------------------------------- |
| Type-check | `typecheck`, `tsc`, `check-types`   |
| Lint       | `lint`, `lint:check`                |
| Build      | `build`, `compile`                  |
| Unit test  | `test`, `test:unit`                 |

Pick the runner from the lockfile:
- `pnpm-lock.yaml` → `pnpm run <script>`
- `bun.lockb` or `bun.lock` → `bun run <script>`
- `yarn.lock` → `yarn <script>`
- else → `npm run <script>`

### Scope-aware selection

Use the changed file set from `git diff --name-only <fork>..HEAD` to choose,
with the `Fork:` SHA from Phase 2:

- **Source code changes** (`src/`, `lib/`, `app/`, similar) → type-check +
  build (if present) + unit tests
- **Only docs, config, CI, or plain text** → lint only (or nothing if lint is
  not configured)
- **Storybook `*.stories.*` or component-level UI changes** → type-check +
  `storybook build` if that script exists

### Playwright + Storybook (opt-in)

If the change is UI-facing **and** the repo has both Playwright and
Storybook, ask via `AskUserQuestion`:

- **Option 1** — header `Skip PW`, label `Skip Playwright` `(Recommended)` — `Unit tests and build are enough for this scope.`
- **Option 2** — header `Run PW`, label `Run Playwright` — `Start Storybook and run Playwright against the affected stories.`

Starting Storybook is slow, so default to skipping unless the user opts in.

### On failure

If any verification step fails:

1. Go back to Phase 3, fix the cause, and re-run **only** the failing check.
2. If the same check fails twice after two fix attempts, stop and hand back
   to the user with the failure output. Do not proceed to Phase 4.5 with
   failing verification. Do not rationalize skipping it.

## Phase 4.4: Simplify

Run this **before** the advisor round, so the reviewers attack the code that
will actually ship. A simplification applied after review ships unreviewed.

Dispatch one subagent over the changed files with a single instruction: apply
subtle, behavior-preserving simplifications against the bar below, and nothing
else. If the host has no subagent facility, run the same instruction inline.

### The simplification bar

Apply only when **all** hold:

- Behavior is provably unchanged
- The change is contained to a single function or a local symbol
- No public export, API shape, or file layout is touched
- It makes the code shorter *and* clearer, not merely shorter

Anything heavier — splitting functions, reshaping control flow, extracting
utilities, renaming exported symbols — is **not applied**. Record it for the
Phase 6 summary and move on. A refactor that is merely nice is out of scope
for an issue the user called simple.

Re-run the Phase 4 checks the simplifications could plausibly break. If
anything fails, revert the simplification rather than fixing around it — it
was supposed to be behavior-preserving, and a failing check is proof it was
not.

## Phase 4.5: Advisor Round

Independent reviewers attack the change in parallel, then their findings are
triaged and fixed. This always runs once verification is green — it is the
polish pass, not an optional extra.

The review itself belongs to `changes-review`. This phase owns only what is
workflow policy: freezing the diff, triaging findings, and deciding whether to
run a second round. Do not duplicate the reviewer prompts here, and do not
invoke `consilium` — that board ranks candidate approaches to a problem and has
nothing to say about whether a finished diff is correct.

### Freeze the diff first

Every reviewer must see the same change set. Before dispatching, delete the
cruft listed under Phase 5 → Remove cruft — the snapshot stages everything, so
scratch files and screenshots would otherwise be baked in where Phase 5's
untracked-file check can no longer see them.

Then, if the tree is dirty, invoke `issue-flow` with intent `"snapshot"`. Its
Step 3 snapshot mode stages the tree and commits it under a content-free `wip:`
subject. Phase 5 squashes it away.

Each round freezes again — round 2 must snapshot the round-1 fixes before
dispatching, or the reviewers re-review the diff they already saw. Round 2 and
later also pass `--mode simple` with the previous round's snapshot as the base,
so the reviewers attack the fix rather than re-reading the whole branch to
check a two-line change.

Carry your own list of findings you accepted rather than fixed. The reviewers are
blind to previous rounds by design, so an accepted decision comes back every
round — recognizing it is your job, not theirs.

### Run the review

Invoke `changes-review` with `--base <fork>` and `--issue <N>`, using the
`Fork:` SHA recorded in Phase 2 — it resolves as a rev where a branch name may
not. It dispatches the
reviewers, re-attacks its own findings — verification is on by default for a
`--base` run — and returns what survives. It changes nothing.

Pass **no other context**. Not the Phase 2 plan, not the Risks/decisions
section, not a summary of what you were trying to do, not the previous round's
findings or how you triaged them. The skill's entire value is that its
reviewers are blind to your reasoning; handing it a summary destroys that.

### Triage and fix

Classify every returned finding:

| Class      | Meaning                                                          | Action                    |
| ---------- | ---------------------------------------------------------------- | ------------------------- |
| **Fix**    | Real defect or a genuine requirement gap                          | Apply now                 |
| **Note**   | Valid but out of scope for this issue                             | Report in Phase 6         |
| **Reject** | Wrong, or the reviewer lacked context that makes the code correct | Report in Phase 6         |

Rules that keep triage honest — you are judging reviews of your own work, and
the pull toward dismissal is real:

- **Uncertainty defaults to Fix.** If you cannot show a finding is wrong, it
  is not rejected.
- **A Reject must name the specific context the reviewer lacked** — the file
  it could not see, the invariant it did not know. "I don't think that's
  right" is not a rejection.
- **Rejects survive verbatim.** Phase 6 carries the reviewer's own wording,
  not your paraphrase of it. The user grades the rejection, not your summary.

Apply the Fix items, then re-run the Phase 4 checks the fixes could plausibly
break. Verification must be green again before continuing.

### Round 2

Run a second round if **any** of these hold:

- The fixes touched a file that was not in the round-1 diff
- The fixes changed more than ~30% of the round-1 changed-line count
- You rejected any intent-reviewer finding
- You rejected more than half of all findings

The last two matter because rejects do not change the diff, so a wrongly
rejected bug is invisible to a size-based trigger. A high reject rate is the
signal that the implementer is grading itself generously.

Otherwise stop at one round. **Hard cap: two rounds.** If round 2 surfaces
another large batch, do not run a third — apply the clear fixes, list the rest
as Notes, and let the PR review catch them.

## Phase 5: Cleanup + Commit

### Trim comments

Invoke `code-cleanup --comments-only`, scoped to the change. This is the step
that stops verbose AI commentary from reaching the commit: it removes comments
that restate the code, compacts genuine gotchas to a line or two, and surfaces
design rationale for the commit body.

`--comments-only` is deliberate — **no code changes at commit time.** Any
simplification opportunity belongs to Phase 4.5, where it was reviewed. If
`code-cleanup` reports suggested refactors, carry them into the Phase 6
summary as Notes; do not apply them here.

Its **Suggested for commit message** section is an *input* to the commit body — it
answers why the code is built the way it is, which is the first thing the body has
to establish. Pass it along under Commit below; `issue-flow` folds it into that
paragraph rather than tacking it on at the end.

If `code-cleanup` is not installed, do the comment pass inline: delete comments
that narrate what the code already says, keep non-obvious gotchas at one to two
lines, and leave documentation comments and `HACK`/`FIXME`/`TODO` markers
alone.

### Remove cruft

Delete anything that should not ship with the commit:

- Plan and scratch files under `.claude/plans/`, `.claude/plan/`, or
  `docs/superpowers/` — gitignored working artifacts, per the repo's
  instructions file. Only files this run created; never a config directory.
- Temp files under `tmp/` or `.tmp/` at the repo root that were created
  during this run
- Screenshot artifacts under `.playwright-mcp/` if they were throwaway

Use `git status --short` to sanity-check that no untracked scratch files are
about to be staged, and that every intended deletion shows up.

### Commit

Invoke `issue-flow` with intent `"commit #<N>"`. Its Step 3 squashes the branch
to one commit, writes the subject and body, and reports the result. It owns the
commit subject format, the body, and the squash rules for every `wip:` snapshot
Phase 4.5 created — do not restate any of them here, and do not run the git
commands yourself.

Pass along, as context for the commit body:

- The issue title and number, so the subject can be built.
- The design rationale `code-cleanup` pulled out of the source, if it produced
  any — that text is why the comment pass could delete it, and it answers the
  body's first question. It is not a block to append at the end.

Capture the short SHA and subject from Step 3's report for the Phase 6 summary.
If Step 3 comes back with a dirty tree or more than one commit, that is a
failure of the commit step — re-invoke it rather than fixing the history here.
The endgame pushes the commit, not the working copy.

## Phase 6: Summary + Endgame

Print a compact summary in this exact shape (omit rows that don't apply):

```text
## Solved #<N>: <title>

**Changed**
- <bullet per logical change>

**Verified**
- type-check: ok
- unit tests: ok (N passed)
- build: ok
- Playwright: skipped (not UI) | passed (N stories) | not configured

**Advisors** (N round(s))
- cold (<model>) · intent (<model>) · external (<cli>|skipped)
- N findings — N fixed, N noted, N rejected
- <one line per fixed finding>

**Not applied**
- <finding, in the reviewer's own wording> — <Note: out of scope | Reject: the
  context the reviewer lacked>

**Commit** `<short-sha>` <subject>
```

Omit the **Advisors** detail lines when the reviewers came back clean — a
single `no findings` line is enough. Omit **Not applied** entirely when there
is nothing in it. Never omit a Reject: a rejected finding the user never sees
is the one failure mode this whole phase is built to prevent.

Then ask via `AskUserQuestion`:

- **question**: "What's next for this commit?"
- **Option 1** — header `PR + merge`, label `Push, PR, auto-merge` `(Recommended)` — `Push, open a PR, wait for checks, merge when green (via issue-flow Steps 4–6).`
- **Option 2** — header `PR only`, label `Push and open PR` — `Push and open PR, stop before merge (via issue-flow Steps 4–5).`
- **Option 3** — header `Push only`, label `Push the branch` — `Push the branch. No PR.`
- **Option 4** — header `Nothing`, label `Leave it local` — `Keep the commit local. No push.`

Route via `issue-flow`:

| Choice              | `issue-flow` intent                                       |
| ------------------- | --------------------------------------------------------- |
| PR + merge          | `"push, PR, and merge #<N>"` — Steps 4, 5, 6 in order     |
| PR only             | `"push and open PR for #<N>"` — Steps 4 and 5             |
| Push only           | `"push #<N>"` — Step 4                                    |
| Nothing             | Stop — commit stays local                                 |

Let `issue-flow` handle the per-step questions it already owns (squash
confirmation, reviewer selection, merge pre-checks). Do not duplicate those
prompts here.

### Do not stop at "PR created"

Both PR endgames must end with a mergeability verdict, not just a PR URL:

- **PR + merge** — `issue-flow` Step 6 waits on CI and merges. Report the
  merged state, or the specific failing check that blocked it.
- **PR only** — `issue-flow` Step 5 still verifies mergeability. Report the
  `Mergeable:` line it produces. Do not watch CI for this path, but do not
  claim the PR is ready without that line either.

If mergeability comes back `CONFLICTING`, the flow is not done: rebase,
force-push, re-check, and report the resolved state.

## Error Handling

| Situation                                | Action                                                          |
| ---------------------------------------- | --------------------------------------------------------------- |
| `gh` not authenticated                   | `issue-flow` or `issue-analyze` reports it — stop, relay it      |
| Not in a git repo                        | Stop: `Not inside a git repository.`                            |
| Issue closed                             | Stop after Phase 1, print `issue-analyze` status                |
| Open blocker                             | Stop after Phase 1 unless user explicitly says to proceed       |
| Working tree dirty before Phase 2        | Stop: `Uncommitted changes on base branch — resolve first.`     |
| Verification keeps failing               | Stop after 2 fix attempts in Phase 3/4, hand back to user       |
| `changes-review` unavailable             | Note it in the summary, skip Phase 4.5, continue to Phase 5     |
| Advisor fixes break verification twice   | Revert those fixes, list them as Notes, continue to Phase 5     |
| Simplification breaks a check            | Revert it — behavior-preserving means the check should not move |
| User picks `Stop` on any AskUserQuestion | Exit cleanly, leave local state as-is                           |
| Host has no structured-choice tool       | Numbered list in chat per **Asking the User**, wait for a number |
| Host cannot chain skills                 | Use each call site's documented inline fallback                 |

## Scope

This skill is for issues the user already decided are simple enough to
delegate end-to-end. If `issue-analyze` surfaces an epic, a multi-file
architecture decision, or a contract change, trigger the Phase 2 plan
approval gate rather than attempting it silently.
