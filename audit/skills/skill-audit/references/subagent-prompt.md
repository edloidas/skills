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
were reported to the orchestrator. The body line cap, shouty emphasis (CRITICAL:, You MUST,
MANDATORY), and behavioural-style words ("be concise", "think carefully") are also the
validator's, not yours. Your job is the six judgment questions below.

INSTRUCTIONS
1. List every file in {{REPO_ROOT}}/{{SKILL_PATH}}/ — SKILL.md plus anything under
   references/, scripts/, assets/, agents/ — and open all of them before you score anything.
   Scoring from SKILL.md alone is invalid. Read-only access: file reads, globs, and content
   search. Do not run shell commands.
2. Use the measurements below as fact. Do not recount lines or re-derive them.
3. Score each of the six categories 1-5 and cite specific evidence — a line number, a
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
   boundary in the description. No word in the discovery entry should calibrate the model
   rather than name the situation — "thoroughly", "concisely", "carefully" cannot make a
   skill fire and bias the host before the body loads. Trigger phrases a user would really
   type ("think hard", "ultrathink") are exempt.
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
   Also required, each a real finding when absent:
   - One complete worked example of the primary output in the body — a filled-in instance,
     not a second template. A skill whose output is one line already shown needs none.
   - Every phase spanning more than one tool call names the line it prints at its end, and
     the line carries counts ("12 raw findings -> 5 after consolidation"). One named line
     PER PHASE: a single line for the whole run becomes the ceiling and the rest goes quiet.
   - Every phase that could continue ends with a sentence naming what does not follow
     ("Then stop. Do not fix, do not offer to fix, do not start a second round").
   - Where the body says to quote or paste source text, the template shows the marker — a
     literal "> " line or a fenced block — and says what to do about elision.
   - Read scope is quantified where under-reading is possible: which files, how many, opened
     together before analysis. "Sampled when too large to read whole" needs a floor.
   - Every optional or dynamic check that did not run is named in the report with the reason.
   - NO finding gated on the model's own confidence: "only report what you are certain
     about", "only high-severity", "be conservative" are followed literally and cap recall,
     worst in a dispatched prompt. A reported confidence field plus filtering in a synthesis
     phase is the shape that works.
   - Instruction first, rationale after, one line, next to the rule. Rationale is not the
     defect; rationale wrapping an imperative is, because the imperative gets extracted and
     the scope the reasoning attached to it is dropped.
   - A condition attached to a table row lives in the row, not in the prose after the table.
   - Tables for classifications and exact mappings; prose steps for ordered procedures,
     exceptions, and nested conditionals.
   - No trailing "## Rules" recap restating earlier sections — over-weighted as emphasis,
     paid for as repetition, skimmed as summary, so a rule living only there is lost.
   | 5 | Followable start to finish; examples, output format, failure modes present. |
   | 4 | One gap: thin example, or an undocumented edge case. |
   | 3 | Missing examples or missing edge cases, not both. |
   | 2 | Steps unclear or out of order; promises material it does not ship; neither examples nor edge cases. |
   | 1 | Contradictory or effectively absent. |

3. CONTEXT EFFICIENCY — does the body earn its size, and is heavy material deferred?
   Body within its line budget — 500 lines / ~5000 tokens, except for the few skills with a
   larger budgeted allowance in BODY_LINE_BUDGETS in .github/scripts/validate-skills.sh.
   That validator fails the build on a breach, so a budgeted skill inside its allowance is
   not a finding here. Reference material — lookup tables, rule catalogs,
   prompt templates, mappings — belongs in references/, loaded on demand, not inlined; the
   measurements give the largest inline table or code block. No nested reference chains, no
   content duplicated between SKILL.md and a reference. Length should be proportionate: a
   400-line body for a three-step task is a finding even under the cap.
   Each rule is stated ONCE, in the section that owns it, and other sites cross-reference
   that section by name ("per **Asking the User**"). Check the duplicate-sentence pairs in
   the measurements: a strict pair (12+ shared tokens) is a finding unless the second site is
   a deliberate condensed copy the body declares as such; loose pairs are paraphrase, so read
   them before deciding. Locality is the counterweight — a constraint belongs beside the
   action it constrains, so the fix for a rule stated twice is usually to keep the copy next
   to the action and cross-reference from the top. An inline fallback for a chained skill is
   at most 5 lines and a pointer; a longer one gets taken every time and is a second copy of
   the skill it replaces.
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
   host-hint parentheticals. A skill that asks must carry the repo's canonical
   `Asking the User` section verbatim (see CLAUDE.md); ad-hoc wording of the same rule is a
   finding, and call sites must not restate the mechanics. The mechanisms validate-skills.sh
   hard-fails — !`command` injection, ${CLAUDE_*}, ToolSearch, TodoWrite, SlashCommand,
   subagent_type — are the validator's job; cite it instead of re-scoring them.
   Three things are NOT violations: `allowed-tools` (a declaration, not an instruction — a
   portable skill that dispatches workers should still declare Task/Agent); the
   AskUserQuestion fallback itself; and per-host *data* presented in a table with a
   documented default. Each host-mechanism hit in the measurements must be resolved as
   either a real violation or legitimate per-host data — say which.
   Every dispatch site must carry a numeric threshold or a named trigger — "~500 changed
   lines or ~20 files", "waves of at most 8". "When the surface is wide" is neither: one host
   spawns a fleet on it and another spawns nothing. A deliberately unbounded count is fine
   when the body says so. The measurements list dispatch lines with no count and no condition.
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
   The mutation class appears in the first 15 lines of the body, as one of: reports only
   (tree byte-identical) / local writes only / writes and pushes / writes to external
   services — and once, not three times. The skill states its own delta (which writes, which
   gates) concretely, because CLAUDE.md does not exist in a repo it is installed into. A
   skill that edits files states the edit mechanic once: targeted edits per hunk, never a
   whole-file rewrite ("surgical" about scope is a different statement). No instruction to
   double-check its own output; an independent agent attacking the artefact, the project's
   tests and lint, and observing real output are NOT self-verification and stay.
   | 5 | Every mutation gated, dependencies named, scripts fail loudly, tools minimal. |
   | 4 | One gap: a missing input check, or a dependency named without a fallback. |
   | 3 | A low-stakes mutation is ungated, or dependencies partly documented. |
   | 2 | A meaningful mutation runs without approval, or undeclared script dependencies. |
   | 1 | A destructive operation with no gate and no warning. |
   A read-only skill starts at 5 and loses points only for undeclared dependencies or
   over-broad tools. Absence of risk surface is not a gap.

6. LAYER DISCIPLINE — does the body confine itself to what this task requires?
   Four layers hold instructions. The HOST SYSTEM PROMPT owns model calibration: verbosity,
   narration cadence, formatting density, thinking depth, blanket self-verification.
   CLAUDE.md owns cross-cutting policy for the user and the repo: commit format, autonomy
   baseline, comment policy, git conventions, general scope discipline. The SKILL.md BODY
   owns what this task requires and nothing else. references/ owns material consulted during
   execution. A line from another layer is paid for every session, silently contradicts what
   the host already said, and drifts from the copy that owns it.
   Two questions decide any line: would it still be correct if the task were different — then
   it is not the skill's line; would the skill produce WRONG results without it, as opposed
   to differently-styled results — if not, it is not the skill's line.
   THE EXCEPTION is the authorization delta. These skills install into other people's repos
   where CLAUDE.md does not exist, so a skill stating its own read-only or mutation boundary
   is correct and is scored under Safety, not penalised here. It must not restate what
   "read-only" means.
   Also check: deliverable length given in units or as a check, never as an adjective ("one
   section per cause, at most four" / "shorter than the original, always" — not "be
   concise"); no restatement of general scope discipline ("deliver what was asked", "do not
   widen the scope"); no restatement of repo-wide git or comment policy unless the procedure
   turns on the value.
   Prescriptive steps are NOT a violation. These skills exist to replace the model's default
   procedure; "review it thoroughly" is the failure they were written against. Judge whether
   a line calibrates the model, not whether it is specific.
   | 5 | Every line task-specific; mutation class stated; nothing borrowed from another layer. |
   | 4 | One borrowed line — a stray "be thorough", a restated git convention. |
   | 3 | A paragraph of host-layer or CLAUDE.md material, or length given as an adjective. |
   | 2 | Several passages calibrate the model or restate repo policy. |
   | 1 | Mostly general agent advice; another skill's body would read much the same. |

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
- Layer Discipline: <1-5> | <evidence>

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
