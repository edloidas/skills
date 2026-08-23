# Where the rules in this skill come from

Three runs of this skill were followed to an outcome — a maintainer's commits in the first, a
browser-checkable result in the second, a published comment and the author's response in the third.
Every rule in `SKILL.md` that looks arbitrary is here with the observation that produced it. Read
this when deciding whether to change one of them.

## Run 1 — a platform PR, reviewed against a long requirement

An admin events websocket hub: 12 files, ~1900 lines, Java and TypeScript in an OSGi/Gradle
monorepo. Five finders, then three verification lenses added by hand. The maintainer replied and
pushed 11 commits, so every finding has a real verdict.

- 9 of 11 substantive findings landed.
- **Zero of three `critical` ratings survived verification.** Every downgrade came from the
  reachability lens.
- Verification killed 3 findings and re-rated 9 downward.
- Every finding backed by a run-it-yourself proof was accepted without argument. Every finding
  argued from reasoning alone drew pushback.
- One finding stayed `critical` until the words *installed application code* were written next to
  it — on that platform, application code is already fully trusted.
- The one dismissal was dismissed as "this is why it is deprecated". Framed as a question about
  whether that is acceptable, it would have survived.
- Two findings filed as unrelated minors were one structural insight; the maintainer fixed both in a
  single commit.
- One finding led with the impressive half — an outbound payload leak the redesign then deleted —
  and buried the inbound half, which survived.
- One finding paired a fully traced trigger path with an unverified alternative. The maintainer
  rebutted precisely the unverified half.
- A requirement deviation flagged as drift turned out to be a decision made across three deliberate
  commits on the branch.

## Run 2 — a component-library PR, every finding checkable in a browser

Shadow DOM support: 36 files, ~650 lines, a Preact component library. Three finders, 14 merged
findings, then a re-verification pass.

- 5 findings were established by execution, 9 by reading.
- **Both findings dropped in re-verification were reading-only, and no measured finding was dropped
  or downgraded.** Two more reading-only findings were downgraded.
- The measured findings left verification with *tighter* claims and *higher* severity — the opposite
  of run 1, where verification only ever deflated.
- Both drops had a concrete, reproducible mechanism and were still worthless: no actor could
  construct the conditions. Concreteness and reachability are orthogonal.
- The PR shipped its own regression story, whose helper copied the document's stylesheets without
  removing them — so the exact failure the story existed to catch could not appear in it.
- Reading one real downstream consumer surfaced three findings no reviewer had, and killed two by
  establishing how the library is actually embedded.
- Two probe techniques did the work: register a novel identifier so ambient state cannot mask the
  result, and remove the ambient condition so the real symptom appears.

## Run 3 — a component-library PR, published to the author

A Combobox mobile-keyboard fix: 3 files, ~145 lines, a Preact component library. Two rounds, both
published as written comments rather than findings lists. Round one raised two findings plus a
rider; the author force-pushed a fix for all three and each was confirmed fixed on re-review. Round
two ran three finders, merged to 7 findings, put them through a separate cold triage pass, and
published 4.

- **The triage pass returned 3 relevant, 3 partial, 1 not relevant.** Three of seven would have
  damaged the review's credibility if published as found.
- **The finding rated `critical` was the most wrong one.** It claimed `click` never carries
  `pointerType` in any browser. Measurement refuted it outright — a real click arrives as a
  `PointerEvent` with `pointerType` of `touch` or `mouse`. The true residue was narrower and still
  worth publishing: WebKit only shipped a truthful `pointerType` on `click` in Safari 18.2, so on iOS
  16 and 17 the fix is a no-op. Same line of code, different claim, different severity.
- One finding reported the value button focusing the input on tap. That is untouched base code and
  the issue asks for exactly that behavior. A reviewer blind to the base cannot know this; publishing
  it would have asked the author to defend their own spec.
- One finding blamed a story description for asserting viewport clamping the positioning hook does
  not implement. True, but the missing clamp is pre-existing and only the description is new on the
  branch. Published unattributed it reads as a regression the author caused.
- Two of the seven were overturned or narrowed on the attribution axis alone.
- The Safari finding could not be reproduced on the reviewer's machine at all. It shipped with a
  console snippet dispatching a plain `MouseEvent` — the event shape those Safari versions deliver —
  and that is what made it land. Screenshots do not transfer into a PR comment; measured numbers and
  runnable snippets do.
- The clipped-submenu finding shipped as *"the 280px submenu spans 295 to 575 on a 320px-wide
  viewport"* plus a sentence on what you see.
- Round two withdrew its own earlier suspicion in the published text: *"That one was mine, not the
  branch's."*
- Three findings about the same unrelated block of stories published as **one** section with the
  other two as reasons not to land it.
- One finding was named as needing a change before ship; the rest were handed over as judgement
  calls with a suggested fix and no verdict.
- A "checked and clear" section drew no response beyond the closing sentence, matching run 2.
- The published comment ran four sections and roughly 900 words for a 145-line diff — the observation
  behind the per-kind length budget, since nothing in the rules capped it.

## Which rule each observation justifies

| Rule in `SKILL.md` | Evidence |
| ------------------ | -------- |
| Severity is a function of actor and failure | Run 1: zero of three criticals survived; the actor decided every one |
| Only refutation, unreachability or a spec kill removes a finding; severity moves either way | Run 2: measured findings came out sharper. A verify phase whose ratings only fall is miscalibrated |
| Verify reasoning-only findings first | Both runs: every finding killed in verification was reasoned; no measured finding died |
| Say whether a finding was measured or reasoned | Run 1: measured findings were accepted without argument, reasoned ones drew pushback |
| Non-goals before hunting | Run 1: the killed finding was refuted by the requirement's own non-goals section |
| One claim per finding | Run 1: the rebuttal landed exactly on the unverified half |
| Cluster by root cause | Run 1: two minors were one insight, fixed in one commit |
| Deprecated surfaces are decisions, not defects | Run 1: the sole dismissal, dismissed as deprecated |
| Lead with the consequence, not the wrong value | Run 1: the buried half was the durable one; consumer-framed findings got real fixes |
| Check a shipped fixture exercises its own path | Run 2: the regression story hid the bug it existed to catch |
| Read a real consumer for library changes | Run 2: three findings surfaced, two killed |
| The two probe techniques | Run 2: what turned the strongest finding into a number |
| A second cold reviewer buys more than a second intent reviewer | Run 1: two cold reviewers diverged usefully; the second intent reviewer duplicated the first |
| Reviewers stall on wide diffs; relaunch narrowed | A 23-file, two-repo run where both native reviewers went quiet and needed a narrowed file list and a tool budget |
| The caller owns rounds and the accepted-findings list | A seven-round session: yields 5 → 7 → 4 → 2 before a round returned nothing, with three findings knowingly accepted in round 4 and re-found afterwards |
| Publication judges where the report does not | Run 3: 3 of 7 findings would have cost the review its credibility if passed through unjudged |
| Attribute against the base before publishing | Run 3: two findings overturned or narrowed on attribution alone, both reading as regressions otherwise |
| No demonstration, no section | Run 3: the highest-rated finding rested on a false premise measurement refuted in one line |
| A reproduction that survives into a comment | Run 3: the Safari finding was unreproducible on the reviewer's machine and landed on a console snippet |
| Withdraw the review's own errors in the published text | Run 3: both rounds withdrew explicitly, and the concession is what made the rest credible |
| Per-kind length budget, four sections maximum | Run 3: four sections and ~900 words for a 145-line diff, with no rule capping it |
| A clean run is one closing paragraph, never a section list | Runs 2 and 3: the "checked and clear" section drew no response either time |
