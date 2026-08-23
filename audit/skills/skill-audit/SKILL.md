---
name: skill-audit
description: >
  Audit Agent Skills for what no validator can decide: whether a description will ever fire,
  whether the instructions are followable, whether the body earns its token cost, whether
  `compatibility` matches what the body requires, and whether mutations are gated. Runs the
  repo's structural validators first, scores five judgment categories with cited evidence, and
  returns a PASS / FAIL verdict.
when_to_use: >
  Before committing any change that creates, edits, moves, renames, or deletes a skill
  directory — it is the acceptance gate for skill work. Also on "audit skills", "score this
  skill", "is this skill Codex-ready", "why does this skill never activate", or when reviewing
  a diff touching SKILL.md, references/, or agents/openai.yaml.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Read Glob Grep Task Bash(node:*) Bash(git diff:*) Bash(git status:*) Bash(git merge-base:*) Bash(bash:.github/scripts/validate-skills.sh) Bash(bash:scripts/validate-codex.sh)
argument-hint: "[changed | all | skill names]"
metadata:
  author: edloidas
---

# Skill Audit

## Purpose

Decide whether a skill is fit to ship. Structure is not the question — scripts answer that
faster and more reliably. This skill owns the five questions a script cannot answer:

1. Will the description ever fire, and does it fire on the right situations?
2. Can an agent follow the instructions to the end without guessing?
3. Does the body earn the tokens it costs in every session?
4. Does `compatibility` match what the body actually requires?
5. Can this skill damage something without being told to?

## When to Use This Skill

- Before committing a change to any skill directory — this is the acceptance gate
- "Audit skills", "score this skill", "check compliance with the spec"
- "Is this skill Codex-ready?"
- "Why does this skill never get invoked?"
- Reviewing a PR that touches `SKILL.md`, `references/`, or `agents/openai.yaml`

## Division of Labour

Anything mechanically checkable belongs to a script. Never re-derive by hand what one of
these already answers, and never score a skill down for something a script reports green.

| Owner | Answers | Failure mode |
| ----- | ------- | ------------ |
| `.github/scripts/validate-skills.sh` | Marketplace and plugin manifests; canonical `<group>/skills/<name>` real directory; required frontmatter; `name` matches directory and format; description ≤ 1024 and discovery entry ≤ 1536; `SKILL.md` referencing bundled files it does not ship | Hard, fails CI |
| `scripts/validate-codex.sh` | Codex catalog membership, `compatibility` ↔ catalog agreement, `agents/openai.yaml` presence, Codex ⊆ OpenCode ∩ Pi host subset rule | Hard, fails CI |
| `scripts/skill-metrics.mjs` | Body size and token estimate, largest inline block, unreachable bundled files, nested reference chains, untagged fences, heading skips, host-mechanism hits, `AskUserQuestion` fallback wording, cross-skill discovery overlap | Advisory measurements |
| This skill | The five judgment questions above | Scored 1–5 |

Requires Node (for `scripts/skill-metrics.mjs`) and `jq` (for the two repo validators).
When a validator is absent — auditing a repo that is not `edloidas/skills` — say so and
note reduced confidence rather than reimplementing it.

## Modes

| Invocation | Scope |
| ---------- | ----- |
| `/skill-audit` | Skills changed on this branch; falls back to all when nothing changed |
| `/skill-audit changed` | Skills changed on this branch only |
| `/skill-audit all` | Every skill, excluding `skill-audit` itself |
| `/skill-audit <name> [<name> ...]` | Named skills, including `skill-audit` when named |

## Workflow

### Step 1: Resolve scope

For `changed` mode, list skill directories touched by the branch, working tree included:

```bash
BASE=${BASE:-$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/HEAD)}
{ git diff --name-only "$(git merge-base HEAD "$BASE")"...HEAD; git status --porcelain | awk '{print $NF}'; } \
  | grep -oE '^[a-z]+/skills/[a-z0-9-]+' | sort -u
```

`BASE` defaults to the repository's default branch. Set it explicitly when the branch forked
from somewhere else — `BASE=epic-6` under an epic — or the scope picks up the whole epic.

A deleted skill directory appears here and cannot be audited — report it as removed and
move on. If the scope resolves to nothing, say "No skills to audit" and stop.

For named skills, resolve each argument against `<group>/skills/<name>/SKILL.md`. If one
does not resolve, list the available skill paths and stop rather than guessing.

### Step 2: Run the structural gate

Run both validators from the repo root, once, before auditing anything:

```bash
bash .github/scripts/validate-skills.sh
bash scripts/validate-codex.sh
```

Keep the exact `::error::` lines. Every error naming a skill in scope belongs in that
skill's report; the rest go under cross-cutting issues. A validator that cannot run —
missing `jq`, missing file — is recorded as such, not treated as a pass.

Report only. Never run `scripts/skills-packaging.sh sync-repo` during an audit; a stale
generated layer is a finding, not something to quietly fix.

### Step 3: Collect measurements

```bash
node <skill-dir>/scripts/skill-metrics.mjs --only <skill-path> [<skill-path> ...]
```

Omit `--only` for all-skills mode. The discovery-overlap section at the end compares every
skill in the run against every other, so run it across the whole set at least once when
scoring Discovery — a pair only shows up when both halves are present.

### Step 4: Score judgment, one skill at a time

Read `references/subagent-prompt.md` and dispatch one cheap, read-only worker per skill,
launching them all before waiting on any result. Replace `{{SKILL_PATH}}`, `{{REPO_ROOT}}`,
and `{{METRICS}}` (that skill's block from Step 3) in the template. Each worker reads the
skill's files and returns the structured block the template specifies.

If the host has no facility for spawning workers, run the same prompt inline, one skill at
a time. If a worker fails or returns unparseable output, mark that skill **Audit
Incomplete** with the reason and continue.

`references/evaluation-rubric.md` holds the full criteria and scoring anchors. It is the
reference for resolving a borderline score — it is not injected into workers, which carry a
condensed copy already.

### Step 5: Verdict

Reject any score that arrives without cited evidence and re-run that skill. Then per skill:

| Verdict | Bar |
| ------- | --- |
| **PASS** | No structural errors, and every category ≥ 4 |
| **PASS WITH NOTES** | No structural errors, and the lowest category is 3 |
| **FAIL** | Any structural error, or any category ≤ 2 |

Overall is the mean of the five categories to one decimal. Report the minimum next to it —
a skill at 4.4 overall with a 2 in Safety is a FAIL, and the average must never hide that.

## Report Format

All-skills and `changed` mode open with a summary, sorted worst first:

```markdown
## Skill Audit — <scope>

**Audited: N | Average: X.X / 5 | Failing: N**

| Skill | Discovery | Instructions | Context | Portability | Safety | Overall | Min | Verdict |
|-------|-----------|--------------|---------|-------------|--------|---------|-----|---------|
| path  | X         | X            | X       | X           | X      | X.X     | X   | PASS    |
```

Then, when they apply:

```markdown
### Structural Errors
1. `::error::` line verbatim — affected skill

### Cross-Cutting Issues
1. Description (affects N skills)

### Top Recommendations
1. Actionable recommendation
```

Include a full breakdown for every named skill in single-skill mode, and in the other
modes for any skill that is not a clean PASS:

```markdown
#### <group>/skills/<name> — X.X / 5 — <verdict>

| Category | Score | Evidence |
|----------|-------|----------|
| Discovery | X | ... |
| Instruction Quality | X | ... |
| Context Efficiency | X | ... |
| Portability & Integration | X | ... |
| Safety & Robustness | X | ... |

**Issues:**
1. [Category] Description — file:line or quote

**Strengths:**
1. Description

**Recommendations:**
1. Description
```

## Edge Cases

- **Skill with only `SKILL.md`** — valid. Bundled directories are optional.
- **Skill directory in scope but deleted on this branch** — report as removed, do not score.
- **Body over 500 lines** — a Context Efficiency finding, not a reason to stop reading it,
  unless the skill carries a budgeted allowance in `BODY_LINE_BUDGETS` in
  `.github/scripts/validate-skills.sh` and is inside it. That is a sanctioned size, already
  enforced mechanically; scoring it again would report the same finding forever.
- **Binary files under `assets/`** — count them, do not read them.
- **A validator cannot run** — record the reason and say confidence is reduced for whatever
  that validator covers. Do not substitute a guess for its verdict.
- **Generated wrapper layer looks stale** — a cross-cutting finding whose fix path is
  `scripts/codex/catalog.json` plus `scripts/skills-packaging.sh sync-repo`.
- **Auditing a repo with no Codex layer** — score Portability from `compatibility` and the
  body alone; there is no catalog contract to check.
- **Skills sharing a discovery neighbourhood** — a high overlap score is evidence for a
  Discovery finding against *both* skills, not just the newer one.

## Rules

- **Scripts first.** Run the validators and the metrics script before forming any opinion.
- **Evidence or nothing.** Every score cites a line, a quote, or a path.
- **Report only.** Never modify a skill, a manifest, or a generated tree during an audit.
- **Judgment only.** Do not score what the structural gate already covers; cite its result.
- **No fluent-nonsense credit.** A polished body that never activates still fails Discovery.
- **Worst first.** Sort by lowest score and lead with what fails.
