---
name: changes-review
description: >
  Attack a code change and report what survives. Spawns up to three independent reviewers in
  parallel, on different models where more than one runs, each with a single job and no access
  to the implementer's reasoning: one hunts correctness bugs blind to the issue, one hunts
  requirement gaps against the issue text. Returns structured findings and changes nothing — no
  tooling, no autofix, no edits. Use before committing, when you want a change attacked rather
  than assessed, or as the find step ahead of a fix pass.
license: MIT
compatibility: Claude Code
allowed-tools: Bash(git:*) Bash(gh:*) Bash(bash:*) Read Glob Grep Task Skill
argument-hint: "[--base <branch> | --uncommitted | --commit <sha>] [--issue <N>] [--no-external]"
metadata:
  author: edloidas
---

# Changes Review

Attack a change from two directions at once and report what survives. This skill **finds**;
it never fixes, never runs tooling, and never touches the working tree.

## The premise

The agent that wrote the code wants it accepted. A reviewer that shares its context inherits
its blind spots — it reads the implementer's reasoning, finds it persuasive, and confirms the
work. So every reviewer here is dispatched **cold to the implementer's reasoning**: no plan,
no rationale, no commit message body, no prior-round findings, no account of why the change
looks the way it does. Each gets one job and is told to find the way the change is wrong.

The bugs this catches are the ones that compile and pass lint — premature drops, floor-vs-truncate
on negative numbers, eager evaluation where laziness was meant. Tooling cannot see them and a
context-rich reviewer rationalizes them away.

Conventions and cleanup are **not** this skill's job. A reviewer told to find bugs *and* tidy
the code softens into a quality reviewer and stops finding bugs. Style, naming, comment noise,
and convention drift belong to `/code-cleanup`.

## Arguments

| Argument | Meaning |
| -------- | ------- |
| (none) | Uncommitted changes; falls back to the last commit when the tree is clean |
| `--base <branch>` | Review `git diff <branch>...HEAD` — the whole branch |
| `--uncommitted` | Staged + unstaged changes only |
| `--commit <sha>` | The change introduced by one commit |
| `--issue <N>` | Use issue `<N>` as the requirement. Skips auto-detection |
| `--no-external` | Skip the third-party CLI reviewer even when one is installed |

## Phase 1: Resolve scope

Resolve the diff and the file list once, up front. Every reviewer sees the identical change set.

```bash
git diff --name-only HEAD                    # tracked modifications
git ls-files --others --exclude-standard     # new untracked files
```

Filter out `*-lock.*`, `dist/`, `build/`, `.next/`, `*.min.js`, `*.map`, `*.d.ts`.

**Trivial diffs** — only version bumps, formatting, or lock files → print
`Trivial changes only. Nothing to attack.` and stop. Do not spend reviewers on them.

**Dirty tree under `--base`.** `git diff <base>...HEAD` excludes uncommitted work, so a dirty
tree means the reviewers judge a change set that is not what exists on disk. Say so and review
`<base>...HEAD` plus the uncommitted diff together, or ask the caller to commit first.

Announce the resolved scope in one line: `Attacking 6 files, 240 lines (base: master).`

## Phase 2: Resolve the requirement

Only the intent reviewer uses this. Resolve it before dispatch:

1. `--issue <N>` was passed → `gh issue view <N> --json title,body`
2. Current branch matches `issue-<N>` → same, with that number
3. An open PR exists for the branch → `gh pr view --json title,body,closingIssuesReferences`
   and prefer the linked issue's body over the PR description
4. Last commit message contains `#<N>` → same, with that number

Take the issue **description** only. Exclude comments the agent itself posted during this run —
they are the implementer's reasoning wearing a different hat.

If nothing resolves, print `No requirement found — running the cold reviewer only.` and skip
the intent reviewer. Do not invent a requirement from the diff; a reviewer checking a change
against a requirement inferred from that same change finds nothing.

## Phase 3: Dispatch reviewers

**Launch every reviewer in a single message so they run concurrently.** They must not see each
other's output. Do not summarize the change for them, do not explain what it is trying to do,
and do not pass along anything from a previous round.

### Reviewer 1 — cold (always)

- Task tool, `subagent_type: "general-purpose"`
- `model`: the first of `fable → opus → sonnet` that is **not** the model running this skill
- Prompt: the contents of `references/cold-reviewer-prompt.md`, then the diff

Repo-aware and issue-blind: it may read callers, types, and tests, but the prompt forbids
fetching the issue or PR. That prohibition is a soft guard, not a sandbox — a determined
subagent could still run `gh`. It holds in practice because the reviewer is never handed an
issue number and has no reason to hunt for one. Do not put the issue number in its prompt,
not even in passing.

### Reviewer 2 — intent (whenever a requirement resolved)

- Task tool, `subagent_type: "general-purpose"`
- `model`: the next entry in `fable → opus → sonnet` after Reviewer 1's, wrapping to the start,
  skipping the model running this skill. It must differ from Reviewer 1's.
- Prompt: `references/intent-reviewer-prompt.md` with `{{REQUIREMENT}}` replaced by the
  resolved issue title and body, then the diff

Role diversity and model diversity are both free here, so take both. They cover different
failure modes: same-model reviewers differ only by sampling, same-role reviewers only by
phrasing.

### Reviewer 3 — external model (when available, unless `--no-external`)

A third model family, via a CLI that is genuinely outside this process.

**Invoke the `/codex` skill through the Skill tool** — do not call its script by path. The
script lives in a different plugin (`assist`), so a repo-relative `bash assist/...` command
resolves only inside this repository's own checkout and fails with exit 127 everywhere else.
The Skill tool resolves the plugin wherever it is installed.

Tell it to run review mode with **the scope this run resolved in Phase 1** — `--base <branch>`,
`--uncommitted`, or `--commit <sha>`. Passing a different scope than the native reviewers got
means Phase 4 dedupes findings from two different change sets, which is worse than skipping
this reviewer.

Pass `540` as the timeout so the script's own timer fires before the tool's, and set the Bash
timeout to its 600000ms maximum. If the `/codex` skill or the CLI is unavailable, note it and
continue with the native reviewers. Do not retry, and never block the run on it.

This leg only ever gets a piped diff, so it is structurally cold — it cannot read the repo. That
makes it good at spotting internal contradictions in the diff and prone to asking for context
it cannot see. Weight it accordingly during dedup.

It is the one reviewer with no output contract you control — it returns whatever its CLI emits.
Map each of its findings onto the same fields the native reviewers return: claim, location,
severity, confidence, defect, cases. Where it gives you a claim and a location but no severity
or confidence, assign `moderate` / `low` and say in the signal line that it came from one
reviewer. Where a finding has no concrete case you can name from the diff, drop it under Phase 4
step 1 like any other. Never upgrade its confidence to match a native reviewer's.

## Phase 4: Merge and report

Reviewers return findings in the labelled shape their prompts specify. That is an internal
contract for merging, not the report — render the report in the format below.

1. **Drop non-findings.** Any finding without a concrete failure — inputs or state leading to a
   named wrong result — is a worry, not a finding. Cut it. Same for intent findings with no
   quotable requirement clause.
2. **Dedupe.** Two reviewers hitting the same `file:line` with the same claim is **one** finding
   reported at the higher severity and higher confidence. Independent corroboration is a strong
   signal — say so in the signal line, and never let it look like two problems.
3. **Order.** Severity first, then confidence.
4. **Never soften.** Report each finding in the reviewer's own framing. You are the messenger
   here, not the judge — triage belongs to whoever called this skill.

### Finding format

A title, a signal line, a paragraph stating the defect, and a `Concretely:` list of what
happens versus what should happen. No field labels — a reader should be able to understand
*and* fix the issue from the prose alone.

```
### <one-line claim, stated as the defect>

<Severity> severity. <Confidence> confidence — <corroboration>.

<A paragraph naming the defect: what the code does, why that is wrong, and what the correct
behavior is. This is the part someone fixes from. For an intent finding, quote the clause of
the request it violates here, inline — the caller needs to see what was actually asked before
deciding whether to fix the code or push back on the issue.>

Concretely:

- `<input or case>` currently <what happens>. It should <what should happen>.
- `<input or case>` currently <what happens>. It should <what should happen>.

<Any caveat that narrows the fix — what must keep working, what is out of scope.>

Look at `path/to/file.ext:120`, `path/to/other.ext:44`.
```

Rules for the shape:

- Severity is `critical` / `moderate` / `minor`; confidence is `high` / `medium` / `low`. Both
  sit in the signal line directly under the title, never in a field list.
- The corroboration clause counts reviewers, never names them: `one reviewer`, `corroborated
  by 2 reviewers`, `corroborated by all 3 reviewers`. Which reviewer found it is a debugging
  detail; how many found it independently is the signal. Count only reviewers that actually
  ran — a skipped intent or external leg is not a reviewer that failed to corroborate.
- Each `Concretely:` bullet is a self-contained sentence pair, one case per bullet however many
  there are. Bullets rather than prose because a finding with ten cases has to stay as readable
  as one with two.
- Write the actual-state clause as a verb phrase so it reads after "currently" — `currently
  parses without error`, not `currently accepted`.
- Locations go last. A reader triages on the claim and the severity, not on the path.
- When a reviewer reports `absent` for location — the finding is that something is missing —
  omit the `Look at` line entirely. Do not name a plausible file: the case list already says
  what is missing, and a guessed path sends the fixer to the wrong place.

### Output

```
## Changes review: N findings (C critical, M moderate, m minor)

Scope: <files, lines, base>
Reviewers: cold (<model>) · intent (<model>|skipped) · external (<cli>|skipped)

<findings, most severe first>
```

When every reviewer returns nothing:

```
## Changes review: no findings

Scope: <files, lines, base>
Reviewers: cold (<model>) · intent (<model>|skipped) · external (<cli>|skipped)
```

A clean result is a real result. Do not pad it with observations.

### After reporting

Stop. Do not fix anything, do not offer to fix anything, do not run a second round on your own
initiative. Hand the findings to whichever skill or caller asked for them — round policy belongs
to the caller.

## Rules

- **One job per reviewer.** A reviewer told to find bugs *and* suggest improvements softens into
  a quality reviewer and stops finding bugs. Never merge the prompts.
- **No reasoning reaches a reviewer.** Not the plan, not the rationale, not a summary of intent,
  not a previous round's findings or verdicts.
- **Never mutate.** No edits, no autofix, no commits, no stashes. Callers rely on this.
- **Concrete failure or it does not exist.** This is the difference between a review and a list
  of anxieties.
- **No manufactured findings.** A reviewer returning "No findings" on sound code is correct
  behavior, not a failed run.

## Error handling

| Situation | Action |
| --------- | ------ |
| No changes in scope | Print `Nothing to review.` and stop |
| Trivial diff only | Print `Trivial changes only. Nothing to attack.` and stop |
| No requirement resolves | Run the cold reviewer only, say so in the report |
| External CLI missing or times out | Note it in the Reviewers line, continue |
| A native reviewer returns nothing usable | Report the remaining reviewers, name the gap |
| Every reviewer fails | Say so plainly. Do not substitute your own review — that is the one thing this skill exists to avoid |
