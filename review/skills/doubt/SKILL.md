---
name: doubt
description: >
  Rule on a set of claims that already exists — review findings, a plan's assumptions, an analysis,
  a reviewer's objection — before anyone acts on them. Every claim gets exactly one verdict: it
  holds, it holds only in a narrower case, it is true but not worth the fix, it falls, or nobody can
  settle it. Whoever judges never sees the reasoning that produced the claim. Reads and reasons;
  changes nothing.
when_to_use: >
  When a claim set already exists and should be checked before it is acted on — "validate your
  findings", "do they agree", "double check this", "are we sure", "did we miss anything". Also
  before contradicting a person, before a claim is published outward, and once before fixes start
  on a set of findings. Not inside a fix-verify loop, and not for a diff.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Read Glob Grep Task Skill Write(*/outsider-*)
argument-hint: "[what to doubt, or empty for the session's most recent claim set]"
metadata:
  author: edloidas
---

# Doubt — Verify Claims From Outside

## Purpose

Rule on a set of **claims** — assertions a reasonable person could disagree with. Not a diff, not a
question. Two seats, one verdict each, no ranking and no fixes.

The premise is `changes-review`'s: whoever produced a claim wants it accepted, and a seat that reads
their reasoning inherits it. So the seats get the propositions and nothing else.

Two agents against consilium's seven to nine. That is the point — cheap enough to fire automatically.

## When to Use

Three triggers, at most once per claim set:

1. **About to contradict a person** — telling a reviewer they are wrong, pushing back on a PR
   comment, declining a requested change.
2. **A claim is about to leave the session** — a PR comment, an issue body, a reply on a thread.
3. **Findings exist and fixes are about to start** — once, before the first fix.

Also on request: `/doubt`, "validate your findings", "do they agree", "double check this", "are we
sure", "did we miss anything".

**Gate on stakes, not on confidence** — fire when being wrong is expensive, whether or not you feel
unsure. An agent poorly calibrated on its own certainty cannot use that certainty to trigger the
skill built to catch it.

### Never

- **Inside a loop.** Once per claim set; a second panel on the same propositions measures sampling
  noise. This is what excludes `build:fix-and-reverify` rounds.
- **When something runnable settles it.** If a test, a build, or `build:live-probe` answers the
  claim, run that — two models reasoning about observable behavior is worse than one observation.
- **On cheap-to-reverse work.** If undoing it is one command, the panel costs more than the mistake.
- **On a claim set already doubted this session.**

**Not this skill:**

| You have | Reach for |
| -------- | --------- |
| A diff to attack for bugs and requirement gaps | `review:changes-review` |
| A question about which approach to take | `review:consilium` |
| One quick outside opinion, no panel and no verdicts | `assist:outsider` |
| A back-and-forth about a design | `assist:discuss` |

## Phase 1: Resolve the claim set

**With an argument** — scope to what it names, nothing else.

**Without one** — take the most recent message asserting things a reasonable person could disagree
with: an analysis, a skill's report, a findings list, a recommendation. Take it **whole**, trailing
minor entries included; those are the ones nobody scrutinized, so skipping them inherits the blind
spot that filed them as minor.

Normalize each claim into one numbered proposition:

- **Self-contained** — judgeable without the surrounding prose, since that prose is the reasoning
  the seats must not see
- **One assertion each** — a claim doing two jobs splits into two
- **As the claimant meant it** — not steelmanned, not weakened

Record each claim's author in your notes and **keep it out of the seats' prompt**: a seat told who
wrote a claim judges the author.

**If there is no claim set, stop and say so.** Never manufacture propositions from a conversation
that only asked questions.

## Phase 2: Dispatch

Both seats run concurrently on the same input — the numbered propositions and repo access. Withhold
the plan, the rationale, the commit message body, author names, and any hint of which claims you
favour.

**Cold seat** — dispatch a subagent briefed with `references/seat-prompt.md`, propositions appended,
on a different model from your own where the host allows one. Where the host has no subagent
facility, run the same prompt inline and report the run as having one independent seat.

**Outside seat** — invoke `assist:outsider` in ask mode by name rather than reproducing its
procedure; it owns temp-file resolution, run ids, and the rule that the question is written with a
file-write tool and never a shell heredoc. Pass it:

- `--host <the agent you are>`, so it does not answer its own question
- `--preamble <skill-dir>/references/seat-prompt.md`, replacing outsider's default entirely
- the numbered propositions, and nothing else, as the question
- a timeout of `420`, with the surrounding command timeout at its maximum

**Verify the preamble path resolved before dispatching.** This skill is reachable through several
generated symlink trees, so `<skill-dir>` must be the directory this `SKILL.md` was loaded from.
Outsider refuses an unresolvable `--preamble` and names the path that failed.

**Name the agent that answered** — outsider prints it on its first line. A verdict from a seat you
cannot identify is not interpretable.

## Phase 3: Verdicts

Each seat rules on every proposition, from a closed vocabulary:

| Verdict | Use when | Must carry |
| ------- | -------- | ---------- |
| `HOLDS` | True, and worth acting on | The evidence |
| `NARROWER` | True only under a condition the claim did not state | The condition |
| `BELOW BAR` | True, and not worth acting on — the fix costs more than it buys | What acting costs, what it buys |
| `FALLS` | Wrong, unreachable, or attacking something that is not there | What the claimant missed |
| `UNPROVEN` | Undemonstrable either way from what is available | What evidence would settle it |

`NARROWER` corrects a true claim's scope; `BELOW BAR` accepts it in full and rejects the work.
Neither substitutes for the other — without `BELOW BAR`, a seat that wants a trivial claim dropped
has only `FALLS`, and must argue the claim is *wrong* to get there. That is how a panel starts
manufacturing refutations.

## Phase 4: Synthesize

- **Both seats agree** → that verdict, marked **corroborated**, the strongest signal this skill
  produces. Never let it read as two separate results.
- **Seats split** → report both, then rule between them with your reason. Never average two verdicts
  into a hedge.
- **`UNPROVEN` from either seat** → it stays `UNPROVEN` unless the other *demonstrated* something.
  An assertion does not beat an honest non-answer.

Then apply context no seat had. Override where warranted, saying so and which way.

### Calibration

**Upholding the claim set is a valid and expected outcome.** The job is finding out whether these
claims are true, not finding fault with them. Work that is already good is finished work: a claim
that is correct and proportionate gets `HOLDS` and nothing further. Never manufacture a `NARROWER`
to look rigorous.

A run where nothing survives is as suspect as one where everything does. If every verdict came back
`FALLS` or `BELOW BAR`, say so in the header and treat your own framing as the likely fault.

## Report

```
## Doubt: N claims · X held, Y narrowed, Z below bar, W fell, V unproven
Seats: cold (<model>) · outside (<agent>)

1. HOLDS — corroborated. <claim, one line>
   <what each seat demonstrated, cited>

2. NARROWER — split (cold: HOLDS, outside: NARROWER). <claim>
   Condition: <the case where it is true>
   Ruling: <yours, and why>

3. BELOW BAR — corroborated. <claim>
   Costs <X>, buys <Y>. True, not worth it.

4. FALLS — <claim>
   <what was missed, cited>
```

Omit a zero count from the header. Say whether the run got model diversity or role diversity alone.
A run where everything holds is a complete report, not a failed one.

## Edge Cases

- **Outside seat unavailable** — this skill ships in the review bundle and `outsider` in assist, so
  a host can have one without the other; no external agent CLI installed has the same symptom. Where
  the host allows a model per seat, run **two cold seats on different models**. Where it does not,
  run one and mark the run **one seat, not corroborated** — two seats on the same model differ only
  by sampling, so calling that corroborated would be a lie.
- **A diff was passed** — hand off to `review:changes-review` at `--mode simple`, the same
  two-reviewer cost as this skill. Say so in one line; do not ask.
- **A question was passed** — say in one line that you are running `review:consilium` instead, then
  run it. Announce but never ask: consilium is four times the cost, so silent escalation is wrong
  and a blocking question is an interruption.
- **A seat times out or fails** — note it in the header, synthesize from the other. An outside seat
  that timed out at 300s never received the timeout argument.
- **Outside seat came back unbriefed** — an answer using none of the verdict vocabulary means the
  preamble never reached it. Discard rather than map it; an unbriefed answer looks like a verdict
  and is not one.
- **One claim** — valid, and cheap. Run it.

## Rules

- **Autonomous.** No questions mid-run. Resolve ambiguity yourself and say how.
- **No modifications.** This skill reads and reasons. It never edits, never fixes, never commits.
- **Seats stay blind** to authorship, to the reasoning behind a claim, and to which claims you
  favour — and to each other's output.
- **Every verdict carries what its row requires.** One that does not is incomplete: complete it or
  drop it, and say which.
