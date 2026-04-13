---
name: skill-audit
description: >
  Audit Agent Skills for quality, compliance, and best practices. Evaluates skills
  against the Agent Skills specification across 6 core categories plus a conditional
  Codex Integration category covering `agents/openai.yaml`, Codex compatibility,
  catalog exposure, and wrapper sync. Produces scored reports with evidence-backed
  findings. Use when the user asks to audit, evaluate, review, or check skill quality
  or Codex readiness.
license: MIT
compatibility: Claude Code, Codex
allowed-tools: Read Glob Grep Task Bash(bash:audit/skill-audit/*) Bash(bash:scripts/validate-codex.sh)
user-invocable: true
argument-hint: "[all or skill names]"
metadata:
  author: edloidas
---

# Skill Audit

## Purpose

Systematically evaluate skills against the Agent Skills specification, AI instruction best practices, and this repo's Codex packaging contract. Audit the skill itself first, then audit repo-level Codex exposure only when the target skill claims Codex support or is exposed through the Codex catalog.

## When to Use This Skill

Use when the user asks to:
- "Audit skills" or "audit the skills"
- "Evaluate skill quality"
- "Check skills against the spec"
- "Review skill compliance"
- "Score skill X"
- "Check whether a skill is Codex-ready"
- "Audit Codex compatibility for a skill"

Trigger phrases: "skill audit", "audit skills", "evaluate skills", "skill quality", "skill review", "skill score", "codex ready", "codex compatibility"

## Commands

| Command | Scope | Description |
|---------|-------|-------------|
| `/skill-audit` | All | Audit all skills (excluding `skill-audit` itself) |
| `/skill-audit all` | All | Same as above |
| `/skill-audit name [name ...]` | Specific | Audit one or more named skills |

When the user's intent is ambiguous (e.g., "audit the skills"), default to all-skills mode without asking.

## Evaluation Categories

| # | Category | What It Checks |
|---|----------|---------------|
| 1 | Specification Compliance | Frontmatter fields, naming, description quality, body size |
| 2 | Instruction Quality | Structure, examples, edge cases, clarity |
| 3 | Tool & Integration Design | `allowed-tools` accuracy, model choice, subagent usage |
| 4 | Context Efficiency | Progressive disclosure, token budget, reference usage |
| 5 | Safety & Robustness | Mutation gates, error handling, dependency docs |
| 6 | Formatting & Syntax | YAML validity, markdown consistency, code blocks |
| 7 | Codex Integration | `agents/openai.yaml`, Codex compatibility, catalog exposure, wrapper sync (conditional) |

Full criteria and scoring anchors are in `references/evaluation-rubric.md`.

## Scoring Scale

| Score | Label | Meaning |
|-------|-------|---------|
| 5 | Excellent | No issues; could serve as a template |
| 4 | Good | Minor issues only; no action required |
| 3 | Attention | Moderate issues; should address in next cycle |
| 2 | Needs Work | Major issues; fix before publishing |
| 1 | Broken | Critical problems; unusable or misleading |

Overall score: equal-weight average of all applicable categories. Most skills use the 6 core categories. Skills that declare Codex support, ship `agents/openai.yaml`, or appear in `scripts/codex/catalog.json` use 7 categories with Codex Integration included. The minimum applicable category score is highlighted separately — a skill scoring 5 everywhere but 1 on Safety is not "4.3 overall, ship it."

Every score must cite specific lines, quotes, or file paths. A score without evidence is invalid.

## Workflow

### Step 1: Parse Arguments

Determine scope from arguments:

- **No arguments or "all"**: Audit all skills, excluding `skill-audit` itself
- **Skill name(s)**: Audit only the named skills (even `skill-audit` if explicitly named)

If the argument doesn't match a known skill name or keyword, output an error and list available skills.

### Step 2: Discover Skills

Run `scripts/list-skills.sh` from the repo root to discover skills:

- **All-skills mode**: `bash audit/skill-audit/scripts/list-skills.sh --exclude audit/skill-audit`
- **Specific skills**: Validate the named skills exist by checking each `<group>/<name>/SKILL.md`

The script finds `*/SKILL.md` relative to CWD, extracts directory names, and applies exclusions. It exits with code 1 if no skills are found.

If no skills match the scope, output a message and stop.

### Step 3: Detect Codex Contract Context

Read `references/codex-contracts.md` before auditing. It defines the repo-specific Codex contract and the source-of-truth files for Codex exposure.

Treat Codex Integration as **applicable** for a target skill when any of these are true:
- `compatibility` in `SKILL.md` includes `Codex`
- `agents/openai.yaml` exists in the skill directory
- The skill path appears in `scripts/codex/catalog.json`

If the repo does not contain `scripts/codex/catalog.json`, skip Codex wrapper checks and audit only any local `agents/openai.yaml` metadata present.

### Step 4: Run Repo-Level Codex Validation Once

If `scripts/validate-codex.sh` exists, run it from the repo root before spawning per-skill subagents:

```bash
bash scripts/validate-codex.sh
```

Capture both success and failure output.

- **Pass**: treat it as strong evidence that the generated wrapper layer matches the source contract at the time of the audit
- **Fail**: preserve the exact failing lines, map them to affected skills when paths are explicit, and include unmatched failures under cross-cutting Codex issues
- **Unavailable dependencies or execution failure**: continue with manual inspection and note reduced confidence for Codex Integration scoring

This skill is still report-only. Do **not** run `scripts/codex-packaging.sh sync-repo` during an audit.

### Step 5: Load Subagent Prompt

Read `references/subagent-prompt.md` — it contains the complete prompt template with a condensed rubric baked in. This is what gets injected into each subagent.

The full rubric (`references/evaluation-rubric.md`) and Codex contract reference (`references/codex-contracts.md`) remain detailed human-readable references for spec lookups but are not injected verbatim into subagents.

### Step 6: Spawn Subagents

Spawn **all** subagents in parallel when the host agent supports it. Use one lightweight read-only subagent per skill.

For each skill, take the prompt template from `references/subagent-prompt.md`, replace `{{SKILL_NAME}}` and `{{REPO_ROOT}}` with actual values, and pass the result as the subagent prompt.

**Claude Code path**:
- Use the `Task` tool
- Spawn all subagents in a single message
- `subagent_type`: `general-purpose`
- `model`: `haiku`
- `max_turns`: 10

**Codex path**:
- Use `spawn_agent`
- Prefer `agent_type: explorer` for read-only repository inspection
- Prefer a lightweight model such as `gpt-5.4-mini`
- Use `reasoning_effort: medium`
- Launch all skill audits first, then wait for results

**Fallback path**:
- If subagents are unavailable, audit sequentially in the main agent using the same rubric and output format

If a subagent fails or returns unparseable output, mark that skill as **"Audit Incomplete"** with the reason.

### Step 7: Collect and Validate Results

For each subagent result:
1. Parse the structured output (SKILL, SCORES, ISSUES, STRENGTHS, RECOMMENDATIONS)
2. Validate that each score has accompanying evidence
3. Reject scores without evidence — flag as incomplete
4. Treat `Codex Integration: N/A` as non-applicable and exclude it from the average
5. Calculate overall score (average of all numeric category scores, rounded to 1 decimal)
6. Identify minimum applicable category score
7. Merge in any repo-level `scripts/validate-codex.sh` failures that affect the skill

### Step 8: Generate Report

**All-skills mode — Summary table:**

```markdown
## Skill Audit Report

**Skills audited: N | Average: X.X / 5 | Lowest: <skill> (X.X)**

| Skill | Spec | Quality | Tools | Context | Safety | Format | Codex | Overall | Min |
|-------|------|---------|-------|---------|--------|--------|-------|---------|-----|
| name  | X    | X       | X     | X       | X      | X      | X/-   | X.X     | X   |
```

Sort table by overall score (ascending — worst first).

**Cross-cutting issues** (if patterns emerge across multiple skills):

```markdown
### Cross-Cutting Issues
1. Issue description (affects N skills)
```

Use this section for repo-level Codex validation failures that affect multiple skills or generated wrapper artifacts rather than a single skill.

**Top recommendations** (most impactful across all skills):

```markdown
### Top Recommendations
1. Actionable recommendation
```

**Per-skill details** — include full breakdown for:
- All skills in single-skill mode
- Skills scoring below 4.0 overall OR below 3 in any category (in all-skills mode)

**Per-skill breakdown format:**

```markdown
#### <skill-name> — X.X / 5

| Category | Score | Evidence |
|----------|-------|----------|
| Specification Compliance | X | ... |
| Instruction Quality | X | ... |
| Tool & Integration Design | X | ... |
| Context Efficiency | X | ... |
| Safety & Robustness | X | ... |
| Formatting & Syntax | X | ... |
| Codex Integration | X or N/A | ... |

**Issues:**
1. [Category] Description — location

**Strengths:**
1. Description

**Recommendations:**
1. Description
```

## Edge Cases

- **Empty skill directory**: Score 1 on Specification Compliance, note missing SKILL.md
- **Skill with only SKILL.md**: Valid — not all skills need scripts/references
- **Very large SKILL.md (>500 lines)**: Flag in Context Efficiency, still evaluate fully
- **Binary files in assets/**: Skip binary files when computing content, still check for references
- **Subagent timeout/failure**: Mark as "Audit Incomplete", continue with other skills
- **Codex contract files absent**: Skip wrapper-layer checks; score Codex Integration only from local metadata if applicable
- **`scripts/validate-codex.sh` fails because `jq` or another dependency is missing**: Continue with manual inspection and say Codex confidence is reduced
- **Generated wrapper layer appears stale**: Report it as a contract issue; do not regenerate files during the audit
- **No skills match scope**: Output "No skills to audit" and stop

## Rules

- **Parallel when possible**: Spawn all subagents together when the host supports it
- **Evidence required**: Never accept a score without cited evidence
- **Self-exclusion**: Exclude `skill-audit` in all-skills mode; allow explicit audit via name
- **No fixes**: Report only — do not modify any skill files
- **No generated-file edits**: Audit generated Codex wrapper outputs, but treat `scripts/codex/catalog.json` and source skills as the editable contract
- **Agent-specific fallbacks**: Do not penalize Claude-only frontmatter extensions, but do flag multi-agent skills that require agent-specific tools without a fallback
- **Worst-first**: Sort and prioritize by lowest scores

## Keywords

skill audit, evaluate, quality, compliance, specification, score, rubric, review skills, codex ready, codex compatibility
