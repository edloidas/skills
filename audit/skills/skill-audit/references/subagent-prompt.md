# Worker Prompt Template

Self-contained prompt for one per-skill audit worker. Replace `{{SKILL_PATH}}`,
`{{REPO_ROOT}}`, and `{{METRICS}}` before dispatch.

Read-only work — file reads, globs, and content search. A cheap worker with a short turn
budget (around 10 turns) is enough. The measurements are handed in, so the worker never
needs a shell.

## Prompt

```
You are auditing one Agent Skill: {{SKILL_PATH}}, rooted at {{REPO_ROOT}}.

Structural correctness has already been checked by scripts and is NOT your job. Do not
score frontmatter validity, name/directory agreement, description length caps, dangling
file paths, Codex catalog membership, or the host-subset rule — those either passed or
were reported to the orchestrator. Your job is the five judgment questions below.

INSTRUCTIONS
1. Read every file in {{REPO_ROOT}}/{{SKILL_PATH}}/ — SKILL.md plus anything under
   references/, scripts/, assets/, agents/. Read-only access only: file reads, globs, and
   content search. Do not run shell commands.
2. Use the measurements below as fact. Do not recount lines or re-derive them.
3. Score each of the five categories 1-5 and cite specific evidence — a line number, a
   quoted phrase, or a file path. A score with no evidence is INVALID.
4. Report up to 5 issues, 3 strengths, and 3 recommendations.
5. Use EXACTLY the output format at the bottom.

MEASUREMENTS FOR THIS SKILL
{{METRICS}}

SCALE
5 could serve as a template | 4 minor issues, ship it | 3 fix next cycle |
2 fix before publishing | 1 unusable or actively misleading

1. DISCOVERY — will name + description + when_to_use ever fire, on the right situations?
   Nothing below the frontmatter is visible at discovery time, so a `## Keywords` section
   in the body contributes nothing. A description that states an attitude ("reviews
   critically", "does not let bad things slide") instead of a situation can never match a
   request. Check the discovery-overlap line in the measurements: a high-scoring pair means
   at least one of the two skills never wins its trigger, and that is a finding against
   both. Sibling skills that legitimately live close together should each state the
   boundary in the description.
   | 5 | Specific, situational, unmistakably distinct from siblings. |
   | 4 | Triggerable. One vague clause, or a near neighbour whose boundary is only implied. |
   | 3 | Fires, but over- or under-broadly. Topic clear, situation not. |
   | 2 | Overlaps a sibling with no stated boundary, or describes attitude, not a situation. |
   | 1 | Nothing in the entry could match a real request. |

2. INSTRUCTION QUALITY — can an agent follow the body to the end without guessing?
   Ordered steps; a worked example or concrete command per non-obvious step; output format
   specified; edge cases and missing-dependency behaviour documented; no contradictions
   between sections or with the frontmatter. Every artefact the body promises must actually
   ship — including the soft version, where a checklist, catalog, or template is described
   in prose but exists nowhere in the skill. Files listed as "unreachable bundled files" in the
   measurements are named by nothing in the skill and count against this category.
   | 5 | Followable start to finish; examples, output format, failure modes present. |
   | 4 | One gap: thin example, or an undocumented edge case. |
   | 3 | Missing examples or missing edge cases, not both. |
   | 2 | Steps unclear or out of order; promises material it does not ship; neither examples nor edge cases. |
   | 1 | Contradictory or effectively absent. |

3. CONTEXT EFFICIENCY — does the body earn its size, and is heavy material deferred?
   Body under 500 lines / ~5000 tokens. Reference material — lookup tables, rule catalogs,
   prompt templates, mappings — belongs in references/, loaded on demand, not inlined; the
   measurements give the largest inline table or code block. No nested reference chains, no
   content duplicated between SKILL.md and a reference. Length should be proportionate: a
   400-line body for a three-step task is a finding even under the cap.
   | 5 | Lean body, heavy content deferred, size proportionate. |
   | 4 | One table or block that belongs in references/. |
   | 3 | Under the cap but bloated, or no references where splitting would help. |
   | 2 | Over the guidance with reference material inlined, or duplicated content. |
   | 1 | Far past the token estimate; expensive to load before it does anything. |

4. PORTABILITY & INTEGRATION — does `compatibility` tell the truth about the body?
   `compatibility` decides which host trees the skill is packaged into, so a wrong value
   ships it to a host that cannot run it. Every declared host must be able to complete the
   main path. In a skill declaring Codex, OpenCode, or Pi, dispatch must be written as
   intent — what to spawn and what it must return — and naming a tool, an agent type, or a
   model is a violation, as are per-host "Claude Code path / Codex path" splits and
   host-hint parentheticals. AskUserQuestion needs a plain-chat fallback there.
   Three things are NOT violations: `allowed-tools` (a declaration, not an instruction — a
   portable skill that dispatches workers should still declare Task/Agent); the
   AskUserQuestion fallback itself; and per-host *data* presented in a table with a
   documented default. Each host-mechanism hit in the measurements must be resolved as
   either a real violation or legitimate per-host data — say which.
   Also: allowed-tools scoped to what the body does, any `model` override justified,
   bundled scripts invoked from the workflow with their runtime dependency stated, and
   where agents/openai.yaml exists, a display_name and short_description that read like the
   skill plus allow_implicit_invocation: false for anything destructive.
   | 5 | compatibility matches the body exactly; dispatch intent-only; tools scoped. |
   | 4 | Accurate overall. One over-broad tool declaration or a thin short_description. |
   | 3 | A declared host hits friction but could finish, or allowed-tools drifts from the body. |
   | 2 | A declared host cannot complete the main path; dispatch names a tool/agent/model; AskUserQuestion with no fallback. |
   | 1 | compatibility is contradicted outright by the body. |

5. SAFETY & ROBUSTNESS — can this skill damage something without being told to?
   Mutations gated on explicit approval: writes outside the skill's own scratch space, git
   push, force-push, branch or tag deletion, issue and PR creation, merges, publishes, any
   gh api write. Destructive operations called out in the body. Bundled scripts validate
   inputs, set failure modes, and emit actionable errors. External dependencies named with
   what happens when one is missing. Nothing writes into a generated tree a sync script owns.
   | 5 | Every mutation gated, dependencies named, scripts fail loudly, tools minimal. |
   | 4 | One gap: a missing input check, or a dependency named without a fallback. |
   | 3 | A low-stakes mutation is ungated, or dependencies partly documented. |
   | 2 | A meaningful mutation runs without approval, or undeclared script dependencies. |
   | 1 | A destructive operation with no gate and no warning. |
   A read-only skill starts at 5 and loses points only for undeclared dependencies or
   over-broad tools. Absence of risk surface is not a gap.

GENERAL
- Evidence or nothing: cite a line, a quote, or a path for every score.
- Same bar for a 60-line skill and a 500-line one.
- Impact over cosmetics.
- Do NOT penalise Claude Code extension fields — model, user-invocable, context, agent,
  argument-hint, disable-model-invocation, hooks, paths, effort, shell, arguments are valid
  frontmatter other hosts ignore. user-invocable defaults to true; its absence is not a gap.

OUTPUT FORMAT (follow exactly):

SKILL: {{SKILL_PATH}}

SCORES:
- Discovery: <1-5> | <evidence>
- Instruction Quality: <1-5> | <evidence>
- Context Efficiency: <1-5> | <evidence>
- Portability & Integration: <1-5> | <evidence>
- Safety & Robustness: <1-5> | <evidence>

TOP ISSUES (max 5, most impactful first):
1. [Category] Description — file:line or quote
...

STRENGTHS (max 3):
1. Description
...

RECOMMENDATIONS (max 3, actionable):
1. Description
...
```
