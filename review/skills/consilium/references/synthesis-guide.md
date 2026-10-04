# Synthesis Guide

How to turn a board's output into a ranked candidate set, a recommendation, and a report. Read this
after verification, with the verdicts in hand.

The board produced material; the ranking is yours. No seat saw the whole picture, and you have context
none of them had. The report is read twice: by the user now, and by this session's agent for the rest
of the work. Keep what either of them will act on; cut the rest.

## Step 1: Apply the Verdicts

Each objection has one `holds`-lens verdict and one `escapability`-lens verdict.

| `holds` lens | `escapability` lens | In the report |
| ------------ | ------------------- | ------------- |
| `refuted` | any | Dismissed, one line, with what refuted it |
| `holds`, `narrowed`, or `unknown` | `stands` | **Against it** on the candidate, at the lens's severity |
| `holds`, `narrowed`, or `unknown` | `design-note` | **Design note** on the candidate, carrying the adjustment |

- `narrowed` keeps only the part the lens says survives.
- `unknown` keeps the critic's severity and is marked `(unsettled)`.
- A verdict of `refuted` or `narrowed` without a `pointer` or `quote` breaks the evidence rule — treat
  it as `unknown`.
- A `dropped` objection that the `holds` lens rules `holds` is reinstated and placed like any other;
  one it rules `refuted` stays dropped and is not reported.

## Step 2: Separate What Holds for Every Option

An objection or verified fact that hits every candidate equally cannot rank anything. It goes in **Facts
that hold for every option**, with how it was verified. If most surviving objections land there, the
frame is the problem — say so before anything else.

## Step 3: Rank

Rank on the frame's own constraints and success, best first. Rules:

- **A `Blocking` objection that stands rules a candidate out.** A `Blocking` one answered by a design
  note does not — rank the candidate as adjusted and name the adjustment.
- **Re-rate by bearer.** An objection borne by the `implementer` alone outranks nothing borne by an
  `end user` or `external consumer`, whatever its stated severity.
- **Count `Material` objections, do not sum them.** Three shallow ones do not outweigh one that reaches
  an end user.
- **Every candidate has to beat C0.** If none does, C0 wins, and that is a valid answer.
- **Ties break towards cheaper exit, then towards the simpler candidate** — the earlier Occam rung, or
  the one with less new machinery.
- **The approach that was already on the table earns nothing for being there.**
- **Convergence is a signal, not a vote.** Several seats reaching one candidate independently means it
  is the obvious answer, not the right one. A candidate only one seat produced can still win.

## Step 4: Choose, and Say What Would Change It

State the recommendation in one bold sentence and justify it in two or three. Name the strongest
objection against it and why it does not change the answer. Then **what would change it**: the specific
fact, constraint, or scale that makes another candidate win, and which one. Cite question ids where a
question is that fact.

When an open question's answer would change the winner, the bold sentence carries the flip itself —
`Keep C1 — unless <question as a condition>, then C2.` A reader who stops at the decision must not
miss the one answer that reverses it.

## Step 5: Open Questions

Merge the generators' `question` records, Seneca's assumption questions, and every hedged preference
from the frame. Keep only questions whose answer changes which candidate wins; at most four. Each
carries the answer the board assumed, so the report reads the same whether the user is there to answer
or another skill is running unattended:

`- **Q1. <question>** Assumed: <the answer the ranking used>. → if not: <what wins or drops out>`

## Step 6: Override Honestly

You may dismiss what is wrong, demote what is insignificant, promote what matches a concern you already
had, and overrule the ranking with context no seat had. Every override is stated with its reason. You
may not silently drop a surviving objection or quietly reframe a candidate.

## The Run Line

One line under the title, so the reader can discount the report correctly: the generators and critics
that ran, **which agent answered as Peregrinus**, the counts from candidates to verdicts, and anything
that degraded the run — a failed or skipped seat, a single generator, no model diversity, critics run
sequentially rather than isolated.

## The Full Report

The default, including when another skill invoked consilium. Write it in the conversation's language.
Options appear best first as plain bold-headed bullets, not a numbered list — the `C` ids carry the
identity and the order carries the rank. The decision is always last.

````markdown
## Consilium · <subject>

Run: <generators> · <critics> · <N> options · <N> objections → <N> stand, <N> design notes, <N> refuted

### Frame
- **Deciding:** <one sentence>
- **Hard constraints:** <a (source) · b (source)>
- **Taken as a preference, not a rule:** <the hedged wish, quoting the user's word> — <Qn> asks.
- **Current state (C0):** <what exists and what it lacks>
- **Outside reframe (<agent>):** <only if Peregrinus read the problem differently>

### Facts that hold for every option
- <fact, and how it was verified>

### Options, ranked

**C<n> · <name>** <— recommended, where applicable>
- Buys: <specific advantage>
- Costs: <effort, complexity, burden>
- Against it — <severity>, <bearer>: <what stands>
- Design notes: <adjustment · adjustment>

### Open questions
- **Q1. <question>** Assumed: <answer>. → if not: <what flips>

### Ruled out
- **C<n> · <name>.** <severity>, <bearer>: <why>. <Found by N critics independently, where true.>
- Dismissed: <refuted objection> (<what refuted it>).

---

### Decision
**<one sentence — and, if an open question would change the winner, "unless <condition>, then C<n>">**

<two or three sentences: why, against the constraints; the strongest objection and why it does not change the answer>

**Would change it:** <fact or Qn → C<n> · fact → C<n>>

**Next:**
1. <step>
````

### A Filled-In Full Report

````markdown
## Consilium · tower asset storage

Run: 3 generators (Novator, Occam, Peregrinus/codex) · 2 critics (Seneca, Censor) · 5 options · 24 objections → 5 stand, 11 design notes, 1 refuted

### Frame
- **Deciding:** where tower's runtime binaries (GLB, textures, audio) live and how they reach `dist/` with hashed URLs, as assets grow past today's 7 KB model.
- **Hard constraints:** startup assets are mandatory (issue #7) · catalog keys are a save-file contract (issue #7, `docs/direction.md`)
- **Taken as a preference, not a rule:** "binaries should stay out of git" (you wrote *probably*) — Q1 asks.
- **Current state (C0):** `tower.glb` is committed under `src/`, imported with `?url`, typed in `catalog.ts`. Works; nothing checks size or naming.
- **Outside reframe (codex):** the real question is how a clean checkout gets the exact bytes of a release. Storage follows from that.

### Facts that hold for every option
- Vite inlines `?url` files under 4 KB as `data:` URLs — read in the installed `shouldInline`. Set `build.assetsInlineLimit: 0` with the first small texture.
- In app builds Vite emits a Git LFS pointer file as if it were the asset, so CI goes green while shipping a broken game.

### Options, ranked

**C1 · C0 hardened: git + `?url` + typed catalog + contract test** — recommended
- Buys: a fresh clone builds with no secrets; a missing file is a bundler error; keys are typed; no new build code.
- Costs: every re-export stays in git history; catalog edits are code edits.
- Against it — Material, maintainer: history grows with each re-export, and LFS is a second project here (not installed, no `lfs:` in CI, private-repo quota).
- Design notes: size budget from a real projection · contract test in pre-commit.

**C2 · External content-addressed store + committed hash lockfile**
- Buys: git stays small at any volume and every commit still pins exact bytes.
- Costs: a store account, credentials on every machine and in CI, a network step in the 10-minute job.
- Against it — Material, operator: infrastructure and credentials for 7 KB of assets today. Structural.
- Design notes: keep a second copy of the blobs.

**C3 · JSON catalog + in-repo Vite plugin**
- Same storage as C1, plus plugin code. Its one gain, a catalog plain Node can read, has no consumer yet.
- Against it: nothing above Minor after verification.

### Open questions
- **Q1. Is "no binaries in git" a hard rule?** Assumed: a preference. → if a rule: C1 and C3 are out, C2 wins.
- **Q2. What runtime volume do you expect once audio lands?** Assumed: under 100 MB. → if above: C2 wins.

### Ruled out
- **C4 · gitignored folder synced from local resources.** Blocking, operator: the repo alone cannot build a deployable game, and the only copy of the assets is one machine. Found by both critics independently.
- Dismissed: "the LFS guard lands too late" (the candidate already sequences it).

---

### Decision
**Keep C1: runtime exports in git, source art outside it — unless "no binaries in git" is a rule, then C2.**

It is the only option where a fresh clone builds and a missing startup asset fails the build with no new machinery, and every call site goes through `AssetKey`, so storage can move later without touching game code. History growth is the strongest objection; it does not change the answer today, but it dates the decision to the first audio slice.

**Would change it:** Q1 = a rule, or Q2 = above 100 MB → C2 · a second contributor or a Node consumer of the catalog → C3.

**Next:**
1. Add the contract test (orphans, kebab-case names, size budget, frozen keys).
2. Set `assetsInlineLimit: 0` in the first slice with a sub-4 KB asset.
3. Record the decision in `docs/direction.md`.
````

## The Concise Report

When `short`, `concise`, or `summary` was passed, or when the user asks for a shorter version of a full
report already presented. It is for the user to make the call: every live option stays visible, each in
one or two plain sentences with a verdict tag first, best first. Ruled-out options get one line. No ids,
no severities, no bearers — say who pays in plain words. The pick is last.

````markdown
### Options
- **<option in plain words>** — *recommended.* <what it is and why it works>. <what it costs>.
- **<option>** — *the move for later | not yet | viable.* <one or two sentences>.
- **<option>** — *out.* <why, in one sentence>.

### Needs your call
- **<question>** <why it matters, and what flips>.

### Fix soon, whatever you pick
<only if a fact holds for every option and needs action>

---

**Pick: <one sentence>.** <when to revisit, if anything dates it>
````

### A Filled-In Concise Report

````markdown
### Options
- **Keep in git, as now** — *recommended.* Cloning the repo is enough to build the game, and a missing file stops the build instead of shipping something broken. The cost is git history: every re-exported model stays there for good.
- **Outside store + hash lockfile in git** — *the move for later.* Git stays small forever and each commit still knows exactly which files it used. Today it means a storage account and CI credentials for one 7 KB model.
- **JSON catalog + Vite plugin** — *not yet.* Same storage plus plugin code, for a benefit nothing uses yet.
- **Gitignored folder (your idea)** — *out.* The repo alone could no longer build the game, and the only copy would sit on your machine.

### Needs your call
- **Is "no binaries in git" a rule or a preference?** You wrote "probably", so the board treated it as a preference. If it is a rule, the outside store wins.
- **Expect more than ~100 MB of assets once audio lands?** Then the outside store wins too.

### Fix soon, whatever you pick
Vite puts files under 4 KB straight into the JS bundle. Set `assetsInlineLimit: 0` when the first small texture lands.

---

**Pick: keep the game's exports in git, source art in `~/dev/tower`.** Revisit at the first audio slice, with real sizes.
````

## Degradation

Say each of these in the run line, and where it matters, in the Frame:

- **Peregrinus unavailable** — the run has no cold reading; every candidate came from inside this
  conversation's context.
- **A single generator ran** — the design space was not shown to be explored.
- **A critic failed** — name what nothing checked: framing without Seneca, cost and reach without
  Censor. If both failed, present the options with their trade-offs and say plainly that nothing
  attacked them; do not present the recommendation as though it survived scrutiny.
- **Only C0 and one candidate survived** — report it as a decision with no live alternative.
- **Every candidate carries a standing `Blocking` objection** — do not pick a least-bad one. Lead with
  the facts that hold for every option and say what a better frame would have to account for.
