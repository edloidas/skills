---
name: fix-and-reverify
description: >
  Fix what a review found, then review the fix. Runs review and fix in rounds: triage findings by
  severity and confidence, fix the ones that clear the gate, confirm the tree still builds and its
  tests still pass, then attack the fix itself rather than the whole change again. Fixes
  automatically by default and reports anything with a real trade-off; `--interactive` asks instead.
  Use after implementing a change, after a review has produced findings, or when asked to fix
  findings, address what a reviewer raised, or close out a review loop.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash Read Write Edit Glob Grep Task Skill AskUserQuestion
argument-hint: "[--interactive] [--mode <simple|standard|deep>] [--rounds <N>] [--base <branch>] [--no-snapshot] [instructions]"
metadata:
  author: edloidas
---

# Fix and Reverify

## The premise

**A fix is unreviewed code.** The reviewer that found the bug never saw the patch, and the agent
that wrote the patch is the one that wrote the bug. So the loop is: review finds, you fix, the next
round reviews the fix. Not the whole change again — the fix.

That is what makes rounds affordable rather than exponential. Round 1 attacks a branch; round 3
attacks eleven lines. The scope shrinks every round, and so does the cost.

This skill **fixes and verifies**. Finding is `/changes-review`'s job and this skill calls it —
that is the only skill it invokes, and the only one it names. Everything downstream of the loop
(committing, squashing, pushing, publishing) belongs to whoever called it.

Two failure modes it exists to prevent:

- **Fixing everything a reviewer said.** Reviewers over-report and over-rate. A low-confidence
  minor finding costs more to fix — the patch, the risk the patch carries, the round of re-review it
  earns — than to carry as one line in a report.
- **Assuming a fix worked.** "Fixed" is a claim about code nobody has read. Re-review is what turns
  it into a fact.

## Arguments

| Argument | Description |
| -------- | ----------- |
| _(none)_ | Fix automatically, report what needs a decision. Uses findings already in context; reviews first when there are none |
| `--interactive` | Ask before anything with a real trade-off, and before dismissing a finding |
| `--mode <simple\|standard\|deep>` | Review depth for round 1 only. Later rounds follow the ladder |
| `--rounds <N>` | Lower the round cap (default and maximum 5) |
| `--base <branch>` | Round-1 scope, passed straight through to the review |
| `--no-snapshot` | Create no snapshot commits. Later rounds then re-review the whole change |
| `$ARGUMENTS` | Focusing instructions — `only criticals`, `skip the intent findings`, `ignore the test files` |

Default is unattended. Nothing waits for a human unless `--interactive` says so.

## Phase 0: Where to start

A bare invocation looks at what just happened before it spends a review.

| What is in context | Start at |
| ------------------ | -------- |
| A review already produced findings — a change review, triaged PR feedback, an audit report | Phase 2, with those findings. Round 1's review is already spent |
| No findings | Phase 1 |
| Findings, but the tree changed after they were produced | Phase 1. Findings older than the code are addressed to a diff that no longer exists |

**Never re-run a review whose findings are already sitting in context.** It is the most expensive
thing this skill can do and it buys nothing.

Findings from a source other than a change review arrive on someone else's scale, or on none. Put
them on this one before the gate — a rating from another scale is not this gate's rating:

- **Confidence.** A finding that named the failing input and what it produces is high; one that read
  the code and found the story plausible is medium; a comment asking whether something might be a
  problem is low.
- **Severity.** Collapse whatever bands the source used onto critical, moderate, and minor by what
  the failure costs and who can reach it. An audit's `informational` band is minor; a PR comment
  carries no severity at all until you assign one.

## Phase 1: Review

Invoke `/changes-review`. Pass the scope, the issue when one resolved, and the mode from the ladder.

| Round | Mode | Scope |
| ----- | ---- | ----- |
| 1 | `--mode` if the caller passed one, otherwise the review's own default | The change |
| 2 | `standard` | The round-1 fix |
| 3–5 | `simple` | The previous round's fix |

Round 2 still has enough new surface to be worth several reviewers. By round 3 the diff is a
handful of lines and a full run spends most of its budget re-deriving a spec that settled two rounds
ago — so late rounds go `simple`, and reachability is the lens that still changes the outcome.
Round 1 is the only one a caller should override: a workflow that wants a whole branch attacked hard
asks for `deep` there.

**Pass no reasoning.** Not your plan, not what the fix was trying to do, not the previous round's
findings or which of them you rejected. The reviewers are cold to the implementer's reasoning by
design, they cannot detect that it leaked, and this skill *is* the implementer by round 2.

### Snapshots

Scoping a round to the fix needs a boundary. Before applying a round's fixes, commit the tree as a
snapshot:

```bash
git add -A && git commit -m "wip: fix-and-reverify round <N> snapshot"
```

Fixes then land on top, uncommitted, and the next round reviews the uncommitted diff — exactly the
fix and nothing else.

Snapshots are scaffolding, not history. Report their shas and leave squashing to the caller; do not
squash, amend, or push them yourself. Two constraints come with them:

- A snapshot commits the **entire** working tree. Before the first one, name any file it would
  include that is outside the review scope — unrelated work gets committed with it, and the caller
  needs to know that before it happens.
- `--no-snapshot` gives up scoped rounds. Later rounds re-review the whole change, which means every
  finding already accepted comes back and every round costs the same as the first. Say so in the
  report.

## Phase 2: Triage

The gate. Both dials have to clear it before a single file is edited.

| | High confidence | Medium | Low |
| --- | --- | --- | --- |
| **Critical** | Fix | Fix | Hold for re-check |
| **Moderate** | Fix | Fix | Hold for re-check |
| **Minor** | Report — fix only if purely stylistic | Report | Drop, named once |

Why a gate at all: below it, carrying beats fixing. A fix costs the patch, the risk the patch
carries, and the round of re-review it earns. A carried finding costs one line. That trade only
inverts for a finding both consequential and credible.

- **Purely stylistic** is the one minor exception — a stray import, a misleading name, a formatting
  slip. Free to fix, and carrying it costs more than the patch. It does not extend to any minor
  finding with behavior attached.
- **Decisions** — findings a review marked as a question rather than a defect — are never fixed at
  any severity. They need an answer. Report them.
- **Held** findings go to Phase 5, not to the bin. Low confidence means unsettled, not wrong.

### Routine or escalated

Clearing the gate says the finding is worth fixing. It does not say the fix is yours to choose.

| Routine — fix it | Escalated — report it |
| ---------------- | --------------------- |
| Bug with one clear correct behavior | Multiple valid approaches with real trade-offs |
| Missing error handling, obvious approach | Breaking or public API change |
| Code not matching a documented pattern | Security-sensitive change |
| Test fix, assertion update | Ambiguous requirement, unclear right fix |
| Single-file, localized change | Cross-cutting change across systems |
| Removing dead code or an unused import | Architectural decision |

**Escalated findings are reported, never fixed** in the default mode. An unattended run must not
land an architectural decision nobody chose. Under `--interactive` they become questions instead.

When the classification is genuinely unclear, escalate. Getting it wrong that way costs a line in a
report; getting it wrong the other way costs a decision the caller never made.

## Phase 3: Fix

Fixes run in subagents. The orchestrator holds the ledger; it does not hold file contents. That is
what keeps a five-round loop inside one context.

Dispatch one fixer per finding, giving it the finding **in the reviewer's own wording**, the files
named in it, and nothing else. It returns what it changed in a line or two, plus anything it could
not fix and why. The prompt is `references/fix-agent-prompt.md`.

- **Two fixers must never share a file.** Cluster findings by file and dispatch one fixer per
  cluster. Concurrent edits to one file lose work silently.
- A finding a review reported as one root cause with several symptoms is **one** fixer. Splitting it
  produces three patches that each treat a symptom.
- **No scope expansion.** A fixer that spots a second bug reports it; it does not fix it. That
  report enters the ledger as a finding and faces the gate in the next round like anything else.
- Where the host has no subagent facility, apply the same prompts inline, one at a time, in the same
  clustering order, and say so in the report.

## Phase 4: Verify the fix

Before the next review round, the tree has to build and its tests have to pass — or at minimum,
everything the change touches. A review round spent on code that does not compile is a wasted round.

1. **Find the project's own checks** — package manifest scripts, a makefile, a task runner, the CI
   workflow. Never invent a command the repo does not define.
2. **Establish the baseline first.** Checks already red before any fix are not the fix's fault.
   Record that and judge the fixes only against *new* failures.
3. **Prefer the narrow checks** — a type check plus the tests covering the touched files. Run the
   full suite when it is fast enough to be free.
4. **Green → next round.**
5. **Red → the fix is the suspect.** Find the cause and correct it, then re-run only the check that
   failed.
6. **Red twice on the same check → revert that fix.** The snapshot is the revert point. Record it as
   reported-not-fixed with the failing output and move on. **Never fix around a failing check** —
   that trades one known defect for an unknown one.

A repo with no checks at all: say so in the report and do not manufacture a test suite to fill the
gap. That is scope expansion wearing a safety vest.

## Phase 5: Carry the ledger

Reviewers in the next round are blind to this one, by design. Every finding you consciously did not
fix will be found again, and recognizing it is your job, not theirs.

Every finding ends each round in exactly one state:

| State | Meaning | Next round |
| ----- | ------- | ---------- |
| `fixed` | Patched, checks green | Expect it gone. If it comes back, the fix did not work — that is a live finding, not a duplicate |
| `held` | Low confidence, unsettled | Re-checked (below) |
| `reported` | Cleared the gate but escalated, or minor and carried | Not re-fixed, not re-reported. Recognized and skipped |
| `dismissed` | Re-checked and still could not be demonstrated | Never raised again |
| `reverted` | The fix broke a check twice | Reported with the output |

### Re-checking held findings

Alongside each new round's review, dispatch one subagent per held finding whose only job is to
settle it — demonstrate the failure or refute it. Prompt: `references/recheck-prompt.md`. These run
in parallel with the review and see only their own finding.

| Verdict | Action |
| ------- | ------ |
| High confidence | Fix it this round, subject to the routine/escalated split |
| Medium | Report it |
| Still low | Dismiss it, named once in the report |

**One re-check per finding.** Two rounds of "maybe" is itself an answer, and a third agent asking
the same question is not going to get a different one.

## Phase 6: Stop

Stop as soon as any of these holds:

- Nothing clears the gate.
- **The round fixed nothing.** There is no new code, so another review round asks a question that
  has already been answered. This is the condition that ends most runs.
- The round cap is reached — 5, or `--rounds`.
- A check is red for a reason the fixes cannot resolve.

Never start a round after one that changed nothing.

## Interactive mode

`--interactive` turns escalations into questions and asks before a dismissal. It does not ask about
routine fixes, it does not ask about the same finding twice, and it never asks permission to run a
review.

Where the host has a question tool — `AskUserQuestion` on Claude Code — use it: recommended option
first, every option carrying the reason it might be right, four at most.

Where it does not, fall back to a short numbered list in normal chat, in this shape, and **wait** —
an unanswered question is not consent:

```
**Fix the negative-offset truncation in `parseOffset`, or report it?**

1. **Switch to `Math.floor`** (recommended) — matches the documented behavior for negative
   offsets, one line, no caller affected.
2. **Clamp the input at zero** — sidesteps the negative case, but narrows what callers may pass.
3. **Report it, do not fix** — which behavior is correct is a product decision, not a code one.

**Reply with 1, 2, or 3.**
```

The bold question, the numbered options each with its reason, and the bold line asking for a reply.
A question that does not look like a question gets scrolled past.

## Report

```
## Fix and reverify: N fixed, M reported, K dismissed · R rounds

Rounds: 1 standard (12 findings) → 2 standard (3) → 3 simple (0)
Checks: `<command>`, `<command>` — green
Snapshots: abc1234, def5678 — squash before committing

### Fixed

- `path/to/file.ext:42` — <the finding, one line> → <what the fix does>

### Reported, not fixed

- <the finding, in the reviewer's own wording> — escalated: <the trade-off, and the options>
- <the finding> — minor, carried

### Dismissed

- <the finding> — re-checked in round 2, could not be demonstrated

### Reverted

- <the fix> — broke `<command>` twice: <the failing line>
```

Rules for the shape:

- **A finding you did not fix survives in the reviewer's wording**, not in your summary of it. You
  are reporting your own decision not to act; paraphrasing the claim is how a rejected finding
  quietly becomes a weaker one.
- Every ledger state with entries gets a section. Drop the empty ones from the heading counts and
  from the body — an empty `### Dismissed` reads as padding.
- Name the checks that ran. "Verified" without a command is a claim, not evidence.
- Nothing is silently swallowed. A finding that appears nowhere in this report is a bug in the run.

When the first review comes back clean:

```
## Fix and reverify: nothing to fix

Scope: <files, lines, base> · reviewed at <mode>
```

Then stop. Do not commit the fixes, do not squash the snapshots, do not push, and do not start a
round the stop rules already ended.

## Rules

- **A fix is unreviewed code.** Every round that changed something gets reviewed, or the loop has
  proved nothing.
- **Never fix below the gate.** Minor and low-confidence findings are carried, not patched.
- **Never fix an escalation unattended.** Report it and let the caller decide.
- **Never fix around a failing check.** Revert instead.
- **No reasoning reaches the review.** No plan, no rationale, no previous findings, no account of
  what the fix was for.
- **Fix in subagents, one file to one fixer.** The orchestrator keeps the ledger, not the code.
- **No scope expansion.** Fix what was found. A refactor spotted on the way is a finding for the
  next round, not work for this one.
- **Every finding ends somewhere.** One ledger state each, all of them in the report.

## Error handling

| Situation | Action |
| --------- | ------ |
| The review skill is unavailable | With findings in context, fix them and report that no round could be verified. With none, stop |
| No findings in context and the review returns none | Print `Nothing to fix.` and stop |
| Tree holds work unrelated to the review scope | Name those files before the first snapshot, then continue |
| Snapshot fails — no repository, detached head, hooks reject it | Continue with `--no-snapshot` semantics and say so |
| Checks red before any fix | Record the baseline, judge fixes against new failures only |
| The same check fails twice after a fix | Revert that fix, report it with the output |
| A fixer fails or returns nothing usable | Report the finding as not fixed, with the reason |
| A fix touches a file no finding named | Treat it as scope expansion: revert the extra edit, keep the fix |
| Host has no subagents | Run the prompts inline and sequentially, say so in the report |
| Host has no question tool under `--interactive` | Ask in chat in the shape above and wait |
| Round cap reached with findings still open | Report them. Do not start another round |
