# Evaluation Rubric

Five judgment categories, each scored 1–5. Everything mechanically checkable was moved into
`.github/scripts/validate-skills.sh`, `scripts/validate-codex.sh`, and
`scripts/skill-metrics.mjs` — cite their output as evidence, never re-derive it, and never
score a skill down for something they report clean.

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
