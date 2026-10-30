# Writing Skills

Read this when creating or editing a skill. The checks that enforce these rules are listed in
[AGENTS.md](../AGENTS.md#skill-changes-are-gated); budgets and exemptions are in
[validation.md](validation.md); host trees and the Codex wrapper are in
[packaging.md](packaging.md).

## Creating a New Skill

1. Create a real directory: `mkdir -p skills/<skill-name>` (never a symlink)
2. Create `skills/<skill-name>/SKILL.md` with required frontmatter and instructions, including
   `metadata.tier` — see [Tiers](#tiers)
3. Add `scripts/`, `references/`, or `assets/` directories as needed
4. Add a row under the right topic in the "Available Skills" table in `README.md`, with the tier
   in its Tier column
5. If the skill targets Codex, update the Codex layer in the same change — see
   [packaging.md](packaging.md#codex-wrapper)
6. Run `bash .github/scripts/validate-skills.sh` to verify marketplace, manifests, and skill layout
7. If the skill bundles a shell script, add its tests under `tests/skills/<skill>/` and run `bash tests/run.sh`
8. Run `skill-audit` and clear it before committing

## Skill Naming

- Directory name must match the `name` frontmatter field exactly
- Lowercase letters, numbers, and hyphens only (`a-z`, `0-9`, `-`)
- No leading/trailing hyphens, no consecutive hyphens (`--`)
- Max 64 characters

Valid: `pdf-processing`, `data-analysis`, `code-review`
Invalid: `PDF-Processing` (uppercase), `-pdf` (leading hyphen), `pdf--processing` (consecutive hyphens)

## Frontmatter (YAML)

Required fields:

| Field         | Constraint                                                                                                       |
| ------------- | ---------------------------------------------------------------------------------------------------------------- |
| `name`        | 1–64 chars, matches directory name                                                                               |
| `description` | ≤1,024 chars; when paired with `when_to_use`, the combined discovery entry is capped at 1,536 chars and truncated |

Optional fields:

| Field           | Constraint                                                                                                            |
| --------------- | --------------------------------------------------------------------------------------------------------------------- |
| `license`       | License name or reference to a bundled LICENSE file                                                                   |
| `compatibility` | 1–500 chars; target agent and/or environment needs (see [Portability](#portability))                                  |
| `metadata`      | Key-value mapping; use reasonably unique key names to prevent conflicts. `metadata.tier` (`auto`, `routed`, `manual`) is required here — see [Tiers](#tiers) |
| `when_to_use`   | Trigger phrases and scenarios for activation. Appended to `description` at discovery; combined cap 1,536 chars        |
| `arguments`     | Space-separated parameter names for autocomplete tokens. Makes arguments mandatory for marketplace-installed plugin skills — see [Arguments Behavior](#arguments-behavior) |
| `allowed-tools` | **Experimental.** Pre-approved tools, as a space-separated string (`Bash(git:*) Read`) or a YAML list                  |

Claude Code extension fields (ignored by other agents; which of them a portable skill must not
rely on is in [Portability](#claude-only-mechanisms)):

| Field                      | Constraint                                                                                                          |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `argument-hint`            | Hint shown during autocomplete to indicate expected arguments (e.g. `[issue-number]`, `[filename] [format]`)        |
| `disable-model-invocation` | `true` prevents Claude from auto-loading the skill; invoke manually with `/skill-name`. Default: `false`            |
| `user-invocable`           | `false` hides from the `/` menu; Claude can still load it when relevant. Default: `true`                            |
| `model`                    | Model to use when skill is active (e.g. `claude-sonnet-4-5`)                                                        |
| `effort`                   | Override session effort while the skill is active: `low`, `medium`, `high`, `xhigh`, or `max`                       |
| `paths`                    | Glob string or YAML list that scopes auto-activation to matching file paths (e.g. `".github/workflows/**/*.yml"`)   |
| `shell`                    | `bash` (default) or `powershell`; gates the shell used for `` !`command` `` and ` ```! ` injection blocks            |
| `context`                  | `fork` runs the skill in a forked subagent context                                                                  |
| `agent`                    | Subagent type when `context: fork` (e.g. `Explore`, `Plan`, `general-purpose`, or a custom `.claude/agents/` agent) |
| `hooks`                    | Hooks scoped to skill lifecycle. See [Claude Code hooks docs](https://code.claude.com/docs/en/hooks)                |

String substitutions available in skill body: `$ARGUMENTS`, `$ARGUMENTS[N]` / `$N`, `${CLAUDE_SESSION_ID}`, `${CLAUDE_SKILL_DIR}` (absolute path to the skill's `SKILL.md` directory — useful for invoking bundled scripts regardless of cwd).
Dynamic context injection: `` !`command` `` runs a shell command and inserts its output before Claude sees the skill content.

`effort:` and `model:` frontmatter stay unset collection-wide. Claude Code supports them and the
other hosts ignore them, so there is no portability cost — but there is also no measurement saying
which skills are under- or over-thought, and the rubric already treats a `model` override as
needing justification. Revisit with numbers, not intuition.

Example frontmatter:

```yaml
---
name: pdf-processing
description: Convert PDF files to text and extract their metadata.
license: MIT
compatibility: Requires poppler-utils (pdftotext) installed on the system
allowed-tools: Bash(pdftotext:*) Read
user-invocable: true
metadata:
  author: edloidas
  tier: routed
---
```

### Arguments Behavior

For marketplace-installed plugin skills, `arguments` makes arguments **mandatory** (Enter is
blocked until provided) and `argument-hint` is **not displayed**. Direct skills
(`~/.claude/skills/`) are unaffected — both fields work as expected.

Only use `arguments` when the skill genuinely cannot function without explicit input (e.g. an
issue number that can't be derived from context). Prefer `argument-hint` alone for optional
hints. `$ARGUMENTS` works regardless of whether `arguments` is declared.

## Discovery

Skills use progressive disclosure to manage context efficiently:

1. **Discovery** — Only `name` and `description` (plus `when_to_use`) are read, every session, by every host. Write descriptions that clearly signal when the skill applies.
2. **Activation** — Full SKILL.md body is loaded (capped at 500 lines / ~5000 tokens; see [validation.md](validation.md#body-budgets)).
3. **Execution** — `references/` and `assets/` files are loaded on demand. Put detailed material there, not in the body.

### Tiers

Every skill declares how it is reached, as `metadata.tier` in its frontmatter. The tier sets
what its discovery text is for, and so how long it may be. `validate-skills.sh` enforces the
limits, measured in bytes of `description` plus `when_to_use`; the 1,536 cap applies to all.

| Tier | Reached by | Discovery text | Limit | Flags |
| ---- | ---------- | -------------- | ----- | ----- |
| `auto` | The model, on its own, from what the user typed | `description`: what it does, plus one "Not for X — that is Y" clause only where a real confusion exists. `when_to_use`: 4–6 phrases a user actually types, then the situation that should fire it | 600 B | none |
| `routed` | `/name`, `/do`, or another skill that chains into it | One sentence in `description`: what it does in plain words, with the one noun that tells it apart. No `when_to_use`, no trigger phrases, no routing notes | 200 B | none |
| `manual` | `/name` only | A fuller `description` is fine; it only feeds the `/` menu | 1,536 | `disable-model-invocation: true` |

**Routed skills carry no triggers because nothing matches against them.** Every discovery entry
is read in every session by every host. A routed skill is chosen by a router that already knows
it, or typed by name, so a trigger list there costs every session and buys nothing — and it
competes with the auto skill that should have fired. The sentence only has to identify the skill
in a listing.

**A skill another skill chains into cannot be manual.** `disable-model-invocation` blocks the
model from loading the skill at all, which includes another skill invoking it. Before making a
skill manual, search the other skills for an instruction to invoke it; a line telling the user to
run it themselves is fine. The validator rejects `disable-model-invocation: true` on an auto or
routed skill, and its absence on a manual one.

**Choosing a tier.** Default to `routed`. Make a skill `auto` only when users ask for it in their
own words often enough that waiting for `/do` or `/name` would be a miss, and its situation is
distinct enough that it will not fire on its neighbours' requests. Make it `manual` when it
should never start without the user asking: it writes to machine or repository settings, or its
output is wanted only on demand.

Codex maps the tier onto `allow_implicit_invocation` ([packaging.md](packaging.md#codex-metadata)).
OpenCode and pi have no equivalent flag, so there the tier is only as good as the text.

### Writing Descriptions

The `description` says what the skill does in words that would appear in a matching request —
a situation, not a stance. How much more it carries is the tier's call, above.

- Poor: `"Helps with PDFs."`
- Routed: `"Attack a diff with independent cold reviewers and report what survives."`
- Auto: `"Explain how something actually works by tracing the mechanism on concrete values."`, with
  `when_to_use` holding `"how does this work", "walk me through it", "I still don't get it"`.

### What Discovery Text Must Not Carry

- **No tool name.** `validate-skills.sh` rejects a tool name in `description` or `when_to_use`
  — `AskUserQuestion`, `ToolSearch`, `TodoWrite`, `SlashCommand`, `NotebookEdit`, `WebFetch`,
  `WebSearch`, `StructuredOutput`, `subagent_type`, and the explicit `<Name> tool` phrasing.
  This applies to **every** skill, Claude-only ones included: discovery text is matched against
  what a person types, and nobody asks for a skill by naming the tool it calls. A tool name
  there cannot help the skill fire on any host. `Task`, `Agent`, `Skill`, `Read`, `Write`,
  `Edit`, `Glob`, `Grep`, and `Bash` are ordinary English and appear legitimately — "Audit
  Agent Skills", "Write Markdown", "Reads and reports only" — so they are caught only in the
  `<Name> tool` form. `allowed-tools` is untouched by this rule; it is a declaration, and
  naming tools is its whole job.
- **No model-calibration adverb** — "thoroughly", "concisely", "carefully". Enforced by
  `validate-skills.sh`. Discovery text is read every session by every host and cannot make a
  skill fire by describing how it works. Behavioural-style trigger phrases a user would type
  are fine here: `consilium`'s "think hard" and "ultrathink" are correct.

## Body Conventions

- Keep under 500 lines / ~5000 tokens — enforced; see [validation.md](validation.md#body-budgets)
- Include step-by-step instructions, examples, and edge cases
- Move detailed reference material — lookup tables, rule catalogs, prompts — to `references/`
  files instead of the body
- Use relative paths from the skill root when referencing files (e.g. `references/api-guide.md`);
  never absolute paths or paths outside the skill directory
- Keep references one directory level deep; avoid nested reference chains
- Keep individual reference files focused — smaller files mean less context usage
- Bundled scripts must be self-contained or clearly document their dependencies, include
  helpful error messages, and handle edge cases gracefully

## Writing a Skill Body

A `SKILL.md` is a prompt fragment injected into an unknown model's context. One file is read by
several Claude models and by GPT-5.x through Codex, and by whatever replaces them next year.
Current vendor guidance points those models in opposite directions on the same knobs: one runs
long and wants a conciseness prompt, another is already too dense; one over-narrates, another
under-narrates; one over-delegates, another does not.

The framing to reject is "tune a shared prompt for models that disagree" — that is per-model
compensation, which a portable file cannot carry. The framing to adopt:

> Every per-model knob is a **default the model falls back to when the prompt is silent.** A
> skill that is not silent — that names the artifact each phase produces and the sentence that
> ends it — never hands the model a place to apply its default.

So the work is never to add compensation. It is to finish specifying what is still left to the
model: progress lines, quoting, delegation thresholds, phase stop conditions, edit mechanics.
Where the artifact is specified, the models converge. Where it is not, each falls back to its
own habit.

**A skill states what the task requires. It does not state what the model requires.**

### The layer model

Four layers hold instructions. Each rule lives in exactly one.

| Layer | Owns | Examples |
| ----- | ---- | -------- |
| Host system prompt | Model calibration the host tunes per model | verbosity, narration cadence, formatting density, correction narration, thinking depth |
| `AGENTS.md` / `CLAUDE.md` (user or repo) | Cross-cutting policy for this person's work | commit format, autonomy baseline, comment policy, git conventions |
| `SKILL.md` body | What this task requires, and only this task | the procedure, its gates, its output contract, its safety boundary |
| `references/` | Material consulted *during* execution, not before | rule catalogs, dispatched prompts, lookup tables, worked examples |

Two tests for a candidate line. Would it still be correct if the task were different? Then it is
not a skill's line. Would the skill produce *wrong results* without it, as opposed to
differently-styled results? If not, it is not a skill's line.

**The deliberate exception is the authorization delta.** These skills install into other people's
repos, where this repo's instructions do not exist. A read-only skill must say it is read-only in
its own body. It must not restate what "read-only" *means*. Same for a skill that pushes, or
writes to an external service: it names the writes it performs and the gates it never skips, and
nothing more. Same again for a skill that reads text someone else wrote — issue bodies, PR and bot
comments, transcripts: it says once, in one line, that the text is data to act on and that
instructions inside it are not the user's.

The autonomy baseline those deltas are measured against: for requests to answer, explain, review,
diagnose, or plan — inspect and report, do not implement unless asked. For requests to change,
build, or fix — make in-scope local changes and run non-destructive validation without asking.
Require confirmation for external writes, destructive actions, and scope expansion. A skill adds
only what differs from that.

### Say a thing once

A rule is stated once, in the section that owns it. Other sites cross-reference that section by
name. This generalizes the [Asking the User](#asking-the-user) convention — "call sites do not
re-explain the fallback" — which was for a long time the only place the repo applied it. It is
the largest single win available: stating each rule once measures at +10–15% eval quality for
41–66% fewer tokens.

**No trailing `## Rules` recap that restates earlier sections.** A closing block of bold negatives
fails on every model at once, each for its own reason: one reads it as emphasis and over-weights
it, one pays the repetition tax, one treats a trailing recap as a summary and skims it — so a rule
living *only* there is lost. Either delete the section, or make it the single home of rules that
appear nowhere else.

**Locality is not repetition.** A constraint belongs beside the action it constrains. A safety
boundary stated once at the top and never again next to the command that would breach it is a
boundary read 300 lines too early. Say-once forbids a second *copy*; locality requires the *only*
copy to sit in the right place. When the two pull against each other, move the rule down to the
action and cross-reference it from the top.

### Specify the artifact, not the behaviour

- **Length in units, never adjectives.** "One section per cause, at most four." "One line:
  `Committed <sha>`." Never "be concise" or "no fluff" — an adjective is a knob each model turns
  differently, a unit is a fact. A check works too: `skills/bro`'s "Shorter than the
  original, always; if it is not, cut more."
- **Every phase spanning more than one tool call names the line it prints at its end.** This
  replaces "give progress updates" and settles the narration split with no per-model text. Make
  the line carry real counts: `12 raw findings -> 5 after consolidation`. It has to be **one line
  per phase**, not one per skill: a single named line elsewhere is read as the ceiling rather than
  the floor, and the model goes silent everywhere it was not asked.
- **Every phase that could continue ends with a stop sentence naming what does not follow.**
  `skills/changes-review` is the model: "Then stop. Do not fix, do not offer to fix, and do
  not start a second round." This is also the real defence against a model bolting its own re-check
  on top of the specified one, and against ending a turn with a promise ("Round 3 would attack the
  fix…") instead of an action. Where a skill runs in rounds, add: a round ends only in one of the
  states in the table; a description of the next round is not a state, run it.
- **A skill with six or more phases states its done condition once, before the first phase:**
  `Done means: <the artifact or state>, or a gate waiting on the user.` The stop sentence bounds the
  end; the done line stops the opposite failure, a turn that ends between phases with a summary
  announcing the next one. A phase's closing line is a status note printed in the same message as
  the next phase's first action, not a turn boundary. The only turn ends are the done condition, a
  gate, and a blocker the report names.
- **Reproduced source text is marked, and the template shows the marker.** An instruction saying
  "quote the clause" while the template renders prose gets prose. Put a literal `> ` blockquote
  line in the template where the quote goes. Where a skill says "paste it, never describe it", add:
  in a fenced block, unedited; if you cut lines, say how many and from where.
- **A skill that edits files states the edit mechanic once:** targeted edits per hunk, never a
  whole-file rewrite. Otherwise removing six comments from a 300-line file becomes a whole-file
  write whose diff carries whitespace and quote-style churn nobody asked for. Language about
  "surgical" *scope* is a different statement and does not cover this.
- **Quantify read-scope where under-reading is possible.** "What to read" without "how many" gets
  one file opened, the rest reasoned about, and the "what I verified" line quietly downgraded.
  One sentence fixes it and fixes tool-call batching at the same time: list every file the trace
  will touch, and open all of them in one response before writing a word.
- **Every dynamic check that did not run is named in the report, with why.** If one optional check
  says "skip it and say so" and its sibling does not, the sibling gets skipped silently and a
  partial run reads as a clean one.

### Phrasing

- Say what to do, not what to avoid, where both work.
- **No shouty emphasis as a compliance device** — enforced by `validate-skills.sh`. Where the
  shout sits on an approval gate, drop the shout and keep the gate: "Pushing the tag publishes it
  and cannot be recalled. Show the version and the tag, and wait for approval." Same imperative
  force, no capitals. Never weaken a gate to satisfy the rule.
- **Instruction first, rationale after, one line, next to the rule.** The *why* genuinely helps and
  the rationale-heavy skills in this collection work — do not strip rationale. What fails is
  rationale *wrapping* an imperative: in a 40-line section holding two instructions and 38 lines of
  reasoning, the instructions get extracted and the scope the reasoning attached to them is lost.
- **A condition attached to a table row lives in the row.** Tables and fenced templates bind far
  more reliably than the prose paragraph after them, so a condition in the following sentence is
  dropped while the row is applied.
- **Tables for classification, prose steps for procedure.** Tables bind for exact mappings and
  mutually exclusive cases, poorly for ordered procedures, exceptions, and nested conditionals.
- **Never gate a finding on the model's own confidence.** "Only report violations you are CERTAIN
  about", "only report high-severity", "be conservative" are followed literally and cap recall.
  Worst inside a *dispatched* prompt, where the sub-agent is the one finding things and no filter
  stage exists downstream. Carry `**Confidence**: high | medium | low` as a reported field and
  filter in synthesis — the architecture `skills/changes-review` already uses.
- **No behavioural-style words in a body** — "be thorough", "think carefully", "double-check",
  "verify your work". Warned by `validate-skills.sh`. Discovery text is exempt (see
  [Discovery](#what-discovery-text-must-not-carry)), and quoted trigger phrases in a body are
  exempt for the same reason.

### Examples and verification

**Every skill producing structured output ships one complete worked example of that output** — a
filled-in instance of the skill's own template, not a second template. One, in the body, as a
fenced block; anything further goes in `references/`. Do not use `<example>` tags: fenced blocks
already separate example from instruction, and XML tagging is a system-prompt tool. The exception
is the quoting marker above, which earns an explicitly marked block.

**Do not instruct a model to double-check its own work.** Cut "before finishing, verify your
answer", "add a final verification step", "use a subagent to double-check your own output". Keep
everything external and structural — an independent agent attacking the artifact blind to the
implementer's reasoning, running the project's tests, a live observation. Those are not
self-verification. In practice the defence against over-verification is the stop sentence above,
not a prohibition.

### Delegation

- **Every dispatch site carries a numeric threshold or a named trigger.** `skills/explain` is
  the model: "Read it yourself up to about 5 files or 1000 lines. Past that, dispatch subagents". An adjective like
  "when the surface is wide" leaves it to the model, so one host spawns and another does not.
- **An inline fallback for a chained skill is at most 5 lines and a pointer.** A fallback longer
  than the invocation gets taken every time, and it is a second copy of the skill it replaces —
  the drift mechanism this doc warns about throughout.
- How a portable skill words a dispatch is in [Portability](#subagent-dispatch-is-intent).

### Cut order, when a body is over budget

1. Duplicated mission statements and restated procedure summaries
2. Historical rationale not attached to a live constraint (compress to one line)
3. "Core Principle" sections that do not change a later decision
4. Failure-mode tables that only restate the procedure
5. Generic agent-behaviour advice (host layer)

Never cut: task-specific boundaries, decision criteria, gates, edge cases, required commands,
output schemas, worked examples, and the one-line reason behind a surprising rule.

### Deliberately not adopted

Recorded so it is not re-derived. Effort sweeps and `output_config` (an API loop; a skill has no
analogue) · prefill migration, structured outputs, `budget_tokens` (request shape; a skill never
constructs a request) · turn-scoped system messages, beta headers, append-only history (harness
layer) · programmatic tool-calling routing (vendor-specific, and naming it is a mechanism
violation) · XML-tagged system-prompt blocks and the "mannered prose" block (host-layer
calibration) · "ask the model to self-check" (superseded above) · restating a conciseness reminder
near the end of a long prompt (model-specific compensation; the per-phase stop sentence does the
same job portably) · "prefer general instructions over prescriptive steps" (wrong here — these
skills exist to *replace* the model's default procedure, which is the whole premise of
`issue-flow`'s squash rules and `changes-review`'s cold dispatch) · "report everything, filter
separately" as new text (already the architecture; adding it again violates say-once).

## Asking the User

Skills using `AskUserQuestion` must follow these rules:

1. First option is recommended — add `(Recommended)` suffix to its label
2. Every option has a description explaining the choice
3. Order by relevance — recommended first, alternatives next, skip/none last
4. Maximum 4 options — "Other" is added automatically by Claude Code
5. Headers ≤12 characters, labels 1-5 words

### The canonical section

Any skill declaring a non-Claude host and asking a question carries exactly one section,
worded **verbatim** as below. The single source of the wording is
`skills/skill-audit/references/asking-the-user.md`, so the rule travels into repos
without this doc; the block here is a copy for reading. It sits immediately before the
skill's first procedural section — `## Workflow`, `## Phase 0`, `## Execution Steps`,
whichever the skill uses — at `##`, or `###` where the skill nests its conventions.

```markdown
## Asking the User

Every question in this skill is written as `AskUserQuestion` options. Use that tool where
the host offers it, or the host's nearest structured-choice equivalent. Where the host has
neither, ask the same question in normal chat as a numbered list of 2–5 options —
recommended first, one short line of description each — and wait for the user to reply
with a number.
```

Copy it; do not paraphrase it. Fourteen skills each carried their own wording of this rule
before it was unified, which made a reader unable to tell a deliberate variation from
drift. `validate-skills.sh` hard-fails an asking skill — `AskUserQuestion` in
`allowed-tools`, an `Asking the User` heading, or a `per **Asking the User**` call site —
whose first paragraph under that heading differs from the reference file, whitespace
collapsed. Change the wording there first, then here and in every skill, in one change.

**Call sites do not re-explain the fallback.** They say `Ask, per **Asking the User**:`
followed by the options, and nothing more. A skill may add one extra paragraph under the
section for its own policy — which gate is never skipped, what happens when the host
cannot prompt at all — but not a second copy of the mechanics.

A skill whose only mention of `AskUserQuestion` is documentation about the field (as in
`skill-audit`'s rubric) does not need the section, and neither does a Claude-only skill.

**A skill may deliberately refuse structured-choice prompting**, and then it carries its own
`Asking the User` section saying so instead of the canonical one. `skills/pr-review`
and `skills/changes-review` do: they publish outward-facing correspondence, and the
gate that approves it has to be answerable *after* reading the text it is about, which a
modal firing mid-report is not. Both ask one question in prose as the last line, so
`AskUserQuestion` is absent from `allowed-tools` and appears in the body only as the thing
being refused. `skill-metrics.mjs` reports these as `mentioned, NO fallback wording found`,
because its heuristic cannot tell a refusal from an omission — that flag is expected on
those two, and the fix is never to re-add the canonical section.

## Portability

Skills for different agents (Claude Code, Codex, etc.) live side by side in `skills/` — no
nesting by agent.

### `compatibility` declares the hosts

**`compatibility` is the single source of truth for host support.** It is not just
documentation: `scripts/skills-packaging.sh sync-repo` parses it to decide which skills land
in each host's generated tree, so editing it changes what ships.

Recognised host tokens are `Claude Code`, `Codex`, `OpenCode`, and `Pi`, comma-separated:

```yaml
compatibility: Claude Code                        # Claude-only — needs a documented reason
compatibility: Claude Code, Codex, OpenCode, Pi   # fully portable (the common case)
```

**Universal skill:** Omit `compatibility` entirely — the skill works with any agent.

**The Codex set must be a subset of every other host's set.** Codex, OpenCode, and pi all
read `.agents/skills/`, which carries the Codex-vetted set, and each non-Codex host also
reads its own tree. So the set a host really sees is its own tree unioned with the Codex
tree. If a skill declared `Codex` but not `Pi`, pi would still pick it up from
`.agents/skills/` despite never declaring support. `scripts/validate-codex.sh` fails on
that combination. In practice: a skill that is Codex-safe is portable, so declare all four.

Adding a host to a skill is not free. Check that the body has no Claude-only dependency —
`AskUserQuestion` without a chat fallback, `subagent_type`, Skill-tool orchestration,
`${CLAUDE_SESSION_ID}`, or `~/.claude/...` paths. Do not rely on `compatibility` alone to hide
an unsupported skill from Codex: add `Codex` only after reviewing that the instructions are
actually Codex-safe, and expose the skill through `scripts/codex/catalog.json`
([packaging.md](packaging.md#codex-wrapper)).

The README "Available Skills" table has an **Agents** column for quick scanning.

### Claude-only mechanisms

The Agent Skills [spec](https://agentskills.io/specification) defines a portable subset. The
following fields and features are Claude Code extensions — silently ignored by the spec, and
never relied on in a skill declaring `Codex`, `OpenCode`, or `Pi`, where they would cause silent
behavior differences across hosts:

- `` !`command` `` dynamic injection and ` ```! ` blocks
- Skill-scoped `hooks:`
- `effort`, `paths`, `shell`
- `${CLAUDE_SKILL_DIR}` and other `${CLAUDE_*}` substitutions
- `ToolSearch`, `TodoWrite`, `SlashCommand`, `subagent_type`

When a portable skill needs bundled-script paths, keep the `<skill-dir>` prose placeholder and
let the agent resolve it contextually. Save `${CLAUDE_SKILL_DIR}` for Claude-only skills.

**Most of this is enforced, not advised.** `validate-skills.sh` hard-fails a skill declaring
`Codex`, `OpenCode`, or `Pi` that contains `` !`command` `` injection, a `${CLAUDE_*}`
substitution, `ToolSearch`, `TodoWrite`, `SlashCommand`, or `subagent_type` — in `SKILL.md` or
any bundled `.md`. The frontmatter fields and ` ```! ` blocks are not detected. Claude-only
skills are exempt, since for them these are the correct mechanism. The rule exists because advice
did not hold: the since-retired `build/skills/commit` sat in the Codex catalog with its entire
context-gathering section written as seven injected commands, plus three body lines instructing
the agent not to gather the context itself. On Codex, OpenCode, and pi the skill had no git state
and was told not to look for any. Detection details and the one exempt skill are in
[validation.md](validation.md#claude-only-pattern-detection).

### Subagent dispatch is intent

**Subagent dispatch is written as intent, never as mechanism.** A skill declaring any
non-Claude host must not name a tool, an agent type, or a model when it dispatches work. Say
what to spawn and what it must return, and note the inline fallback for hosts without
subagents:

```
Dispatch a subagent to scan the target files against the active convention
rules and return structured violations. If the host has no subagent facility,
run the same prompt inline.
```

For dispatch specifically, per-host "Claude Code path / Codex path" splits and host-hint
parentheticals (`` `subagent_type: Explore` (Claude Code; use the host's nearest equivalent
elsewhere)``) are violations, not fallbacks — the aim is one set of instructions every agent
can follow. When the dispatched prompt is long enough to matter, put it in the skill's
`references/*-prompt.md` and point every host at the same file; never keep a second copy in a
plugin `agents/` file, which only Claude Code can read and which drifts the moment one is edited.

Three things this rule does **not** cover:

- `allowed-tools` — a declaration, not an instruction. A portable skill that dispatches
  subagents should still declare `Task` / `Agent` for Claude Code's pre-approval, and that is
  not a mismatch with intent-only prose in the body.
- `AskUserQuestion` — the per-host fallback in [Asking the User](#asking-the-user) is
  *required*, not forbidden.
- Per-host **data**, such as `skills/handoff`'s table of where each host stores its
  transcripts. Facts that genuinely differ per host belong in a table with a documented
  default; only the dispatch procedure has to be uniform.

### Claude-only skills, and how others became portable

One skill is `compatibility: Claude Code`, locked by what it actually does. It should stay
Claude-only unless its workflow changes:

- `skills/code-to-spec` — dispatches fleets of plugin-namespaced subagents via
  `subagent_type` and keys temp files on `${CLAUDE_SESSION_ID}`.

`skills/consilium` was Claude-only for the same reasons and is now portable. It stopped
being a review skill: it is an approach board that takes a problem or a decision, generates
candidate approaches from independent seats, and ranks them. Making it portable was mostly
subtraction — dispatch is stated as intent, model choice as intent, its outside seat runs through `outsider` instead of a private `codex exec`
wrapper, and the temp files that forced `${CLAUDE_SESSION_ID}` are gone entirely because the
candidate set travels in the dispatched prompt and `outsider` owns the one file that still hits
disk.

`skills/issue-flow` and `skills/solve-issue` were Claude-only for the same
reason `changes-review` was: they named the mechanism. Both now state delegation as intent
("invoke `issue-flow`", "dispatch one subagent"), each call site documents what to do when
the host cannot chain skills or has no subagents, and both carry the standard
`AskUserQuestion` fallback in a single `Asking the User` convention rather than repeating
it at sixteen call sites. `issue-flow` owns every git and `gh` write in the pipeline, so
`solve-issue` holds no duplicate of its commit format or squash rules — the seam is what
made them portable.

`skills/changes-review` was Claude-only for its per-agent `model` overrides. It now
states model choice as intent — most capable model the host offers, next tier down when that is
the orchestrator's own, a different one per reviewer where the host allows it — and degrades to
role diversity alone where it does not. Model diversity is still half of why the reviewers
disagree usefully, so the report says which kind of diversity a run actually got.

`skills/outsider` used to be two skills, `codex` and `claude`, each excluded from the
host it would have called recursively. It now resolves an installed agent CLI that is not the
current host, so it declares all four hosts and still never invokes itself. Recursion is a
selection rule in `scripts/run-outsider.sh`, not a `compatibility` omission — which is the
pattern to follow for anything else that shells out to an agent CLI.
