# Where the rules in this skill come from

Two runs of this skill were followed to an outcome — a maintainer's commits in one case, a
browser-checkable result in the other. Every rule in `SKILL.md` that looks arbitrary is here with the
observation that produced it. Read this when deciding whether to change one of them.

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
