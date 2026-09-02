---
name: consilium
description: >
  Approach board for a problem or a decision. Dispatches independent seats — some generating
  candidate approaches, including one agent outside this process entirely, some attacking the
  assembled set comparatively — then verifies the surviving objections and reports a ranked
  recommendation with its trade-offs. An approach already on the table enters as one candidate
  among several. Autonomous; changes nothing.
when_to_use: >
  When the question is what to build or how to frame the problem, not whether a diff is
  correct: "how should we approach this", "what are the options", "is this the right way",
  "think hard", "ultrathink", "stress-test this plan". Also for an architecture decision, a
  PRD review, or weighing trade-offs, prior art, blast radius, and lock-in.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Read Glob Grep Task Skill Write(*/outsider-*)
argument-hint: "[focus area, or empty]"
metadata:
  author: edloidas
---

# Consilium — Approach Board

## Purpose

Examine a problem, or an approach someone already picked, from several angles and several scopes at
once. The board answers four questions: **what are we actually deciding**, **what approaches exist**,
**what does the one on the table foreclose**, and **what would a different framing buy**.

It is not a review skill. Defects appear here only as *evidence that an approach is wrong* — a bug
that is fixable inside a candidate is not this board's output. A diff goes to `changes-review`.

**Mutation class**: reports only. Consilium reads and reasons and never modifies the thing it
examines; the one file it writes is the temp question file `outsider` needs for Peregrinus.
Autonomous: run every step without asking the user — resolve ambiguity yourself and say how — and
present the report when done.

## When to Use

- "how should we approach X", "what are the options", "what's the best way to", "explore approaches"
- "is this the right approach", "stress-test this plan", "think hard", "ultrathink"
- Before committing to a decision that is expensive to reverse — a data model, a public contract, a
  dependency, an architectural direction
- `/consilium`, `/consilium <focus>`

**Not this skill:**

| You have | Reach for |
| -------- | --------- |
| A diff, and you want it attacked for bugs and requirement gaps | `review:changes-review` |
| Comment noise, naming, convention drift in changed code | `review:code-cleanup` |
| A set of claims that already exists, and you want each one ruled on | `review:doubt` |
| One quick outside opinion, no board and no synthesis | `assist:outsider` |
| A back-and-forth about a design, not a verdict | `assist:discuss` |

**Cost.** This is the most expensive skill in the collection. Auto-selection keeps the board itself
at four or five seats, and verification adds **three more dispatches** on the largest payload of the
run — so a typical run is seven or eight agents and a full board is nine. On a board of four or fewer
seats, run the `bite` lens alone: with one critic there is nothing to corroborate, and `bite` is the
lens that changes outcomes. Spend this skill on decisions that are expensive to reverse, not on
questions one seat could answer.

## Focus Areas (optional `$ARGUMENTS`)

| Focus | Board | Use case |
| ----- | ----- | -------- |
| _(default)_ | Core + auto-selected | Let the board select its own optional seats |
| `all` | All six | Every angle, highest cost |
| `prior-art` | Core + Librarius | Likely already solved somewhere |
| `scope` | Core + Scrutator | Blast radius and what the choice forecloses |
| `cost` | Core + Censor | Suspect overbuilding, or a simpler option skipped |
| `wide` | Core + Scrutator + Censor | Big decision, no prior-art question |

## The Seats

Three generate, three critique. Each phase's isolation rule sits with its own dispatch.

### Core (always)

| Seat | Job | Phase |
| ---- | --- | ----- |
| **Novator** | Proposes fundamentally different candidate approaches, each concrete enough to start | Diverge |
| **Peregrinus** | An agent outside this process, with none of this conversation's context — frames the problem cold | Diverge |
| **Seneca** | Attacks the framing and the load-bearing assumptions; checks the candidates are genuinely distinct | Converge |

### Optional (auto-selected)

| Seat | Job | Launch when | Skip when |
| ---- | --- | ----------- | --------- |
| **Librarius** | Prior art — has this been solved, what do comparable systems and libraries already do | The problem sounds general, names a library or ecosystem, or looks like a well-trodden shape | Genuinely internal, domain-specific, or no external surface |
| **Scrutator** | Scope and blast radius — what each candidate touches, forecloses, and locks in; second-order effects | Wide reach, migrations, public contracts, data models, irreversible choices | Local, cheap to undo, contained in one module |
| **Censor** | Proportionality — cost to build and operate against the size of the problem; is a simpler candidate being skipped | New abstractions, multi-part machinery, anything that smells larger than the problem | Already minimal, or the cost is the point |

**Selection happens twice, because the evidence arrives twice.** Librarius is a generator, and its
trigger is a property of the frame, so decide it in Phase 1. Scrutator and Censor judge candidates
that do not exist until Phase 3 — deciding them from the frame is guessing, so decide them in Phase 3
against the assembled set. State each include/skip decision with a one-line reason at the point you
make it.

**A board whose only critic is Seneca is a defective board.** Seneca attacks the framing; nobody is
then looking at reach or at cost. If the assembled set contains any candidate that touches a contract
outside this codebase, reshapes stored data, or is expensive to leave, Scrutator runs. If any
candidate is materially larger than another that survives, Censor runs. Reaching Phase 4 with one
critic is allowed only when the candidates are genuinely small and cheap to undo, and the report must
say the board had one critic.

Minimum 3 (core only). Maximum 6. Typical 4–5 seats, plus verification.

## Choosing Models and Depth

Stated as intent, since the roster changes and each host names its own models:

- Give each seat the **most capable model the host offers**. If that is the model running this skill,
  take the next tier down — a seat on the orchestrator's own model shares whatever the orchestrator
  already believes about this problem.
- Where the host lets you pick a model per seat, **give each a different one**. Same-model seats
  differ only by sampling; same-role seats only by phrasing. Where it does not, run the default and
  say so in the report: role diversity survives that, model diversity does not.
- Give each seat a **depth budget** rather than a turn count: *shallow* for Censor, *standard* for
  Seneca and Librarius, *exhaustive* for Novator and Scrutator. A host with a turn or step limit maps
  these onto it; a host without one just needs the seat to stop when its own output contract is met.

The report says which kind of diversity the run actually got.

## Phase 1: Frame

No agents yet. Establish, in the orchestrator's own words:

1. **The decision** — one sentence naming what is actually being chosen. Not the symptom, the choice.
2. **Candidate A**, if an approach is already on the table. A finished plan is not the subject of an
   audit here; it enters the board as one candidate, ranked against the others on the same terms.
3. **Constraints** — what genuinely limits the solution space: existing architecture, compatibility,
   effort available, things that must keep working.
4. **Non-goals** — what is out of scope, so seats do not solve a larger problem than the one asked.

Where a constraint is a claim about the existing system, **check it in the repo** rather than
asserting it. A frame built on a constraint that is not actually true wastes every seat on the board,
and this is the only phase where it is cheap to catch.

If the decision cannot be stated in one sentence, say so and stop. Do not invent a decision — the
board cannot rank candidates against a question nobody has written down.

Announce the frame as four labelled lines: decision, candidate A (or `none`), constraints,
non-goals. Every seat receives this identical frame; nothing else about the conversation reaches
them.

## Phase 2: Diverge

**Dispatch all generators at once so they run concurrently.** They must not see each other's output.
Do not hint at which candidate you favour, and do not pass the conversation's reasoning about it.

The two native seats read their prompt from `references/` with `{{FRAME}}` replaced by the Phase 1
frame. Dispatch a subagent per seat that returns candidates in the shape its prompt specifies; on a
host with no subagent facility, run the same prompt inline.

- **Novator** — `references/novator-prompt.md`
- **Librarius** (if selected) — `references/librarius-prompt.md`. This seat needs web search or a
  documentation lookup facility; without one it reports what it could not verify rather than guessing.

**Peregrinus** runs through the collection's external-agent skill, `/outsider`, in **ask** mode.
Invoke it by name rather than reproducing its procedure here — it owns temp-file resolution, run ids,
and the rule that the question is written with a file-write tool and never a shell heredoc. Follow its
ask-mode steps, and pass it four things:

- `--host <the agent you are>`, so it does not select the host and answer its own question
- `--preamble <skill-dir>/references/peregrinus-prompt.md` — this skill's seat brief, which replaces
  outsider's default prompt entirely. It is a preamble, not a template: it carries no `{{FRAME}}`
  placeholder because the frame is appended after it as the question
- the Phase 1 frame, and nothing else, as the question
- a timeout of `540`, with the surrounding command timeout set to its maximum. This seat produces
  three sections and up to three fully specified candidates; outsider's 300s ask-mode default is not
  enough for that, and a timeout here costs the whole leg

**Check the preamble path resolved before you dispatch.** Consilium is reachable through several
generated symlink trees, so `<skill-dir>` has to be the directory this `SKILL.md` was actually loaded
from. Outsider refuses to run with an unresolvable `--preamble` and says so — if you see that message,
fix the path rather than dropping the seat, because the alternative is a seat that answers with no
brief at all.

Peregrinus is the one seat with no output contract you control, and the one that saw nothing but the
frame. **Name the agent that actually answered** — `outsider` prints it on the first line; a candidate
from a board member you cannot identify is not interpretable. Map its Section 2 onto the candidate
shape the others use, and carry its Section 3 — what looks off about the problem as stated — into
Phase 5 as cross-cutting material. That section is the most valuable thing a cold seat produces and it
is not a candidate, so nothing else in the flow would pick it up.

The leg is droppable: with no external agent CLI installed, or with `outsider` itself not installed,
the run continues without it. Say so in the report, and say how many generators actually ran — with
Librarius unselected that is **one**, and a single-generator board cannot show the design space was
explored. Prefer selecting Librarius in that case even if its trigger is weak.

When the generators return, print one line: `Diverge: 3 generators ran (Novator, Peregrinus/<agent>,
Librarius) -> 7 raw candidates`. Then assemble; do not dispatch a second wave of generators because
the set looks thin — Phase 4 is what tests it.

## Phase 3: Assemble the Candidate Set

Before the critics run, merge the generators' output into one numbered set. This is the orchestrator's
job and it is not clerical:

1. **Include candidate A** from the frame, described on the same terms as the rest.
2. **Merge near-duplicates.** Two candidates that differ only in naming or file layout are one
   candidate. Keep the clearer description and note both origins.
3. **Kill the non-candidates.** "Use something better" is not a candidate. Anything not concrete
   enough to start on is dropped, and the drop is reported.
4. **Strip attribution, by rewriting rather than by omitting.** Critics must not know which seat
   proposed what, or which one was already on the table — that is the bias the board exists to
   remove. Deleting seat names is not enough: prior-art candidates announce themselves ("adopt
   `<library>`"), and an existing plan reads in the house voice. Restate every candidate in one
   common voice at the same level of detail, and order them so the pre-existing approach is not
   first. You will still know which is which; the critics must not.

Announce the set headed by one line — `Candidate set: 4 (7 raw, 2 merged, 1 dropped)` — then one
line per candidate.

## Phase 4: Converge

**Dispatch all critics at once.** Each receives the frame and the full assembled candidate set, and
attacks it **comparatively** — this board ranks candidates, so an objection that hits every candidate
equally changes nothing about the ranking and must be labelled cross-cutting.

Prompts, with `{{FRAME}}` and `{{CANDIDATES}}` replaced:

- **Seneca** — `references/seneca-prompt.md`
- **Scrutator** (if selected) — `references/scrutator-prompt.md`
- **Censor** (if selected) — `references/censor-prompt.md`

On a host with no subagents, run each prompt in turn and never show one critic another's output. Say
in the report that they were not isolated — a sequential run leaks earlier objections into later ones.

When the critics return, print one line: `Converge: 2 critics ran -> 14 raw objections`.

### The Objection Contract

Every objection names four things, or it is not an objection:

- **Candidate** — which one it hits, or `cross-cutting`
- **Condition** — the circumstance under which it actually bites
- **Bearer** — who pays, named from this closed list and no other: `end user`, `operator`,
  `external consumer`, `implementer`, `maintainer`. Dedupe and ranking both key on this field, so
  free-text bearers make both unstable
- **Severity** — `Blocking` (rules the candidate out; cannot work, or the cost is unrecoverable),
  `Material` (candidate survives, trade-off gets worse), `Minor` (worth knowing, does not move the
  ranking)

An objection missing **both** a condition and a bearer is a **preference**: reported in its own
section, ranking nothing. Missing **one** of the two is an incomplete objection, not a preference —
supply the missing half if the candidate text supports it, and drop it if it does not.

`Blocking` requires a named bearer. A `Blocking` objection without one becomes `Material`, because an
unrecoverable cost nobody bears is not a reason to rule a candidate out.

## Phase 5: Consolidate and Verify

Critics over-report, over-rate, and file one insight three times. Cut that down first, then verify —
a board of six with nothing between an opinion and the report is six unchecked opinions.

**Consolidate:**

1. **Kill non-objections.** No named condition and no named bearer is a preference, not an objection
   — move it. An objection whose evidence quotes nothing from the frame or the candidate is an
   impression; drop it.
2. **Kill unproven halves.** An objection pairing a demonstrated claim with one nobody could
   demonstrate ships as the demonstrated claim alone. The weakest claim sets the credibility of the
   whole objection.
3. **Dedupe.** Two critics hitting the same candidate with the same objection is **one** objection at
   the higher severity. Independent corroboration is a strong signal — say so, and never let it look
   like two problems.
4. **Cluster.** If one change to a candidate answers several objections, report the root and nest the
   rest beneath it.
5. **Separate cross-cutting from discriminating.** Cross-cutting objections belong in the framing
   section — they say something about the problem, not about the choice. Peregrinus's Section 3
   observations join them here.
6. **Keep what you killed.** Pass the drops from steps 1 and 2 into verification marked `dropped`.
   Verification rules on them too, and a confirmed drop is worth more than an assumed one — the
   lenses sometimes find the stated reason for dropping was wrong.

Print one line when consolidation is done: `Consolidated: 14 raw -> 6 objections, 3 dropped, 2
preferences`.

**Verify:** dispatch the lenses from `references/verification-prompt.md`, all at once, one per lens.
Replace `{{LENS}}` with the lens name, `{{FRAME}}` with the Phase 1 frame, `{{CANDIDATES}}` with the
assembled set, and `{{OBJECTIONS}}` with the consolidated objections plus the drops — a lens told to
quote the candidate and judge against the frame's constraints needs all three in its prompt. Every
lens defaults to refuting what it cannot demonstrate, and each rules only within its own verdict
vocabulary.

| Lens | Question |
| ---- | -------- |
| `premise` | Is this objection about what the candidate actually proposes, or an invented version of it? Quote the candidate. |
| `bite` | Under what condition does it bite, and who pays? No condition and no bearer means it is a preference. |
| `escapability` | Can the candidate absorb this cheaply? An objection with a cheap fix is a design note, not a reason to rule a candidate out. |

**Merge rule.** An objection dies when `premise` shows it attacks something the candidate does not
propose, or when `bite` can establish neither a reachable condition nor an exposed bearer. Those two
lenses are the only ones that refute.

`escapability` never kills an objection. It demotes one to a **design note** on its candidate, along
with the specific adjustment that answers it. A design note does not rank, which means escapability
is the one lens that can keep a `Blocking` objection from ruling a candidate out — so it must state
the adjustment, and the report must carry it. An adjusted candidate is ranked as adjusted, and the
adjustment is named.

**Verification is not a downgrade pass.** An objection that arrives reasoned and leaves demonstrated
should come out *sharper*. A verify phase whose ratings only ever fall is miscalibrated. Verify the
reasoned ones hardest, and anything a critic rated confidently without evidence.

Print one line when the verdicts are merged: `Verification: 2 refuted, 1 narrowed, 1 demoted, 2
confirmed`. One pass of lenses, then synthesize — no second round, and no objections of your own
added at this stage.

## Phase 6: Synthesize

Read `references/synthesis-guide.md` and follow it. It covers ranking the candidates, choosing the
recommendation, when to override the board, the report format, and a filled-in report to match.

Before presenting, judge the board against your own broader context: dismiss what is wrong or
irrelevant, demote what is correct but insignificant, promote what matches a concern you already had,
and note the reasoning for any override. You have context no seat had — use it, and say when you did.

Then present the report and stop. Do not implement the recommendation, do not edit anything, and do
not offer to run a second board.

## Edge Cases

- **No external agent installed** — Peregrinus is skipped, the report says so. Never retry.
- **`outsider` itself not installed** — a different failure with the same symptom, and a real one:
  consilium ships in the review bundle while `outsider` ships in the assist bundle, so a host with
  only one of them installed has a core seat that cannot exist. Say which is missing, name the other
  bundle, and run the board without that seat.
- **Peregrinus times out** — note it and move on. If it timed out at 300s, the timeout was not passed.
- **Peregrinus ran unbriefed** — if its answer has none of the sections its prompt asks for, the
  preamble did not reach it. Discard the output rather than mapping it; an unbriefed answer looks like
  a candidate and is not one.
- **A seat fails** — note it in the report header and continue with what returned.
- **Only one candidate survives Phase 3** — valid, and worth saying plainly: report it as a decision
  with no live alternative, and say what was rejected and why.
- **All candidates carry a Blocking objection** — the honest report. Say the frame may be wrong and
  hand back the cross-cutting objections rather than picking a least-bad candidate.
- **No objections survive verification** — a valid outcome. Report the ranking on trade-offs alone
  and say the board found nothing disqualifying.
- **A finished plan with no open question** — it becomes candidate A and the board still generates
  alternatives. If it wins, that is the useful answer.
- **A diff was passed instead of a decision** — say what this skill is for, point at
  `changes-review`, and stop.
- **Every candidate came from one generator** — say so in the header. A single-generator run cannot
  show the design space was explored. Prefer selecting Librarius to avoid it, and re-run with a
  different frame if the candidates still feel narrow.
- **Only one critic ran** — permitted only under the exception in **The Seats**. Otherwise select
  Scrutator or Censor in Phase 3 and dispatch it.
