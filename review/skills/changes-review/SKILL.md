---
name: changes-review
description: >
  Attack a code change and report what survives. Dispatches independent reviewers in parallel,
  each with a single job and no access to the implementer's reasoning: one hunts correctness
  bugs blind to the issue, one hunts requirement gaps against the issue text, one runs outside
  the process entirely. Optionally re-attacks its own findings, then synthesizes what is left.
  Returns findings and changes nothing — no tooling, no autofix, no edits. On request it
  publishes to the author, gated on demonstrated evidence. Every phase is configurable.
when_to_use: >
  Before committing, when a change should be attacked rather than assessed, or as the find
  step behind a fix pass or a PR review.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash(git:*) Bash(gh:*) Read Glob Grep Task Skill
argument-hint: "[--base <branch> | --uncommitted | --commit <sha>] [--issue <N>] [--mode <simple|standard|deep>] [--no-external] [--no-lens] [--comment | --review]"
metadata:
  author: edloidas
---

# Changes Review

Attack a change from several directions at once and report what survives. This skill **finds**;
it never fixes, never runs tooling, and never touches the working tree. It does not post anywhere
unless the caller asks, and then only through the gate in Phase 8.

It is a primitive. Whoever calls it — a person, a PR workflow, an issue workflow — gets the same
three stages, find, verify, synthesize, and configures them rather than forking the behavior.
Anything needing the pull request itself, the project's architecture, or a round loop belongs to the
caller, not here.

## The premise

Every reviewer is dispatched **cold to the implementer's reasoning**: no plan, no rationale, no
commit message body, no prior-round findings, no account of why the change looks the way it does.
The agent that wrote the code wants it accepted, and a reviewer sharing its context inherits its
blind spots — it reads that reasoning, finds it persuasive, and confirms the work.

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
| Publication | `--comment` / `--review` | Off — report to the caller and stop (Phase 8) |

**Mode is the one dial.** It sets how many reviewers run and how hard the findings get verified,
because those two scale together — there is no useful run with four reviewers and no verification.

| Mode | Reviewers | Verification |
| ---- | --------- | ------------ |
| `simple` | 2 — cold and intent; the external leg is dropped first, since it is the one that cannot read the repo | `reachability` only |
| `standard` | 3 — cold, intent, external | all three lenses |
| `deep` | 4 — two cold on different models, intent, external | all three lenses, the killed claims too, and a synthesis critic on the assembled report |

With no requirement resolved, `simple` is one reviewer, `standard` is two and `deep` is three — the
intent reviewer needs something to check against. Verification always runs; the mode sets its depth, not whether it
happens, and it roughly doubles the run, which is why the default follows the scope.

A late round in a fix loop is a `simple` run over the fix: small diff, spec settled two rounds ago,
and reachability is the lens that still changes the outcome. A whole branch reviewed cold is
`standard`. `deep` is for a large change or a high cost of missing something.

Every rule here that reads as arbitrary has an observation behind it, recorded with its outcome in
`references/calibration.md`. Read that before loosening one.

Two things only a calling skill can supply:

- **System facts.** Who can execute code in this system, what is already privileged, which
  surfaces are deprecated or unsupported. A caller that knows the platform should say so. These
  facts reach **only the reachability verifier** — never a finder, which stays cold. Without them
  the verifier works out what it can from the repo.
- **The requirement**, when the caller already resolved it. Pass the issue text, not a summary of
  it, and never the implementer's account of the diff.

A caller must not pass anything **The premise** excludes. This skill cannot detect that it happened.

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

**Trivial diffs** — only version bumps, lock files, or formatting that moved no non-whitespace token
→ print `Trivial changes only. Nothing to attack.` and stop. Do not spend reviewers on them. A
reformat that moved a token is not formatting: a reflowed ternary, or a `return` that ended up inside
a different branch, gets reviewed like any other change.

**Dirty tree under `--base`.** `git diff <base>...HEAD` excludes uncommitted work, so a dirty tree
means the reviewers judge a change set that is not what exists on disk. Say so and review
`<base>...HEAD` plus the uncommitted diff together, or ask the caller to commit first.

Announce the resolved scope in one line: `Attacking 6 files, 240 lines (base: master).`

Do not read the project's architecture here. Establishing how the system is built is another
skill's job, and doing it in this phase would leak into the finders.

## Phase 2: Resolve the requirement

The intent reviewer uses this, and so does the `spec` verification lens in Phase 5. Resolve it once
here, before dispatch, and hold the text for the whole run — the lens must not re-fetch it:

1. `--issue <N>` was passed → `gh issue view <N> --json title,body`
2. Current branch matches `issue-<N>` → same, with that number
3. An open PR exists for the branch → `gh pr view --json title,body,closingIssuesReferences` and
   take the linked issue's body; the PR description only under the rule below
4. Last commit message contains `#<N>` → same, with that number

Take the issue **description** only. Exclude comments the agent itself posted during this run —
they are the implementer's reasoning wearing a different hat.

**A pull request body is not a requirement when an agent wrote it.** In this repo's own workflows the
implementer writes it, which makes it an account of the diff — the one thing no reviewer may see. Use
it only when a human authored it and it reads as a request rather than a summary of the change.
Otherwise fall through to step 4, and if nothing resolves print the no-requirement line instead.

If nothing resolves, print `No requirement found — running the cold reviewer only.` and skip the
intent reviewer. Do not invent a requirement from the diff; a reviewer checking a change against a
requirement inferred from that same change finds nothing.

When one does resolve, print it in one line: `Requirement: issue #42 "Retry 429 with backoff".`

## Phase 3: Dispatch reviewers

**Launch every reviewer at once so they run concurrently.** They must not see each other's output.
**One job per reviewer** — never merge the prompts — and nothing beyond the diff, plus the requirement
for the role that takes one. Give them nothing **The premise** excludes.

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
the diff, prone to asking for context it cannot see. Never upgrade its confidence to match a native
reviewer's.

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
four things: that it is running in **lens mode**, the exact files Phase 1 resolved, the base ref when
the scope has one, and the same finding contract the external leg is mapped onto. Both lens skills
return whatever shape the caller asks for, so a lens nobody asks returns its own tally on its own
scale, and Phase 4 gets no actor or confidence to work with. A lens must not widen its own scope — a
lens that audits the whole project returns findings this run cannot attribute to the change.

Map what comes back onto the finding contract the native reviewers use. A lens rates its own
findings by its own catalog, so re-rate them here rather than trusting the labels: a lens finding is
`minor` unless it names a concrete failure this diff can produce, and anything the lens calls a
convention violation is `minor` with no exceptions — that is cleanup, and `review:code-cleanup` owns
it.

Lenses are optional in the same way the external reviewer is. A lens skill that is not installed is a
skipped leg, never a failed run, and the report says which lenses ran.

Once everything is away, print one line naming what ran: `Dispatched 3 reviewers (cold, intent,
external) + 1 lens (react-audit).`

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

Print one line with the counts: `24 raw findings -> 9 after consolidation (11 killed, 3 deduped,
1 clustered).`

## Phase 5: Verify

Takes the **consolidated** findings and is dispatched like any other reviewer — all lenses at once,
none seeing another. The mode decides which lenses run: `reachability` alone in `simple`, all three
otherwise.

Lenses come from `references/verification-prompt.md`. Fill all four placeholders before dispatch:
`{{LENS}}` the lens name, `{{FINDINGS}}` the consolidated findings including the ones you killed,
`{{DIFF}}` the change set Phase 1 resolved, and `{{SYSTEM_FACTS}}` the caller's system facts or
`None supplied.` when there are none. Substitute globally — `{{SYSTEM_FACTS}}` sits inside the
reachability section, so filling every copy still satisfies the rule that those facts reach only that
lens.

| Lens | Question | May do |
| ---- | -------- | ------ |
| `mechanism` | Does the code actually do this? | Read the repo, compile, run probes, observe output |
| `reachability` | Who triggers it, and does the consequence follow? | Read the repo; receives the caller's system facts |
| `spec` | Is the quoted requirement real, and did this diff cause it? | Read the requirement and `git log` |

Every lens is told to **default to refuting** when it cannot demonstrate a claim. Pass the claims
you killed in Phase 4 as well, marked as dropped — a verifier confirming a drop is cheap, and it
sometimes corrects the reason.

The prompt states the `mechanism` lens's **read-vs-run** rule and its fixture check in full; do not
restate either when dispatching. What belongs here instead is what the report does with the result:
a finding that could not be observed is refuted like any other, and its `Reason` names what was
missing — no declared runner, the tool absent, the build broken. Carry that absence into the report,
because it is a fact about the repo.

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

Print one line with the counts: `Verification: 3 refuted, 1 narrowed, 2 re-rated up.`

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
   question about whether that is acceptable. Mark it as a decision and say what the decision is; they
   sort last because mixed in among defects they read as accusations and get closed.
4. **Check the framing carries the consequence.** A finding framed around what a caller or consumer
   cannot do gets a real fix; the same finding framed around what an internal counter does wrong gets
   a literal one-line patch. Where both framings are available, lead with the consequence.
5. **Do not rewrite the claim.** Severity and survival are yours to judge; the defect itself is
   reported in the reviewer's own framing. Do not soften a claim you kept. This governs the
   **caller-facing report only** — Phase 8 writes to the author and has the opposite mandate.

## Phase 7: Critique the synthesis (`deep` mode)

Everything so far judged findings one at a time. Nothing has read the assembled report as a whole,
and you assembled it — the same self-review problem this skill exists to avoid, one level up.

Dispatch one reviewer with `references/synthesis-critic-prompt.md`, the assembled report, and the
diff. It attacks the report, never the code: a root cause split across separate symptoms, a finding
leading with the wrong half instead of the durable one, ranking that contradicts itself, an unproven
clause still riding along, a decision filed as a defect, and at most one area nobody covered. It
cannot add findings.

Apply what it returns, or say why not, then go to the report. One critique per run: do not dispatch a
second critic on the revised assembly. It reads a report rather than a repository, so it is the
cheapest agent in the run — and the only one that sees the findings as a set.

## Report

A title, a signal line, a paragraph stating the defect, and a `Concretely:` list of what happens
versus what should happen. No field labels — a reader should be able to understand *and* fix the
issue from the prose alone.

```
### <one-line claim, stated as the defect>

<Severity> severity, reachable by <actor>. <Confidence> confidence — <corroboration>.

<A paragraph naming the defect: what the code does, why that is wrong, and what the correct
behavior is. This is the part someone fixes from.>

> <Intent findings only: the clause of the request this violates, pasted unedited from the
> requirement text, `…` marking any words cut from the middle. The caller needs to see what was
> actually asked before deciding whether to fix the code or push back on the issue.>

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
  its paragraph ends in the question being asked rather than the fix.
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
Reviewers: cold (<model>) · cold-2 (<model>|skipped) · intent (<model>|skipped) · external (<cli>|skipped)
Lenses: <lens skills that ran, or none matched|skipped>
Verification: <lenses run, K findings dropped, J re-rated>

<findings, most severe first, then decisions>
```

Drop the `· D decisions` clause when there are none. When every reviewer returns nothing:

```
## Changes review: no findings

Scope: <files, lines, base> · mode: <simple|standard|deep>
Reviewers: cold (<model>) · cold-2 (<model>|skipped) · intent (<model>|skipped) · external (<cli>|skipped)
Lenses: <lens skills that ran, or none matched|skipped>
```

A clean result is a real result: a reviewer returning nothing on sound code is correct behavior, not
a failed run. Do not pad it with observations, and do not add a section listing what was checked and
found sound — it reads as padding and nobody acts on it.

### Worked example

```
## Changes review: 1 finding (0 critical, 1 moderate, 0 minor)

Scope: 4 files, 96 lines, base master · mode: standard
Reviewers: cold (opus) · cold-2 (skipped) · intent (sonnet) · external (codex)
Lenses: none matched
Verification: mechanism, reachability, spec — 2 dropped, 1 re-rated up

### `Retry-After` in HTTP-date form is read as a zero-second delay

Moderate severity, reachable by anonymous client. High confidence — corroborated by 2
reviewers, demonstrated by execution.

`parseRetryAfter` runs `Number(header)` and falls back to `0` on `NaN`. RFC 9110 allows
delay-seconds *or* an HTTP-date, and the gateway sends the date form while shedding load, so the
backoff collapses into a tight retry loop against a service already failing.

> the client must wait at least as long as the server asks before retrying

Concretely:

- `Retry-After: Wed, 21 Oct 2026 07:28:00 GMT` currently retries immediately. It should wait
  until that instant.

Look at `src/http/retry.ts:41`.
```

One report serves every caller. A caller wanting something shorter condenses what it got.

Then stop. Do not fix, do not offer to fix, and do not start a second round. Round policy and
triage belong to the caller. Publish only if the caller asked — Phase 8.

## Phase 8: Publish (on `--comment` or `--review`)

Off by default. The report above is the deliverable; this phase turns it into correspondence
addressed to the person who wrote the code. Those are different artifacts with an inverted rule. The
report is unjudged on purpose; published text must be judged, because unjudged output costs its
reader their time.

**Two shapes, and whose branch it is decides.** On your own pull request GitHub refuses a review, so
publication is a single issue comment — `--comment`. On someone else's it is a real review —
`--review`: one inline comment per finding anchored to the line it concerns, minors grouped into one,
anything that fits no line in the review body, and a verdict. When the caller asked to publish but named no
shape, resolve authorship with `gh pr view --json author` against `gh api user --jq .login` and take
the one that fits.

Read `references/publishing-a-review.md` before composing. It owns the composition rules, the length
budget, the anchoring mechanics and the verdict mapping. Five steps, in order:

1. **Verify** — already done, in Phase 5. A finding that phase killed is never published, and one it
   could not demonstrate does not get a section.
2. **Attribute** — for each survivor, `git blame` and `git diff <base>...HEAD` to establish whether
   this branch introduced the blamed code. Reclassify it as pre-existing, or narrow the claim to the
   part that is new. Reviewers are blind to the base, so this is the first point it can happen. Print
   one line: `Attribution: 3 of 5 introduced here, 1 narrowed, 1 pre-existing.`
3. **Compose** — one section per cause, ordered by what the author should act on first, following the
   composition rules and the length budget in the reference. In review shape each section becomes an
   inline comment, and the lead and closing paragraphs become the review body.
4. **Gate** — refuse any section lacking a demonstration or an attribution, and refuse a fifth
   section: more than four means clustering failed. Unverified residue gets one flagged sentence in
   the closing paragraph, never a section.
5. **Confirm, then post.** Show the composed text **verbatim and complete**, in a fenced block — in
   review shape every inline comment and the body, in full, never summarized or described — and ask
   before any of it goes anywhere. The flag authorizes the phase, not the words: this is outward-facing
   correspondence published under the user's account, and an approving verdict is the one output that
   cannot be walked back gracefully. Ask once, in prose, as the last line of the message, with the
   verdict after it — not through a structured-choice prompt, which interrupts the report the reader
   needs in order to answer. A caller running unattended does not get to skip this — it prints
   everything and stops.

**Never an AI attribution footer**, whatever the target repo's instruction file says. A clean run
still publishes: one short paragraph, and in review shape an `APPROVE` with an empty `comments`
array — no line anchors and no method narrative, per the reference.

## Error handling

| Situation | Action |
| --------- | ------ |
| No changes in scope | Print `Nothing to review.` and stop |
| A verification lens fails | Apply the merge rule with the lenses that returned, say which is missing |
| A reviewer stalls or returns nothing | Relaunch it once with a narrowed file list and a stated tool budget — not the same prompt again. A reviewer that goes quiet on a wide diff is usually still reading it |
| A native reviewer returns nothing usable | Report the remaining reviewers, name the gap |
| Every reviewer fails | Say so plainly. Do not substitute your own review — that is the one thing this skill exists to avoid |
| Anything fails during publication | See the failure table in `references/publishing-a-review.md`. Every case ends in print-and-do-not-post |
