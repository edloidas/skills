# Where the rules in this skill come from

Four runs of this skill were followed to an outcome — a maintainer's commits in the first, a
browser-checkable result in the second, a published comment and the author's response in the third,
and the second run published as a review on someone else's branch in the fourth.
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

## Run 4 — run 2, published as a review

The same shadow-DOM pull request as run 2, on a colleague's branch rather than the reviewer's own, so
publication was a GitHub review rather than an issue comment. Run 2's 14 merged findings went out as
**8 inline comments plus a body**, verdict `REQUEST_CHANGES`.

- **14 findings became 8 comments.** Three minors were grouped into a single comment opening `Three
  small ones, grouped.` A reader counts comments, and the grouping is what kept the review readable.
- Every comment was anchored to the line its finding was about, across six different files. None was
  parked on a convenient nearby line.
- **The body repeated no finding text.** It carried standing, the grouping, the exclusion, and the
  blockers — nothing else. Every measurement and reproduction lived in the inline comment it belonged
  to.
- Standing named the **method**, not the effort: *"reading computed styles rather than class names"*.
  That clause is the reason the rest is believable.
- It conceded first, at length — the portal plumbing, the theme class, the scroll fix all confirmed
  working — before any defect appeared.
- It stated what it deliberately excluded and why: the run started on an earlier commit, so the
  reverted `.light` token selector was out of scope and said so.
- **Two findings were named as blocking, in prose, in the body** — which is where severity survived
  once the labels were gone. The API verdict said the same thing a second time.
- Findings that were scope gaps quoted the issue with `>` blockquotes rather than paraphrasing what
  it asked for.
- One finding explicitly refused to argue against the change it was about: *"this is not an argument
  against the change, only the other half of it."*
- One handed the decision over outright: *"this second one is arguably the embedder's problem rather
  than the library's, so I will leave the call with you."*
- An AI attribution footer was applied because the target repo prescribed one. Reading the four runs
  back, no reader ever engaged with it and the operator eventually asked for it gone everywhere — the
  case that retired repo-local footer resolution rather than the case that justified it.

## Run 5 — run 3's pull request, third pass, approved

The combobox pull request from run 3, re-reviewed after the author addressed two rounds of
`CHANGES_REQUESTED`. Every prior finding verified as fixed and nothing blocking survived, so the
verdict was `APPROVE`. The first draft was rejected by the operator, and each rejection is a rule.

- **The gate showed a summary, not the text.** The draft described the review — two inline comments,
  what each was about, the body's shape — and asked to post. The operator asked three times to see
  the actual words. Approving a description of correspondence is not approving the correspondence.
- **The question was asked through `AskUserQuestion`.** "It just hurts" — the modal fired before the
  report it interrupted had been read, so the reader was choosing before they had the basis to
  choose. One question, in prose, at the end.
- **The verdict was a header at the top.** It scrolled away above the evidence. Moved to the last
  line, where the reader looks for it.
- **The approval carried two inline comments and a WebKit measurement table.** Both notes were real
  and neither was blocking; anchored to an approved diff they asked the author to reopen settled
  code. Withheld, reported to the operator as their own block, and the review shrank to four
  paragraphs — which is what an approval is.
- **The verification record was in the review.** Engines, a 60-case story matrix, `pnpm check`
  clean. The operator's note was that the author sees CI and does not need the method: *"this is
  okay to write it as a report for me, but keep it out of review."*
- The one technical paragraph that survived into the body was kept because the change turned on it —
  WebKit reporting a touch-generated click as `pointerType: "mouse"` is why the author's approach was
  right. Not how it was measured; why it matters.

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
| One inline comment per finding, minors grouped into one | Run 4: 14 findings published as 8 comments, and the grouping is what kept it readable |
| The review body is a map, not a summary | Run 4: the body repeated no finding text; every measurement stayed on the line it belonged to |
| The verdict follows from whether a blocker survived | Run 4: two findings named as blocking in prose, `REQUEST_CHANGES` saying it again |
| Standing names the method, not the effort | Run 4: "reading computed styles rather than class names" is why the rest was believable |
| Say what was deliberately excluded | Run 4: the run started on an earlier commit, and the reverted selector was called out as out of scope |
| Never anchor a finding to a convenient nearby line | Run 4: eight comments across six files, each on its own finding's line |
| Never an AI attribution footer | Run 4 applied one on repo-local policy; it earned no response, and the policy is retired |
| The gate shows the text verbatim, never a summary | Run 5: the operator asked three times to see the actual words before approving |
| One question, in prose, at the end | Run 5: the `AskUserQuestion` modal fired before the report it interrupted had been read |
| The verdict goes last | Run 5: as a top header it scrolled away above the evidence justifying it |
| `APPROVE` carries no inline comments | Run 5: two non-blocking notes anchored to an approved diff asked the author to reopen settled code |
| Method and measurement stay out of an approval | Run 5: *"okay to write it as a report for me, but keep it out of review"* |
| Non-blocking suggestions are withheld and reported | Run 5: withholding both shrank the approval to four paragraphs |
