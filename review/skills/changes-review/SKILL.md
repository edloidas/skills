---
name: changes-review
description: >
  Attack a code change and report what survives. Dispatches independent reviewers in parallel,
  each with a single job and no access to the implementer's reasoning: one hunts correctness bugs
  blind to the issue, one hunts requirement gaps against the issue text, one runs outside the
  process entirely. Optionally re-attacks its own findings before reporting, then synthesizes what
  is left. Returns findings and changes nothing — no tooling, no autofix, no edits, no posting.
  Use before committing, when you want a change attacked rather than assessed, or as the find step
  behind a fix pass or a PR review skill. Every phase is configurable by the caller.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash(git:*) Bash(gh:*) Read Glob Grep Task Skill
argument-hint: "[--base <branch> | --uncommitted | --commit <sha>] [--issue <N>] [--mode <simple|standard|deep>] [--no-external] [--no-lens]"
metadata:
  author: edloidas
---

# Changes Review

Attack a change from several directions at once and report what survives. This skill **finds**;
it never fixes, never runs tooling, never touches the working tree, and never posts anywhere.

It is a primitive. Whoever calls it — a person, a PR workflow, an issue workflow — gets the same
three stages, find, verify, synthesize, and configures them rather than forking the behavior.
Anything needing the pull request itself, the project's architecture, a round loop, or a published
comment belongs to the caller, not here.

## The premise

The agent that wrote the code wants it accepted. A reviewer that shares its context inherits its
blind spots — it reads the implementer's reasoning, finds it persuasive, and confirms the work. So
every reviewer is dispatched **cold to the implementer's reasoning**: no plan, no rationale, no
commit message body, no prior-round findings, no account of why the change looks the way it does.

The bugs this catches are the ones that compile and pass lint — premature drops, floor-vs-truncate
on negative numbers, eager evaluation where laziness was meant. Tooling cannot see them and a
context-rich reviewer rationalizes them away.

Conventions and cleanup are **not** this skill's job. A reviewer told to find bugs *and* tidy the
code softens into a quality reviewer and stops finding bugs. Style, naming, comment noise, and
convention drift belong to a cleanup pass, and this skill will not report them.

## Configuration

| Setting | Flag | Default |
| ------- | ---- | ------- |
| Scope | `--base <branch>` / `--uncommitted` / `--commit <sha>` | Uncommitted changes; the last commit when the tree is clean |
| Requirement | `--issue <N>` | Auto-detected (Phase 2) |
| Mode | `--mode <simple\|standard\|deep>` | `standard` for `--base`, `simple` for a single commit or an uncommitted diff |
| External reviewer | `--no-external` | On whenever a third-party CLI is available |
| Stack lenses | `--no-lens` | On whenever the diff matches a lens (Phase 3) |

**Mode is the one dial.** It sets how many reviewers run and how hard the findings get verified,
because those two scale together — there is no useful run with four reviewers and no verification.

| Mode | Reviewers | Verification |
| ---- | --------- | ------------ |
| `simple` | 2 — cold and intent; the external leg is dropped first, since it is the one that cannot read the repo | `reachability` only |
| `standard` | 3 — cold, intent, external | all three lenses |
| `deep` | 4 — two cold on different models, intent, external | all three lenses, the killed claims too, and a synthesis critic on the assembled report |

With no requirement resolved, `simple` is one reviewer and `standard` is two — the intent reviewer
needs something to check against. Verification always runs; the mode sets its depth, not whether it
happens, and it roughly doubles the run, which is why the default follows the scope.

A late round in a fix loop is a `simple` run over the fix: small diff, spec settled two rounds ago,
and reachability is the lens that still changes the outcome. A whole branch reviewed cold is
`standard`. `deep` is for a large change or a high cost of missing something — two cold reviewers on
different models diverge usefully, where a second intent reviewer mostly repeats the first.

Every rule here that reads as arbitrary has an observation behind it, recorded with its outcome in
`references/calibration.md`. Read that before loosening one.

Two things only a calling skill can supply:

- **System facts.** Who can execute code in this system, what is already privileged, which
  surfaces are deprecated or unsupported. A caller that knows the platform should say so. These
  facts reach **only the reachability verifier** — never a finder, which stays cold. Without them
  the verifier works out what it can from the repo.
- **The requirement**, when the caller already resolved it. Pass the issue text, not a summary of
  it, and never the implementer's account of the diff.

A caller must not pass a plan, a rationale, a previous round's findings, or a description of what
the change is trying to do. Those defeat the premise, and this skill cannot detect that it happened.

**Round loops belong to the caller.** This skill reviews once and stops. A caller looping should pass
the fix itself as the scope on rounds after the first — the snapshot commit, or `--base` against it —
rather than re-reviewing a whole branch to check a two-line change. It also has to keep its own list
of findings it consciously accepted: reviewers here are blind to previous rounds by design, so an
accepted decision is found again every round and only the caller can recognize it.

## Phase 1: Resolve scope

Resolve the diff and the file list once, up front. Every reviewer sees the identical change set.

```bash
git diff --name-only HEAD                    # tracked modifications
git ls-files --others --exclude-standard     # new untracked files
```

Filter out `*-lock.*`, `dist/`, `build/`, `.next/`, `*.min.js`, `*.map`, `*.d.ts`.

**Trivial diffs** — only version bumps, formatting, or lock files → print
`Trivial changes only. Nothing to attack.` and stop. Do not spend reviewers on them.

**Dirty tree under `--base`.** `git diff <base>...HEAD` excludes uncommitted work, so a dirty tree
means the reviewers judge a change set that is not what exists on disk. Say so and review
`<base>...HEAD` plus the uncommitted diff together, or ask the caller to commit first.

Announce the resolved scope in one line: `Attacking 6 files, 240 lines (base: master).`

Do not read the project's architecture here. Establishing how the system is built is another
skill's job, and doing it in this phase would leak into the finders.

## Phase 2: Resolve the requirement

Only the intent reviewer uses this. Resolve it before dispatch:

1. `--issue <N>` was passed → `gh issue view <N> --json title,body`
2. Current branch matches `issue-<N>` → same, with that number
3. An open PR exists for the branch → `gh pr view --json title,body,closingIssuesReferences` and
   prefer the linked issue's body over the PR description
4. Last commit message contains `#<N>` → same, with that number

Take the issue **description** only. Exclude comments the agent itself posted during this run —
they are the implementer's reasoning wearing a different hat.

If nothing resolves, print `No requirement found — running the cold reviewer only.` and skip the
intent reviewer. Do not invent a requirement from the diff; a reviewer checking a change against a
requirement inferred from that same change finds nothing.

## Phase 3: Dispatch reviewers

**Launch every reviewer at once so they run concurrently.** They must not see each other's output.
Do not summarize the change for them, do not explain what it is trying to do, and do not pass along
anything from a previous round.

Choosing models, stated as intent rather than as names, since the roster changes and each host names
its own:

- Give each reviewer the **most capable model the host offers**. If that is the model running this
  skill, take the next tier down — a reviewer on the orchestrator's own model shares whatever the
  orchestrator already believes about this change.
- Where the host lets you pick a model per reviewer, **give each a different one**. Same-model
  reviewers differ only by sampling; same-role reviewers only by phrasing. Where it does not, run the
  default and say so: role diversity survives that, model diversity does not.

On a host with no subagents, run each prompt in turn and never show one reviewer another's output.
Say in the report that they were not isolated — a sequential run leaks earlier findings into later
ones.

### Reviewer 1 — cold (always)

Dispatch a reviewer that hunts correctness bugs and returns findings in the shape its prompt
specifies. Prompt: the contents of `references/cold-reviewer-prompt.md`, then the diff.

Repo-aware and issue-blind: it may read callers, types, and tests, but the prompt forbids fetching
the issue or PR. That prohibition is a soft guard, not a sandbox. It holds in practice because the
reviewer is never handed an issue number and has no reason to hunt for one. Do not put the issue
number in its prompt, not even in passing.

### Reviewer 2 — intent (whenever a requirement resolved)

Dispatch a reviewer that hunts requirement gaps and returns findings in the shape its prompt
specifies. Prompt: `references/intent-reviewer-prompt.md` with `{{REQUIREMENT}}` replaced by the
resolved issue title and body, then the diff.

### Reviewer 3 — second cold (`deep` mode only)

The same cold prompt on a different model. Two cold reviewers on different models produce
meaningfully different findings; a second *intent* reviewer largely duplicates the first, so depth
is bought with another bug hunter, never another requirement checker.

### External reviewer (`standard` and `deep`, when available, unless `--no-external`)

A model family outside this process entirely, via a CLI.

Invoke it through the collection's external-agent skill, `/outsider`, rather than calling a script by
path — a repo-relative path resolves only inside one checkout. That skill picks an installed agent CLI
that is not the host running this skill, so the reviewer is both a different model family and a
different process. The leg is optional: with no external agent available the run continues without it
and the report says so.

Tell `/outsider` to run **review** mode and pass it exactly three things:

- `--host <the agent you are>`, so it does not select the host and review its own work
- **the scope this run resolved in Phase 1**, as the matching scope flag — `--uncommitted`,
  `--base <branch>`, or `--commit <sha>`. A different scope means Phase 4 dedupes two different
  change sets, which is worse than skipping this reviewer
- a timeout of `540`, with the surrounding command timeout set to its maximum

Do not retry, and never block on it. A missing CLI is a skipped leg, not a failed run: the skill
reports why and exits cleanly, and the report notes the reviewer was unavailable.

This leg only ever gets a piped diff, so it is structurally cold — good at internal contradictions in
the diff, prone to asking for context it cannot see. Weight it accordingly, and never upgrade its
confidence to match a native reviewer's.

It is the one reviewer with no output contract you control. Map each finding onto the fields the
native reviewers return: claim, location, actor, severity, confidence, defect, cases. Missing severity
or confidence becomes `moderate` / `low`; a missing actor is resolved in Phase 6, not guessed here.

### Stack lenses (when the diff matches, unless `--no-lens`)

The reviewers above are stack-agnostic on purpose. A lens adds the one thing they cannot carry:
a catalog of failure modes specific to a library, deep enough that it would drown a general prompt.

Match the resolved file list against this table and dispatch a lens for each row that hits:

| Diff contains | Lens |
| ------------- | ---- |
| `.tsx` / `.jsx`, or `.ts` importing `react` | `audit:react-audit` |
| files importing `three` or `@react-three/*` | `audit:three-audit` |

Invoke the lens skill by name, the same way the external leg goes through `/outsider`, and tell it
three things: that it is running in **lens mode**, the exact files Phase 1 resolved, and the base ref
when the scope has one. A lens must not widen its own scope — a lens that audits the whole project
returns findings this run cannot attribute to the change.

Map what comes back onto the finding contract the native reviewers use. A lens rates its own
findings by its own catalog, so re-rate them here rather than trusting the labels: a lens finding is
`minor` unless it names a concrete failure this diff can produce, and anything the lens calls a
convention violation is `minor` with no exceptions — that is cleanup, and `review:code-cleanup` owns
it.

Lenses are optional in the same way the external reviewer is. A lens skill that is not installed is a
skipped leg, never a failed run, and the report says which lenses ran.

## Phase 4: Consolidate

Reviewers over-report, over-rate, and file one insight three times. Cut that down before spending
anything on verification.

1. **Kill non-findings.** No concrete failure — inputs or state leading to a named wrong result —
   is a worry, not a finding. Same for an intent finding with no quotable requirement clause.
2. **Kill unproven halves.** A finding pairing a demonstrated claim with one nobody could
   demonstrate ships as the demonstrated claim alone — the weakest claim sets the credibility of the
   whole finding.
3. **Dedupe.** Two reviewers hitting the same `file:line` with the same claim is **one** finding at
   the higher severity and confidence. Independent corroboration is a strong signal — say so, and
   never let it look like two problems.
4. **Cluster by root cause.** Ask whether one structural change would fix two or more findings. If
   so, report the root and nest its symptoms beneath it; filed separately, both are understated.

Keep what you killed. Verification rules on the drops too, and a drop confirmed is worth more than
a drop assumed.

## Phase 5: Verify

Takes the **consolidated** findings and is dispatched like any other reviewer — all lenses at once,
none seeing another. The mode decides which lenses run: `reachability` alone in `simple`, all three
otherwise.

Lenses come from `references/verification-prompt.md` with `{{LENS}}` set:

| Lens | Question | May do |
| ---- | -------- | ------ |
| `mechanism` | Does the code actually do this? | Read the repo, compile, run probes |
| `reachability` | Who triggers it, and does the consequence follow? | Read the repo; receives the caller's system facts |
| `spec` | Is the quoted requirement real, and did this diff cause it? | Read the requirement and `git log` |

Every lens is told to **default to refuting** when it cannot demonstrate a claim. Pass the claims
you killed in Phase 4 as well, marked as dropped — a verifier confirming a drop is cheap, and it
sometimes corrects the reason.

One extra job for the `mechanism` lens whenever the change ships its own test, story, or fixture:
**check that the artifact exercises the path it claims to guard.** A fixture that quietly supplies
the missing precondition is worse than no fixture — it turns an open question into a passing check.

**Merge rule.** A finding dies when `mechanism` refutes it, when `reachability` cannot name an
actor who reaches it, or when `spec` kills it. Nothing else removes a finding. Where a lens returns
`narrowed`, keep only the part it says survives.

Severity is then whatever the lenses justify — take `reachability`'s rating when it named an actor,
since that is the actor-aware one, and `mechanism`'s otherwise. **Verification is not a downgrade
pass.** A finding that came in reasoned and goes out demonstrated should come out *sharper*: higher
confidence, and higher severity where the demonstration widened it. A verify phase whose ratings only
ever fall is miscalibrated.

**Verify the reasoned ones hardest.** Every finding killed in verification across both calibration
runs was established by reading; none established by execution was killed or downgraded. Sort the
queue accordingly: reasoning-only findings first, then anything a reviewer rated low confidence.

## Phase 6: Rate and order

The last judgment call, and the one the caller cannot make for itself.

1. **Re-rate by actor.** Severity is a function of **actor and failure, never failure alone**. A
   defect reachable only by code that already holds full trust is not a security finding, whatever
   the mechanism looks like. Every finding names an actor: anonymous client, authenticated user,
   installed extension code, first-party code, or operator action. When verification ran, the
   reachability lens already named it — take that one over the finder's.
2. **Order.** Severity, then confidence. Decisions last, whatever their severity.
3. **Separate decisions from defects.** A finding whose entire blast radius is a deprecated,
   unsupported, or already-documented-as-broken surface is not a defect the author will fix — it is a
   question about whether that is acceptable. Mark it as a decision and say what the decision is.
4. **Check the framing carries the consequence.** A finding framed around what a caller or consumer
   cannot do gets a real fix; the same finding framed around what an internal counter does wrong gets
   a literal one-line patch. Where both framings are available, lead with the consequence.
5. **Do not rewrite the claim.** Severity and survival are yours to judge; the defect itself is
   reported in the reviewer's own framing. Do not soften a claim you kept.

## Phase 7: Critique the synthesis (`deep` mode)

Everything so far judged findings one at a time. Nothing has read the assembled report as a whole,
and you assembled it — the same self-review problem this skill exists to avoid, one level up.

Dispatch one reviewer with `references/synthesis-critic-prompt.md`, the assembled report, and the
diff. It attacks the report, never the code: a root cause split across separate symptoms, a finding
leading with the wrong half instead of the durable one, ranking that contradicts itself, an unproven
clause still riding along, a decision filed as a defect, and at most one area nobody covered. It
cannot add findings.

Apply what it returns, or say why not. It reads a report rather than a repository, so it is the
cheapest agent in the run — and the only one that sees the findings as a set.

## Report

A title, a signal line, a paragraph stating the defect, and a `Concretely:` list of what happens
versus what should happen. No field labels — a reader should be able to understand *and* fix the
issue from the prose alone.

```
### <one-line claim, stated as the defect>

<Severity> severity, reachable by <actor>. <Confidence> confidence — <corroboration>.

<A paragraph naming the defect: what the code does, why that is wrong, and what the correct
behavior is. This is the part someone fixes from. For an intent finding, quote the clause of the
request it violates here, inline — the caller needs to see what was actually asked before deciding
whether to fix the code or push back on the issue.>

Concretely:

- `<input or case>` currently <what happens>. It should <what should happen>.
- `<input or case>` currently <what happens>. It should <what should happen>.

<Any caveat that narrows the fix — what must keep working, what is out of scope.>

Look at `path/to/file.ext:120`, `path/to/other.ext:44`.
```

Rules for the shape:

- Severity is `critical` / `moderate` / `minor`; confidence is `high` / `medium` / `low`. Both sit
  in the signal line directly under the title, never in a field list.
- The actor sits in the signal line too, because it is what makes the severity legible.
- A **decision** takes the same shape with `Decision, not a defect` where the severity would go, and
  its paragraph ends in the question being asked rather than the fix. Decisions come after every
  finding, however severe they look: they need an answer, not a patch, and mixed in among defects
  they read as accusations and get closed.
- The corroboration clause counts reviewers, never names them: `one reviewer`, `corroborated by 2
  reviewers`. Which reviewer found it is a debugging detail; how many found it independently is the
  signal. Count only reviewers that actually ran.
- Say how the finding was established: `demonstrated by execution` when a reviewer or the mechanism
  lens ran the failing case, `reasoned` when it came from reading. It is the strongest thing a finding
  can carry and the best predictor of whether it survives contact with the author.
- A clustered finding reports the root as the finding and nests each symptom as its own
  `Concretely:` bullet with its own location.
- Each bullet is a self-contained sentence pair, one case per bullet however many there are.
- Write the actual-state clause as a verb phrase so it reads after "currently" — `currently parses
  without error`, not `currently accepted`.
- Locations go last. A reader triages on the claim and the severity, not on the path.
- When the finding is that something is **missing**, omit the `Look at` line. Do not name a
  plausible file: the case list already says what is missing, and a guessed path sends the fixer to
  the wrong place.

### Output

```
## Changes review: N findings (C critical, M moderate, m minor) · D decisions

Scope: <files, lines, base> · mode: <simple|standard|deep>
Reviewers: cold (<model>) · intent (<model>|skipped) · external (<cli>|skipped)
Lenses: <lens skills that ran, or none matched|skipped>
Verification: <lenses run, K findings dropped, J re-rated>

<findings, most severe first, then decisions>
```

Drop the `· D decisions` clause when there are none. When every reviewer returns nothing:

```
## Changes review: no findings

Scope: <files, lines, base> · mode: <simple|standard|deep>
Reviewers: cold (<model>) · intent (<model>|skipped) · external (<cli>|skipped)
Lenses: <lens skills that ran, or none matched|skipped>
```

A clean result is a real result. Do not pad it with observations, and do not add a section listing
what was checked and found sound — it reads as padding and nobody acts on it.

One report serves every caller. A caller wanting something shorter condenses what it got.

Then stop. Do not fix, do not offer to fix, do not post, and do not start a second round. Round
policy, publication, and triage belong to the caller.

## Rules

- **One job per reviewer.** A reviewer told to find bugs *and* suggest improvements softens into a
  quality reviewer and stops finding bugs. Never merge the prompts.
- **No reasoning reaches a reviewer.** Not the plan, not the rationale, not a summary of intent, not
  a previous round's findings or verdicts.
- **Never mutate.** No edits, no autofix, no commits, no stashes. Callers rely on this.
- **Concrete failure or it does not exist.** This is the difference between a review and a list of
  anxieties.
- **Severity needs an actor.** A rating that does not say who can reach the defect is not a rating.
- **No manufactured findings.** A reviewer returning "No findings" on sound code is correct
  behavior, not a failed run.

## Error handling

| Situation | Action |
| --------- | ------ |
| No changes in scope | Print `Nothing to review.` and stop |
| Trivial diff only | Print `Trivial changes only. Nothing to attack.` and stop |
| No requirement resolves | Run the cold reviewer only, say so in the report |
| External CLI missing or times out | Note it in the Reviewers line, continue |
| Host cannot vary models per reviewer | Run them on the default, say so in the report |
| Host has no subagents | Run reviewers sequentially, say they were not isolated |
| A verification lens fails | Apply the merge rule with the lenses that returned, say which is missing |
| A reviewer stalls or returns nothing | Relaunch it once with a narrowed file list and a stated tool budget — not the same prompt again. A reviewer that goes quiet on a wide diff is usually still reading it |
| A native reviewer returns nothing usable | Report the remaining reviewers, name the gap |
| Every reviewer fails | Say so plainly. Do not substitute your own review — that is the one thing this skill exists to avoid |
