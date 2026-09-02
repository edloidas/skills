# Evaluation Rubric

Six judgment categories, each scored 1–5. Everything mechanically checkable was moved into
`.github/scripts/validate-skills.sh`, `scripts/validate-codex.sh`, and
`scripts/skill-metrics.mjs` — cite their output as evidence, never re-derive it, and never
score a skill down for something they report clean. The body line cap, shouty-emphasis
tokens (`CRITICAL:`, `You MUST`, `MANDATORY` used to force compliance), the behavioural-style
word list ("be concise", "think carefully", "double-check your work"), and the calibration
adverbs in discovery text all belong to `validate-skills.sh`. Cite it; do not score them
again here. What is left below is judgment: whether a passage is calibrating the model
instead of specifying the task, which is a call no word list can make.

Scale: **5** could serve as a template · **4** minor issues, ship it · **3** should be fixed
next cycle · **2** fix before publishing · **1** unusable or actively misleading.

## 1. Discovery

Discovery is the only phase every skill pays for in every session. `name`, `description`,
and `when_to_use` are all the host reads before deciding — everything below the frontmatter
is invisible at this point.

**Checks:**

- [ ] The description names a *situation*, not a stance. "Reviews code critically and does
      not let bad things slide" describes an attitude and can never match a request.
      "Reviews a diff for correctness bugs before committing" can.
- [ ] Trigger phrasing is present and reads like something a user would actually type.
- [ ] The description says what the skill *does*, what it takes as input, and when it
      applies — not just its topic.
- [ ] No sibling skill claims the same trigger. Check the discovery-overlap section of the
      metrics output; a high-scoring pair means at least one of the two never wins.
- [ ] Where two skills legitimately live near each other, each description states the
      boundary explicitly ("for X use this, for Y use `<other-skill>`").
- [ ] `when_to_use` carries the trigger phrases rather than a `## Keywords` section in the
      body, which is loaded too late to affect discovery at all.
- [ ] The discovery entry is proportionate: a narrow skill does not spend 900 characters.
- [ ] No word in `description` or `when_to_use` calibrates the model rather than describing
      the situation — "thoroughly", "concisely", "carefully". They cannot make a skill fire,
      and they bias the host before the body is even loaded. A trigger phrase a user would
      actually type is exempt: `consilium`'s "think hard" and "ultrathink" are correct
      discovery text, because people type them.

**Anchors:**

| Score | Criteria |
| ----- | -------- |
| 5 | Specific, situational, unmistakably distinct from every sibling. Would fire when it should and stay quiet otherwise. |
| 4 | Clear and triggerable. One vague clause, or a near neighbour whose boundary is implied rather than stated. |
| 3 | Fires, but over- or under-broadly. Topic is clear, the triggering situation is not. |
| 2 | Overlaps a sibling with no stated boundary, or describes attitude and capability instead of a situation. |
| 1 | Nothing in the entry could match a real request. The skill is effectively unreachable. |

## 2. Instruction Quality

Whether an agent can follow the body to the end without guessing.

**Checks:**

- [ ] Steps are ordered so each one has what it needs: context, then analysis, then output.
- [ ] At least one worked example or concrete command per non-obvious step.
- [ ] Output format is specified when the skill produces structured output.
- [ ] Edge cases and failure modes are documented, including what to do when a dependency
      is missing.
- [ ] No contradictions between sections, or between the body and the frontmatter.
- [ ] Every artefact the body promises actually ships. `validate-skills.sh` catches a
      dangling path; this catches the softer version — a body describing a checklist,
      catalog, or template in prose that exists nowhere in the skill.
- [ ] Every bundled file is reachable — named by `SKILL.md` or by another bundled file. The
      metrics script lists the unreachable ones; dead weight in a skill ships in the package.
- [ ] Instructions say what to do rather than what to avoid, where both work.
- [ ] One complete worked example of the primary output ships in the body — a filled-in
      instance of the skill's own template, not a second template. Further examples belong
      in `references/`. A skill whose output is a single line already shown needs none.
      Concrete examples are the first thing an author cuts for looking expensive, and they
      steer format and tone better than another paragraph of principle.
- [ ] Every phase spanning more than one tool call names the line it prints at its end, and
      the line carries real counts — `12 raw findings -> 5 after consolidation`, not "done".
      One named line **per phase**: a skill that names a single line for the whole run turns
      that line into the ceiling and goes quiet everywhere else. A phase of one tool call
      needs none. The metrics script counts named-output lines per `##` section.
- [ ] Every phase that could continue ends with a sentence naming what does not follow —
      "Then stop. Do not fix, do not offer to fix, and do not start a second round." Where a
      skill runs rounds, a description of the next round is not a terminal state; the table
      of states is.
- [ ] Where the body says to quote or paste source text, the template shows the marker — a
      literal `> ` line, or a fenced block — and says what to do about elision: unedited, and
      if lines are cut, how many and from where. An instruction to quote against a template
      that renders prose gets prose.
- [ ] Read scope is quantified wherever under-reading is possible: which files, how many, and
      opened together before analysis begins. "What to read" without "how many" gets one file
      read and the rest reasoned about. "Sampled when too large to read whole" needs a floor.
- [ ] Every optional or dynamic check that did not run is named in the report with the
      reason. One check saying "skip it and say so" beside a sibling that does not gets the
      sibling skipped silently, and a partial run reported as green.
- [ ] No finding is gated on the model's own confidence. "Only report what you are certain
      about", "only high-severity", "be conservative" are followed literally and cap recall —
      worst inside a dispatched prompt, where the worker is the one finding things and no
      downstream filter exists. The shape that works is a reported confidence field plus
      filtering in a synthesis phase.
- [ ] Instruction first, rationale after, one line, next to the rule. Rationale is not the
      defect and rationale-heavy skills work; rationale *wrapping* an imperative is the
      defect. In a section with two instructions and thirty lines of reasoning, the
      instructions get extracted and the scope the reasoning attached to them is dropped.
- [ ] A condition attached to a table row lives in the row. A condition in the prose
      following a table is lost while the row is applied.
- [ ] Tables carry classifications, exact mappings, and mutually exclusive cases; prose steps
      carry ordered procedures, exceptions, and nested conditionals. A procedure forced into
      a table binds worse than the same procedure as steps.
- [ ] No trailing `## Rules` or `## Principles` recap restating earlier sections. It fails
      three ways at once: read as emphasis and over-weighted, paid for as repetition, and
      skimmed as a summary — so a rule living only there is lost. Either delete it, or reduce
      it to rules that appear nowhere else.

**Anchors:**

| Score | Criteria |
| ----- | -------- |
| 5 | Followable start to finish. Examples, output format, and failure modes all present. |
| 4 | Good structure. One gap — a thin example, or an edge case worth documenting. |
| 3 | Followable but underspecified: missing examples or missing edge cases, not both. |
| 2 | Steps out of order or unclear; promises material it does not ship; no examples and no edge cases. |
| 1 | Contradictory or effectively absent instructions. |

## 3. Context Efficiency

Whether the body earns its size, and whether the heavy material is deferred.

**Checks:**

- [ ] Body within its line budget. The cap is 500 lines / ~5000 tokens; a few skills carry
      a larger budgeted allowance, listed in `BODY_LINE_BUDGETS` in
      `.github/scripts/validate-skills.sh` with the reason recorded in `CLAUDE.md`.
      `validate-skills.sh` already fails the build on a breach, so do not re-litigate a
      budgeted size here — an allowlisted skill inside its allowance is not a finding.
      Take the numbers from the metrics script.
- [ ] Reference material — lookup tables, rule catalogs, prompt templates, mappings — lives
      in `references/`, loaded on demand, not inlined. The metrics script reports the
      largest inline table or code block; a 60-line table in the body is the classic case.
- [ ] `references/` files are focused and single-purpose.
- [ ] No nested reference chains — a reference file pointing at another reference file
      means the agent pays twice to reach the content.
- [ ] No content duplicated between `SKILL.md` and a reference file.
- [ ] Body length is proportionate to what the skill does. A 400-line body for a
      three-step task is a finding even though it is under the cap.
- [ ] Each rule is stated once, in the section that owns it; every other site
      cross-references that section by name — `per **Asking the User**`, `per **Scope**`.
      The repo already does this for one rule and it generalises to all of them: a second
      copy is the drift mechanism, and repetition costs answer quality as well as tokens.
      Check the duplicate-sentence pairs in the measurements. A strict pair — 12 or more
      shared tokens — is a finding unless the second site is a deliberate condensed copy
      whose purpose the body states out loud, as with a full rubric and the worker prompt
      that carries a shortened version of it. Loose pairs are paraphrase; read them before
      deciding, since a rule rewritten in different words is still stated twice.
- [ ] Locality is not repetition. A constraint belongs beside the action it constrains; a
      safety boundary stated once at the top and never again next to the command that would
      breach it is read three hundred lines too early. Where this pulls against the rule
      above, the one copy moves down to the action and the top cross-references it.
- [ ] An inline fallback for a chained skill is at most five lines and a pointer. A fallback
      longer than the invocation is taken every time, and it is a second copy of the skill it
      replaces. The metrics script reports the length of each one.
- [ ] Where a body is over its budget, the cut order is: duplicated mission statements and
      restated procedure summaries; historical rationale not attached to a live constraint,
      compressed to one line; "Core Principle" sections that change no later decision;
      failure-mode tables that only restate the procedure; generic agent-behaviour advice.
      Never cut task-specific boundaries, decision criteria, gates, edge cases, required
      commands, output schemas, worked examples, or the one-line reason behind a surprising
      rule.

**Anchors:**

| Score | Criteria |
| ----- | -------- |
| 5 | Lean body, heavy content deferred, size proportionate to the task. |
| 4 | Well balanced. One table or block that would be better in `references/`. |
| 3 | Under the cap but bloated, or no references where splitting would clearly help. |
| 2 | Over the guidance with reference material inlined, or the same content in two places. |
| 1 | Body far past the token estimate; the skill is expensive to load before it does anything. |

## 4. Portability & Integration

Whether `compatibility` tells the truth about what the body requires, and whether tools and
scripts are declared honestly.

`compatibility` is not documentation — `scripts/skills-packaging.sh sync-repo` parses it to
decide which host trees the skill lands in. A wrong value ships the skill to a host that
cannot run it.

**Checks:**

- [ ] Every host in `compatibility` can actually execute the body. A skill declaring Codex,
      OpenCode, or Pi must not require a Claude-only facility to complete its main path.
- [ ] Dispatch is written as intent — what to spawn and what it must return — never as
      mechanism. Naming a tool, an agent type, or a model is a violation, and so are
      per-host "Claude Code path / Codex path" splits and host-hint parentheticals.
- [ ] `AskUserQuestion` in a skill declaring a non-Claude host carries the repo's canonical
      `Asking the User` section, **verbatim** — see CLAUDE.md. Ad-hoc wording that says the
      same thing differently is a finding, not a pass: the section is copied so a reader can
      tell a deliberate variation from drift. Call sites say `per **Asking the User**` and do
      not restate the mechanics.
- [ ] The Claude-only mechanisms `validate-skills.sh` hard-fails — `` !`command` `` injection,
      `${CLAUDE_*}`, `ToolSearch`, `TodoWrite`, `SlashCommand`, `subagent_type` — are the
      validator's job, not the rubric's. Cite it rather than re-scoring them.
- [ ] Legitimate exceptions are not flagged. `allowed-tools` is a declaration, not an
      instruction — a portable skill that dispatches workers *should* declare `Task` /
      `Agent`. Per-host **data** in a table with a documented default is also fine.
- [ ] The metrics script's host-mechanism hits are each accounted for: either a real
      violation, or per-host data that belongs where it is.
- [ ] A Claude-only `compatibility` has a reason a reader can see in the body.
- [ ] `allowed-tools` matches what the body does, and is scoped — `Bash(git:*)` over bare
      `Bash` where the narrower form suffices.
- [ ] A `model` override, where present, is justified by the work rather than habit.
- [ ] Every dispatch site carries a numeric threshold or a named trigger — "~500 changed
      lines or ~20 files", "waves of at most 8". "When the surface is wide" is neither: one
      host spawns a fleet on it and another spawns nothing. Where the count is deliberately
      unbounded, that is a decision the body states, not an omission. The metrics script
      lists dispatch lines carrying no count and no condition.
- [ ] Bundled scripts are invoked from the workflow, with their runtime dependency stated.
- [ ] **Codex surface**, where the repo has one: `agents/openai.yaml` carries a
      `display_name` and a `short_description` that reads like the skill, and
      `allow_implicit_invocation: false` for anything destructive or environment-specific.
      Catalog membership and the host-subset rule are `validate-codex.sh`'s job — cite it.

**Anchors:**

| Score | Criteria |
| ----- | -------- |
| 5 | `compatibility` matches the body exactly. Dispatch is intent-only, tools scoped, Codex metadata accurate. |
| 4 | Accurate overall. One over-broad tool declaration or a thin `short_description`. |
| 3 | A declared host would hit friction but could still finish, or `allowed-tools` drifts from what the body does. |
| 2 | A declared host cannot complete the main path; dispatch names a tool, agent type, or model; `AskUserQuestion` with no fallback. |
| 1 | `compatibility` is contradicted outright by the body — the skill ships to hosts that cannot run it. |

## 5. Safety & Robustness

Whether the skill can damage something without being told to.

**Checks:**

- [ ] Mutations are gated on explicit user approval: file writes outside the skill's own
      scratch space, `git push`, force-push, branch or tag deletion, issue and PR creation,
      merges, publishes, and any `gh api` write.
- [ ] Destructive operations are called out in the body, not just implied by a command.
- [ ] Bundled scripts validate inputs, set failure modes (`set -euo pipefail` or the
      equivalent), and emit an error message a reader can act on.
- [ ] External dependencies are named — `gh`, `jq`, `node`, `rg`, whatever — with what
      happens when one is missing.
- [ ] Read-only skills say so, and their `allowed-tools` reflects it.
- [ ] Nothing writes into a generated tree that a sync script owns.
- [ ] The mutation class is stated in the first 15 lines of the body, in one of four terms:
      reports only (tree byte-identical) · local writes only · writes and pushes · writes to
      external services. Stated three times, keep the first and cut the rest.
- [ ] The skill states its own delta and not the baseline: which writes it performs, which
      gates it never skips. It does not re-derive general autonomy semantics, which belong to
      `CLAUDE.md` — but because that file does not exist in a repo the skill is installed
      into, the delta has to be concrete. Name the writes; do not explain the philosophy.
- [ ] A skill that edits files states the edit mechanic once: targeted edits per hunk, never
      a whole-file rewrite. Removing six comments from a 300-line file by rewriting the file
      picks up trailing-whitespace and quote-style changes nobody asked for. "Surgical"
      language about *scope* is a different statement and does not substitute for it.
- [ ] No instruction to double-check its own output — "before finishing, verify your answer",
      "use a second pass to check your own work". Those are followed, cost a round, and add
      nothing. What is not self-verification and stays: an independent agent attacking the
      artefact blind to the implementer's reasoning, the project's own tests, build, and
      lint, and observing what the thing actually printed. The defence against a bolted-on
      extra re-check is the stop sentence scored under Instruction Quality, not a
      prohibition here.

**Anchors:**

| Score | Criteria |
| ----- | -------- |
| 5 | Every mutation gated, dependencies named with fallbacks, scripts fail loudly, tools minimally scoped. |
| 4 | Sound. One gap — a script missing an input check, or a dependency named without a fallback. |
| 3 | A low-stakes mutation is ungated, or dependencies are only partly documented. |
| 2 | A meaningful mutation runs without approval, or a script has undeclared dependencies. |
| 1 | A destructive operation with no gate and no warning. Could lose work. |

A skill that only reads starts at 5 here and loses points only for undeclared dependencies
or over-broad tools. Absence of risk surface is not a gap.

## 6. Layer Discipline

Whether the body confines itself to what this task requires. Four layers hold instructions
and each rule lives in exactly one:

| Layer | Owns |
| ----- | ---- |
| Host system prompt | Model calibration the host tunes per model: verbosity, narration cadence, formatting density, thinking depth, blanket self-verification |
| `CLAUDE.md` | Cross-cutting policy for this person and this repo: commit format, autonomy baseline, comment policy, git conventions, general scope discipline |
| `SKILL.md` body | What this task requires and only this task: the procedure, its gates, its output contract, its safety boundary |
| `references/` | Material consulted *during* execution: rule catalogs, dispatched prompts, lookup tables, worked examples |

A line from another layer in a body is paid for in every session, silently contradicts
whatever the host already said, and drifts from the copy that owns it. Two questions decide
any candidate line:

- Would it still be correct if the task were different? Then it is not the skill's line.
- Would the skill produce *wrong results* without it, as opposed to differently-styled
  results? If not, it is not the skill's line.

**The exception is the authorization delta.** These skills are installed into other people's
repos, where our `CLAUDE.md` does not exist, so a skill states its own read-only or mutation
boundary in its own body — that is scored under Safety and is not a layer violation here.
What it must not do is restate what "read-only" *means*.

**Checks:**

- [ ] No host-layer calibration in the body: how much to narrate, how densely to format, how
      long an answer should be in adjectives, how hard to think. The word list is
      `validate-skills.sh`'s job — cite it. The judgment here is the passage it cannot see:
      a paragraph that tunes the model instead of specifying the task.
- [ ] Deliverable length is given in units or as a check, never as an adjective. "One section
      per cause, at most four." "One line: `Committed <sha>`." "Shorter than the original,
      always; if it is not, cut more." An adjective is a knob every model turns differently;
      a unit is a fact.
- [ ] No restatement of general scope discipline — "deliver what was asked", "do not widen
      the scope", "finish the whole task".
- [ ] No restatement of repo-wide git, commit-message, or comment policy, unless this
      skill's own procedure turns on the specific value.
- [ ] Prescriptive steps are **not** a layer violation. These skills exist to replace the
      model's default procedure — a squash rule, a cold-dispatch discipline — and "review it
      thoroughly" is exactly the failure they were written against. Judge whether a line
      calibrates the model, not whether it is specific.

**Anchors:**

| Score | Criteria |
| ----- | -------- |
| 5 | Every line is task-specific. Mutation class stated, nothing borrowed from another layer. |
| 4 | One borrowed line — a stray "be thorough", a restated git convention. |
| 3 | A paragraph of host-layer or `CLAUDE.md` material, or length given as an adjective in the deliverable contract. |
| 2 | Several passages calibrate the model or restate repo policy, competing with the task-specific content. |
| 1 | Mostly general agent advice; another skill's body would read much the same. |

## Scoring Guidelines

- **Evidence or nothing.** A score without a line, quote, or path is invalid.
- **Same bar everywhere.** A 4 must mean the same thing for a 60-line skill and a 500-line one.
- **Impact over cosmetics.** A heading skip is worth a sentence; a description that never
  fires is worth the finding that gets the skill rewritten.
- **Proportionality.** Complexity should track the task. A skill that reformats text does
  not need workers, references, and a scoring rubric.
- **Do not penalise Claude Code extension fields.** `model`, `user-invocable`, `context`,
  `agent`, `argument-hint`, `disable-model-invocation`, `hooks`, `paths`, `effort`, `shell`,
  and `arguments` are valid frontmatter that other hosts ignore. `user-invocable` defaults
  to `true`; its absence is not a gap.
