# Synthesis Guide

How to turn a board's output into a ranked candidate set and a recommendation. Read this after
verification, with the surviving objections in hand.

The board produced material; the ranking is yours. No seat saw the whole picture, and you have context
none of them had.

## Step 1: Apply the Verdicts

- `refuted` — the objection is gone. Keep it for the Dismissed section with the lens that killed it.
- `narrowed` — keep only the part the lens says survives, at the severity it justified.
- `demoted` — only `escapability` returns this. The objection becomes a **design note** on its
  candidate, carrying the specific adjustment that answers it. It does not rank, which is why the
  adjustment is mandatory: a demoted objection is only safe to set aside if someone can act on it. A
  `demoted` verdict with no stated adjustment is not a demotion — treat it as `confirmed`.
- `confirmed` — stands, at whatever severity the lenses justified. Take the `bite` lens's severity over
  a critic's: that is the actor-aware one.

Where lenses disagree, the one that read something in the repository outranks the one that reasoned.
Where both reasoned, take the more sceptical verdict — the board's failure mode is plausible objections
nobody could demonstrate.

## Step 2: Separate Cross-Cutting From Discriminating

An objection that hits every candidate equally says something about the **problem**, not about the
choice. It cannot rank anything. Move it into the framing section of the report and rank the candidates
without it.

If most surviving objections are cross-cutting, that is the headline: the frame is the problem, not the
candidate set. Say so before anything else.

## Step 3: Rank

For each candidate: what it buys, what it costs, what it forecloses, what it takes to leave, plus its
surviving objections and its design notes.

Then rank them on the frame's own success criteria. Rules:

- **A `Blocking` objection rules a candidate out** — unless `escapability` demoted it, in which case
  rank the candidate **as adjusted** and name the adjustment in its write-up. This is the only way a
  candidate survives a `Blocking` objection, so never apply it silently.
- **Re-rate by bearer before ranking.** Severity is a function of bearer and condition, never of how
  bad the mechanism sounds. Take the `bite` lens's bearer over a critic's — that is the one that
  checked. An objection borne by the `implementer` alone outranks nothing borne by an `end user` or an
  `external consumer`, whatever its stated severity.
- **Count `Material` objections, do not sum them.** Three shallow objections do not outweigh one that
  reaches an end user. Severity is about bearer and condition, and the ranking follows that too.
- **Reversibility breaks ties.** Two candidates close on merit rank by exit cost: the cheaper one to
  leave wins, because the board is deciding under uncertainty.
- **Never rank the approach that was already on the table above what its own objections justify.** It
  entered as a candidate. Being first is not a merit.

## Step 4: Choose, and Say What Would Change It

State the recommendation in one sentence and justify it against the success criteria in three.

Then name **what would change the answer**: the specific fact, constraint, or scale change that would
make a different candidate win. A recommendation with no such statement is an assertion, not a
decision — the reader needs to know which way the call is close.

## Step 5: Override Honestly

You may:

- Dismiss what is wrong or does not apply, saying which and why
- Demote what is technically right but practically insignificant here
- Promote what matches a concern you already had — and say that is what happened
- Overrule the ranking with context no seat had, stating the context explicitly

You may not silently drop a surviving objection or quietly reframe a candidate. Every override is
stated with its reasoning.

## Step 6: Report What the Run Actually Was

The reader must be able to discount the report correctly. Say in the header:

- Which seats ran, and which were skipped or failed
- **Which agent answered as Peregrinus**, by name. A candidate from an unidentifiable board member is
  not interpretable. If the leg was unavailable, say how many generators actually ran.
- Whether the run got **model diversity** (each seat on a different model) or **role diversity only**
- Whether the seats were isolated, or run sequentially on a host without concurrent dispatch

## Report Format

```markdown
## Consilium

**Decision**: <one sentence — what is being chosen>
**Board**: Novator, Peregrinus (<agent that answered>), Seneca[, + optional seats] — <N> generators,
<N> critics[, verification: <lenses that ran>]
**Candidates**: N — <one-word labels>
**Recommendation**: <candidate> — <one clause>
**Diversity**: model | role only[, sequential — seats were not isolated]

### The Decision

<Two or three sentences restating what is being chosen and under what constraints. Then the
cross-cutting objections: what every candidate shares, and what it means for the frame. If a shared
assumption is load-bearing and unverified, this is where it goes and it goes first. Peregrinus's
observations about the problem as stated belong here too — an outside reading that differs from the
inside one is a fact about the frame, not about any candidate.>

### Candidates

#### <N>. <Name>  <— recommended, where applicable>

<Two or three sentences: what it is and how it works.>

- **Buys**: <the specific advantage>
- **Costs**: <effort, complexity, operational burden>
- **Forecloses**: <what gets hard afterwards>
- **Exit**: cheap | moderate | expensive — <what leaving takes>
- **Objections**: <severity — one line each, with the condition and the bearer named>
- **Design notes**: <each demoted objection with the specific adjustment that answers it. Where an
  adjustment is what keeps a `Blocking` objection from ruling this candidate out, say so here.>

### Recommendation

<One sentence naming the choice, three justifying it against the success criteria. Name the strongest
objection against it and say why it does not change the answer.>

**What would change this**: <the specific fact, constraint, or scale change that makes another
candidate win — and which one>

### Preferences

<Objections with no condition or no bearer, one line each, attributed. Present because a reader may
share the preference — but they did not rank anything.>

### Dismissed

<Refuted objections, one line each, with the lens that killed them.>
```

## A Filled-In Report

One instance of the format above, so the shape is not left to interpretation:

```markdown
## Consilium

**Decision**: Where unsaved editor drafts live between the keystroke and the server write.
**Board**: Novator, Peregrinus (codex/gpt-5.6), Seneca, Censor — 2 generators, 2 critics,
verification: premise, bite, escapability
**Candidates**: 3 — debounced-server, local-first, session-buffer
**Recommendation**: 2. Local-first — survives an offline tab, and its exit cost is one migration
**Diversity**: model

### The Decision

We are choosing where a draft lives for the seconds between a keystroke and a durable write, under
an existing REST API we do not control and a hard requirement that a closed tab never loses work.
Two objections hit every candidate: none of them says what happens when two tabs edit the same
draft, and all three assume the server's `updatedAt` is authoritative, which nobody has checked.
Peregrinus read the problem as a conflict-resolution question rather than a storage question — an
outside reading worth taking seriously before the frame is treated as settled.

### Candidates

#### 2. Local-first  — recommended

Writes land in IndexedDB on every keystroke; a background task pushes to the server and reconciles
on `updatedAt`. The editor reads only from the local store.

- **Buys**: a closed or offline tab loses nothing; the editor never waits on the network
- **Costs**: a reconcile path, a store migration story, and a second source of truth to debug
- **Forecloses**: server-rendered draft previews, which would now read stale data
- **Exit**: moderate — drop the store, keep the push path, one migration to drain pending writes
- **Objections**: Material — a schema change strands drafts in an old store shape, borne by the
  end user, whenever a release changes the draft model
- **Design notes**: version the stored records and drain on upgrade (from `escapability`, cheap);
  this is what keeps the Blocking "silent data loss on upgrade" objection from ruling it out

### Recommendation

Take local-first. It is the only candidate that satisfies the no-lost-work requirement without a
change to the API we do not control, its exit cost is a single migration, and the offline case it
buys is the one the support tickets are about. The strongest objection against it — two sources of
truth are harder to debug — is real and does not change the answer, because the alternative puts
the same divergence on the network instead of in a store we can inspect.

**What would change this**: if multi-tab editing becomes a requirement, session-buffer wins — it
already serializes through one connection, and local-first would need a leader election to match.

### Preferences

- Candidate 1: "debouncing at 400ms feels laggy" — no condition and no bearer named.

### Dismissed

- Candidate 3: "session storage is capped at 5MB" — refuted by `premise`; the candidate stores
  a diff, not the document.
```

## Degradation

- **A seat failed** — say so in the header and continue. Do not speculate about what it would have
  found.
- **Peregrinus unavailable** — say how many generators actually ran: two with Librarius selected, and
  **one** without it, which is the common case. Note that the run has no cold framing — every candidate
  came from inside this conversation's context — and that a single-generator board cannot demonstrate
  the design space was explored.
- **One critic ran** — say so. With only Seneca, nothing assessed reach or cost, and the ranking rests
  on framing alone.
- **All critics failed** — present the candidate set with its trade-offs and state plainly that nothing
  attacked it. Do not present a recommendation as though it survived scrutiny.
- **Only one candidate survived** — report it as a decision with no live alternative, list what was
  ruled out and by what, and say plainly that the board did not find a real choice.
- **Every candidate carries a `Blocking` objection** — do not pick a least-bad candidate. Report that
  the frame may be wrong, lead with the cross-cutting objections, and say what a better frame would
  have to account for.
- **Nothing survived verification** — a valid outcome. Rank on trade-offs alone and say the board found
  nothing disqualifying, which is information about the decision's difficulty.
