---
name: skill-audit
description: >
  Audit Agent Skills for quality, compliance, and best practices. Evaluates skills
  against the Agent Skills specification across 6 categories: Specification Compliance,
  Instruction Quality, Tool & Integration Design, Context Efficiency, Safety & Robustness,
  and Formatting & Syntax. Produces scored reports with evidence-backed findings.
  Use when the user asks to audit, evaluate, review, or check skill quality.
license: MIT
compatibility: Claude Code
allowed-tools: Read Glob Grep Task Bash(bash:audit/skill-audit/*)
user-invocable: true
arguments: "skills"
argument-hint: "[all or skill names]"
metadata:
  author: edloidas
---

# Skill Audit

## Purpose

Systematically evaluate skills against the Agent Skills specification and AI instruction best practices. Spawns parallel subagents (one per skill) and aggregates results into a scored report.

## When to Use This Skill

Use when the user asks to:
- "Audit skills" or "audit the skills"
- "Evaluate skill quality"
- "Check skills against the spec"
- "Review skill compliance"
- "Score skill X"

Trigger phrases: "skill audit", "audit skills", "evaluate skills", "skill quality", "skill review", "skill score"

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

Full criteria and scoring anchors are in `references/evaluation-rubric.md`.

## Scoring Scale

| Score | Label | Meaning |
|-------|-------|---------|
| 5 | Excellent | No issues; could serve as a template |
| 4 | Good | Minor issues only; no action required |
| 3 | Attention | Moderate issues; should address in next cycle |
| 2 | Needs Work | Major issues; fix before publishing |
| 1 | Broken | Critical problems; unusable or misleading |

Overall score: equal-weight average of all 6 categories. The minimum category score is highlighted separately — a skill scoring 5 everywhere but 1 on Safety is not "4.3 overall, ship it."

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

### Step 3: Load Subagent Prompt

Read `references/subagent-prompt.md` — it contains the complete prompt template with a condensed rubric baked in. This is what gets injected into each subagent.

The full rubric (`references/evaluation-rubric.md`) remains as a detailed human-readable reference for spec lookups but is not injected into subagents.

### Step 4: Spawn Subagents

Spawn **all** subagents in a **single message** using the Task tool so they execute in parallel. Use one `haiku` subagent per skill.

For each skill, take the prompt template from `references/subagent-prompt.md`, replace `{{SKILL_NAME}}` and `{{REPO_ROOT}}` with actual values, and pass the result as the subagent prompt.

**Subagent configuration** (also documented in the reference file):
- `subagent_type`: `general-purpose`
- `model`: `haiku`
- `max_turns`: 10

If a subagent fails or returns unparseable output, mark that skill as **"Audit Incomplete"** with the reason.

### Step 5: Collect and Validate Results

For each subagent result:
1. Parse the structured output (SKILL, SCORES, ISSUES, STRENGTHS, RECOMMENDATIONS)
2. Validate that each score has accompanying evidence
3. Reject scores without evidence — flag as incomplete
4. Calculate overall score (average of 6 category scores, rounded to 1 decimal)
5. Identify minimum category score

### Step 6: Generate Report

**All-skills mode — Summary table:**

```markdown
## Skill Audit Report

**Skills audited: N | Average: X.X / 5 | Lowest: <skill> (X.X)**

| Skill | Spec | Quality | Tools | Context | Safety | Format | Overall | Min |
|-------|------|---------|-------|---------|--------|--------|---------|-----|
| name  | X    | X       | X     | X       | X      | X      | X.X     | X   |
```

Sort table by overall score (ascending — worst first).

**Cross-cutting issues** (if patterns emerge across multiple skills):

```markdown
### Cross-Cutting Issues
1. Issue description (affects N skills)
```

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
- **No skills match scope**: Output "No skills to audit" and stop

## Rules

- **Parallel execution**: Always spawn all subagents in a single message
- **Evidence required**: Never accept a score without cited evidence
- **Self-exclusion**: Exclude `skill-audit` in all-skills mode; allow explicit audit via name
- **No fixes**: Report only — do not modify any skill files
- **Worst-first**: Sort and prioritize by lowest scores

## Keywords

skill audit, evaluate, quality, compliance, specification, score, rubric, review skills
