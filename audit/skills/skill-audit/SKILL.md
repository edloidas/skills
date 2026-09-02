---
name: skill-audit
description: >
  Audit Agent Skills for what no validator can decide: whether a description will ever fire,
  whether the instructions are followable, whether the body earns its token cost, whether
  `compatibility` matches what the body requires, and whether mutations are gated. Runs the
  repo's structural validators first, scores six judgment categories with cited evidence, and
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

Decide whether a skill is fit to ship. Reports only: it reads skills, runs read-only checks,
and prints a verdict — the working tree is byte-identical afterwards. Structure is not the
question, since scripts answer that faster and more reliably. This skill owns the six
questions a script cannot answer:

1. Will the description ever fire, and does it fire on the right situations?
2. Can an agent follow the instructions to the end without guessing?
3. Does the body earn the tokens it costs in every session?
4. Does `compatibility` match what the body actually requires?
5. Can this skill damage something without being told to?
6. Does the body stay in its own layer, or carry lines the host or `CLAUDE.md` owns?

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
| `scripts/skill-metrics.mjs` | Body size and token estimate, largest inline block, duplicate sentence pairs, worked-output examples, longest prose run, unquantified dispatch lines, inline fallback length, named-output lines per section, unreachable bundled files, nested reference chains, untagged fences, heading skips, host-mechanism hits, `AskUserQuestion` fallback wording, cross-skill discovery overlap | Advisory measurements |
| This skill | The six judgment questions above | Scored 1–5 |

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

Close the step with one line: `Scope: 6 skills (changed), 1 removed`.

### Step 2: Run the structural gate

Run both validators from the repo root, once, before auditing anything:

```bash
bash .github/scripts/validate-skills.sh
bash scripts/validate-codex.sh
```

Reproduce the `::error::` lines unedited in the report's fenced block; if you truncate one,
say where you cut. Every error naming a skill in scope belongs in that skill's report; the
rest go under cross-cutting issues. A validator that cannot run — missing `jq`, missing
file — is recorded as such, not treated as a pass.

Never run `scripts/skills-packaging.sh sync-repo` during an audit; a stale generated layer
is a finding, not something to quietly fix.

Close the step with one line: `Structural gate: 2 errors across 2 skills`.

### Step 3: Collect measurements

```bash
node <skill-dir>/scripts/skill-metrics.mjs --only <skill-path> [<skill-path> ...]
```

Omit `--only` for all-skills mode. The discovery-overlap section at the end compares every
skill in the run against every other, so run it across the whole set at least once when
scoring Discovery — a pair only shows up when both halves are present.

### Step 4: Score judgment, in waves

Read `references/subagent-prompt.md` and dispatch one cheap, read-only worker per skill, in
waves of at most 8 workers. Replace `{{SKILL_PATH}}`, `{{REPO_ROOT}}`, and `{{METRICS}}`
(that skill's block from Step 3) in the template. Each worker reads the skill's files and
returns the structured block the template specifies.

Launch a whole wave before waiting on any result, and let every worker in it return before
launching the next. Every skill in scope gets a worker — 39 skills is 5 waves, not a smaller
sample. Parsed blocks accumulate across waves, a skill already scored is never re-scored,
and a wave that ends with failures still hands its good blocks forward. Close each wave with
one line: `Wave 2/5 audited: 8 skills, 3 FAIL`.

If the host has no facility for spawning workers, run the same prompt inline, one skill at a
time, in the same groups of 8, and print the same wave line. If a worker fails or returns
unparseable output, mark that skill **Audit Incomplete** with the reason and continue; it
counts in its wave's total and appears in the summary.

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

Overall is the mean of the six categories to one decimal. Report the minimum next to it —
a skill at 4.4 overall with a 2 in Safety is a FAIL, and the average must never hide that.

## Report Format

### Summary

All-skills and `changed` mode open with a summary, sorted worst first. Headers and columns
are fixed. The example below is filled rather than a second template; the skills in it are
invented, the shape is not.

```markdown
## Skill Audit — changed (3 skills)

**Audited: 3 | Average: 4.2 / 5 | Failing: 1**

| Skill | Discovery | Instructions | Context | Portability | Safety | Layer | Overall | Min | Verdict |
|-------|-----------|--------------|---------|-------------|--------|-------|---------|-----|---------|
| assist/skills/recap | 4 | 3 | 4 | 5 | 5 | 2 | 3.8 | 2 | FAIL |
| build/skills/stage | 4 | 4 | 3 | 5 | 4 | 4 | 4.0 | 3 | PASS WITH NOTES |
| write/skills/changelog | 5 | 5 | 4 | 5 | 5 | 4 | 4.7 | 4 | PASS |
```

Then, when they apply:

```markdown
### Structural Errors
1. `::error::Skill 'recap': description is 1104 chars; the limit is 1024` — assist/skills/recap

### Checks Not Run
1. `scripts/validate-codex.sh` — `jq` not installed. Catalog membership and the host-subset
   rule are unverified for all three skills.

### Cross-Cutting Issues
1. "Reports, never edits" is stated three times in each of two bodies (affects 2 skills)

### Top Recommendations
1. Delete the trailing `## Rules` block in `assist/skills/recap` — all six lines restate
   earlier sections, and the two host-layer ones should not be in a body at all.
```

Name every validator, metrics run, and optional check that did not run under **Checks Not
Run**, with the reason. A check nobody names reads as a check that passed.

### Per-skill breakdown

Include one for every named skill in single-skill mode, and in the other modes for any skill
that is not a clean PASS:

```markdown
#### assist/skills/recap — 3.8 / 5 — FAIL

| Category | Score | Evidence |
|----------|-------|----------|
| Discovery | 4 | `when_to_use` carries typed trigger phrases; "concisely" at :11 is calibration |
| Instruction Quality | 3 | No worked example of the summary the skill promises at :44 |
| Context Efficiency | 4 | 71 lines, proportionate; `## Rules` at :64 duplicates :12–:20 |
| Portability & Integration | 5 | Four hosts declared, no host-specific mechanism in the body |
| Safety & Robustness | 5 | Reads the transcript and writes nothing; `allowed-tools` is `Read` |
| Layer Discipline | 2 | :31 "be thorough and double-check the result"; :64 "deliver what was asked" |

**Issues:**
1. [Layer] "Be thorough and double-check the result" — SKILL.md:31. Host-layer calibration;
   the task reads the same without it.
2. [Instructions] The output contract is described at :44 and never shown.

**Strengths:**
1. Length is stated as a check, not an adjective — "shorter than the original, always" :26.

**Recommendations:**
1. Replace :31 with the stop sentence the last phase is missing.
```

Then stop. The audit ends with the report: do not edit a skill, do not regenerate the
packaging layer, and do not re-open a skill already scored.

## Edge Cases

- **Skill with only `SKILL.md`** — valid. Bundled directories are optional.
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
- **Auditing a repo with no `CLAUDE.md`** — Layer Discipline still applies. The host layer
  exists everywhere, and a skill installed into a foreign repo is exactly the case the
  category is about.
- **Skills sharing a discovery neighbourhood** — a high overlap score is evidence for a
  Discovery finding against *both* skills, not just the newer one.
