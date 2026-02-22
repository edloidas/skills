---
name: consilium
description: >
  Critical review board for plans, proposals, and research findings. Deploys up to 6 reviewers
  (2 core + 4 on-demand) including Seneca, Codex, Scrutator, Novator, Librarius, and Censor.
  The orchestrator selects which optional subagents to launch based on review content.
  Use when the user asks to "think hard", "ultrathink", perform critical review, validate a plan,
  or before committing to a complex technical decision. Also triggers on large-scope tasks and
  PRD reviews. Also operates in brainstorm mode for problem exploration — generates and critiques
  solution approaches. Autonomous — runs without user interaction, presents combined findings.
license: MIT
compatibility: Claude Code
allowed-tools: Read Write(/tmp/consilium-*) Edit(/tmp/consilium-*) Read(/tmp/consilium-*) Glob Grep Task Bash(bash:review/consilium/*) Bash(codex:*) Bash(cat:*) Bash(rm:*)
user-invocable: true
arguments: "focus-area brainstorm"
argument-hint: "[focus area, brainstorm, or empty]"
metadata:
  author: edloidas
---

# Consilium — Critical Review Board

## Purpose

Deploy up to 6 reviewers (2 core + up to 4 on-demand) to stress-test a plan, proposal, or research finding from different angles. Core reviewers (Seneca, Codex) always run. The orchestrator selects which optional reviewers to launch based on the review content. Findings are synthesized into a severity-grouped report with evidence-backed findings.

This is autonomous — run all steps without user interaction. Present the final synthesized report when done.

## When to Use

**Explicit triggers:**
- User says "think hard", "ultrathink", "critical review", "stress-test this", "validate this plan"
- User asks to review a PRD, architecture proposal, or technical decision
- `/consilium` invocation

**Brainstorm triggers:**
- User asks "how should we...", "what's the best approach for...", "explore options for..."
- Problem statement without a proposed solution
- `/consilium brainstorm` invocation

**Auto-invocation criteria:**
- Before committing to a complex multi-system architectural decision
- When a plan has high blast radius (affects many files, services, or users)
- When the user seems uncertain about a technical approach

**Focus areas** (optional `$ARGUMENTS`):

| Focus | Subagents | Use case |
|-------|-----------|----------|
| _(default)_ | Seneca + Codex + auto-selected | Orchestrator decides which optional reviewers to add |
| `all` | All 6 | Full board review |
| `logic` | Seneca + Codex + Scrutator | Deep state and logic analysis |
| `libraries` | Seneca + Codex + Librarius | Dependency and API verification |
| `practices` | Seneca + Codex + Censor | Best practices audit |
| `alternatives` | Seneca + Codex + Novator | Design space exploration |
| `deep` | Seneca + Codex + Scrutator + Novator | Both new specialized reviewers |
| `brainstorm` | Novator (Phase 1 lead) → Seneca + Codex + auto-selected (Phase 2) | Two-phase: generate approaches then critique them |

## Subagent Roles

### Core (always run)

| Reviewer | Role | Type | Model | Max Turns |
|----------|------|------|-------|-----------|
| Seneca | Critical logic analyst — contradictions, assumptions, edge cases | Task (`general-purpose`) | `opus` | 8 |
| Codex | Independent reviewer — no conversation context, fresh perspective | Bash script (`codex exec`) | codex default | N/A |

### Optional (on-demand)

| Reviewer | Role | Type | Model | Max Turns |
|----------|------|------|-------|-----------|
| Scrutator | Exhaustive state/logic analyzer — all states, transitions, race conditions | Task (`general-purpose`) | `opus` | 14 |
| Novator | Devil's advocate — alternative approaches, design space exploration | Task (`general-purpose`) | `opus` | 10 |
| Librarius | Library/API verification — versions, signatures, deprecations | Task (`general-purpose`) | `sonnet` | 10 |
| Censor | Best practices reviewer — anti-patterns, SOLID, security | Task (`general-purpose`) | `sonnet` | 8 |

## Workflow

### Step 1: Identify Review Target

Determine what to review from the conversation:
- A plan file (e.g., written to `/tmp/plan.md` or discussed in conversation)
- The most recent proposal or architectural decision
- Research findings or a PRD

Extract the content into a single text block. If the target is unclear, use the last substantive proposal from the conversation.

### Step 1.5: Detect Mode

Determine whether to run in **review mode** or **brainstorm mode**:

1. If `$ARGUMENTS` is `brainstorm` → **brainstorm mode**
2. If `$ARGUMENTS` is any other focus keyword from the table → **review mode**
3. If `$ARGUMENTS` is empty → **auto-detect**:
   - Brainstorm signals: interrogative framing ("how should we...", "what's the best way to..."), no concrete proposal structure, exploratory language ("explore", "options", "approaches")
   - Default to **review mode** when uncertain

State detected mode and one-line reasoning before proceeding.

If brainstorm mode → skip to **Brainstorm Workflow** section below. Otherwise continue with Step 2.

### Step 2: Prepare Context

1. Write the review content to `/tmp/consilium-${CLAUDE_SESSION_ID}-context.md` with a header:
   ```
   # Consilium Review Context
   # Source: <what this is — plan, proposal, research>
   # Timestamp: <ISO 8601>

   <content>
   ```
2. This file is used by the Codex script and as the source for Task prompts.

### Step 2.5: Select Optional Subagents

If a focus area is specified, use the focus area table above to determine which subagents to launch. Otherwise, scan the review content and select optional subagents using this decision table:

| Subagent | Launch when | Skip when |
|----------|------------|-----------|
| **Scrutator** | State machines, async flows, concurrent ops, retry/recovery, multi-step workflows, loading/error/success states, event handlers | Pure data transforms, static config, docs-only, simple CRUD |
| **Novator** | Major architecture decisions, new system design, high blast radius, irreversible choices, "X vs Y" discussions | Bug fixes, minor refactors, well-established patterns, incremental changes |
| **Librarius** | Specific library names, version numbers, API calls, dependency changes, migration guides | No external deps, pure algorithm/logic, internal-only code |
| **Censor** | New abstractions, class hierarchies, design patterns, security-sensitive code, public API design | Bug fixes with minimal structural change, config changes, one-off scripts |

State your selections and one-line reasoning for each decision (include/skip) before proceeding.

Minimum: 2 (core only). Maximum: 6 (all). Typical: 3–4.

### Step 3: Load Prompts and Launch Reviewers

Read the prompt templates from `references/` for all selected reviewers:
- `review/consilium/references/seneca-prompt.md` (always)
- `review/consilium/references/scrutator-prompt.md` (if selected)
- `review/consilium/references/novator-prompt.md` (if selected)
- `review/consilium/references/librarius-prompt.md` (if selected)
- `review/consilium/references/censor-prompt.md` (if selected)

For each Task-based reviewer, replace `{{CONTEXT}}` in the prompt template with the actual review content.

Launch **all applicable reviewers in a single message** (parallel execution):

**Codex** (core) — via Bash:
```
bash review/consilium/scripts/run-codex.sh /tmp/consilium-${CLAUDE_SESSION_ID}-context.md /tmp/consilium-${CLAUDE_SESSION_ID}-codex.txt
```
Run in background so it doesn't block the other subagents.

**Seneca** (core) — via Task:
- `subagent_type`: `general-purpose`
- `model`: `opus`
- `max_turns`: 8
- `prompt`: contents of seneca-prompt.md with `{{CONTEXT}}` replaced

**Scrutator** (if selected) — via Task:
- `subagent_type`: `general-purpose`
- `model`: `opus`
- `max_turns`: 14
- `prompt`: contents of scrutator-prompt.md with `{{CONTEXT}}` replaced

**Novator** (if selected) — via Task:
- `subagent_type`: `general-purpose`
- `model`: `opus`
- `max_turns`: 10
- `prompt`: contents of novator-prompt.md with `{{CONTEXT}}` replaced

**Librarius** (if selected) — via Task:
- `subagent_type`: `general-purpose`
- `model`: `sonnet`
- `max_turns`: 10
- `prompt`: contents of librarius-prompt.md with `{{CONTEXT}}` replaced
- This reviewer uses WebSearch and Context7 tools to verify claims

**Censor** (if selected) — via Task:
- `subagent_type`: `general-purpose`
- `model`: `sonnet`
- `max_turns`: 8
- `prompt`: contents of censor-prompt.md with `{{CONTEXT}}` replaced

### Step 4: Collect Results

1. Read Codex output from `/tmp/consilium-${CLAUDE_SESSION_ID}-codex.txt`
2. Parse Task results from the subagent responses
3. If any reviewer failed or timed out, note it — do not block on it

### Step 5: Synthesize Report

Read `review/consilium/references/synthesis-guide.md` and follow it exactly:

1. **Deduplicate** — merge identical findings across reviewers
2. **Resolve contradictions** — use your broader conversation context
3. **Calibrate severity** — upgrade multi-reviewer findings, downgrade weak ones
4. **Filter false positives** — dismiss findings that misunderstand scope or context
5. **Verify evidence** — every finding needs what/where/why/who
6. **Integrate Scrutator** — state table as reference, transition gaps as findings (when Scrutator ran)
7. **Integrate Novator** — map verdicts to severities, premise check to preamble (when Novator ran)
8. **Apply autonomous threshold** — decide what to resolve vs flag for user

Note: Novator's output uses a different format (sections instead of numbered findings). The synthesis guide has specific instructions for mapping its output to the standard report format.

### Step 6: Autonomous Review

Before presenting the report, critically evaluate each finding against your broader context:
- You may dismiss findings that are wrong or irrelevant
- You may downgrade findings that are technically correct but practically insignificant
- You should upgrade findings that align with concerns you already had
- Note your reasoning for any overrides

### Step 7: Clean Up

Remove temporary files:
```
rm -f /tmp/consilium-${CLAUDE_SESSION_ID}-context.md /tmp/consilium-${CLAUDE_SESSION_ID}-codex.txt
```

## Output Format

Present the final report using the format from `references/synthesis-guide.md`:

```markdown
## Consilium Review

**Reviewers**: Seneca, Codex + [optional subagents that ran]
**Findings**: N total (X critical, Y warnings, Z notes)
**Dismissed**: N false positives

### Critical

1. **Finding title**
   - Issue: description
   - Evidence: quote or reference
   - Flagged by: reviewer names
   - Impact: consequence

### Warnings

(same format)

### Notes

(same format)

### Alternatives Considered

(optional — when Novator found strong alternatives)

### State Coverage Gaps

(optional — when Scrutator found significant gaps)

### Dismissed

(brief list with reasons, if any)
```

## Brainstorm Workflow

When brainstorm mode is detected, follow these steps instead of the standard review workflow (Steps 2–7).

### Step B1: Prepare Brainstorm Context

Write the problem description to `/tmp/consilium-${CLAUDE_SESSION_ID}-context.md`:
```
# Consilium Brainstorm Context
# Problem: <one-line summary>
# Timestamp: <ISO 8601>

<problem description extracted from conversation>
```

### Step B2: Phase 1 — Novator as Solution Architect

1. Read `review/consilium/references/novator-brainstorm-prompt.md`
2. Replace `{{CONTEXT}}` with the problem description
3. Launch a single Task:
   - `subagent_type`: `general-purpose`
   - `model`: `opus`
   - `max_turns`: 12
   - `prompt`: the prepared novator brainstorm prompt
4. **Wait for completion** — this is a blocking step. Phase 2 depends on Novator's output.

### Step B3: Prepare Phase 2 Context

Write `/tmp/consilium-${CLAUDE_SESSION_ID}-phase2-context.md`:
```
# Consilium Brainstorm — Phase 2 Critique Context
# Original Problem: <one-line summary>
# Timestamp: <ISO 8601>

## Original Problem
<problem description>

## Novator's Proposed Approaches
<Novator's full Phase 1 output>
```

Select Phase 2 reviewers using the existing decision table (Step 2.5). Apply it against **both** the original problem description and Novator's output — use the original problem for domain signals (what the problem involves), and Novator's output for structural signals (whether approaches involve state machines, library choices, etc.). This prevents selection from depending solely on Novator's word choices. Novator is excluded from Phase 2. State your selections and one-line reasoning.

### Step B4: Phase 2 — Critique Novator's Proposals

Launch all Phase 2 reviewers in a single message (parallel execution):

**Codex** (core) — via Bash:
```
bash review/consilium/scripts/run-codex.sh /tmp/consilium-${CLAUDE_SESSION_ID}-phase2-context.md /tmp/consilium-${CLAUDE_SESSION_ID}-codex.txt
```
Run in background.

**Seneca** (core) — via Task:
- `subagent_type`: `general-purpose`
- `model`: `opus`
- `max_turns`: 8
- `prompt`: **seneca-brainstorm-prompt.md** with `{{CONTEXT}}` replaced by Phase 2 context

**Scrutator** (if selected) — via Task:
- `subagent_type`: `general-purpose`
- `model`: `opus`
- `max_turns`: 14
- `prompt`: scrutator-prompt.md with `{{CONTEXT}}` replaced by Phase 2 context

**Censor** (if selected) — via Task:
- `subagent_type`: `general-purpose`
- `model`: `sonnet`
- `max_turns`: 8
- `prompt`: censor-prompt.md with `{{CONTEXT}}` replaced by Phase 2 context

**Librarius** (if selected) — via Task:
- `subagent_type`: `general-purpose`
- `model`: `sonnet`
- `max_turns`: 10
- `prompt`: librarius-prompt.md with `{{CONTEXT}}` replaced by Phase 2 context

Seneca uses its brainstorm-specific prompt (`seneca-brainstorm-prompt.md`) to evaluate approaches comparatively. All other reviewers use their standard prompts — the Phase 2 context file frames Novator's proposals as "the proposal to review."

### Step B5: Synthesize Brainstorm Report

1. Read Codex output from `/tmp/consilium-${CLAUDE_SESSION_ID}-codex.txt`
2. Parse Task results from Phase 2 subagent responses
3. Read `review/consilium/references/brainstorm-synthesis-guide.md` and follow it exactly

### Step B5.5: Autonomous Review

Before presenting the brainstorm report, critically evaluate each finding and the recommendation against your broader conversation context:
- You may dismiss Phase 2 findings that are wrong or irrelevant
- You may adjust the recommendation if your broader context warrants it
- You should flag findings that align with concerns you already had
- Note your reasoning for any overrides

### Step B6: Clean Up

Remove temporary files:
```
rm -f /tmp/consilium-${CLAUDE_SESSION_ID}-context.md /tmp/consilium-${CLAUDE_SESSION_ID}-phase2-context.md /tmp/consilium-${CLAUDE_SESSION_ID}-codex.txt
```

## Edge Cases

- **Codex not installed**: script writes skip message to output file — proceed with remaining reviewers
- **Codex timeout (300s default)**: script writes timeout message — proceed with remaining reviewers. Pass custom timeout as third argument to the script.
- **Subagent failure**: note in report header, continue with available results
- **Empty context**: if no review target can be identified, tell the user and stop
- **No findings**: if all reviewers return "No findings", report that — it's a valid outcome
- **Focus area specified**: launch only the reviewers for that focus, adjust report header
- **No optional subagents selected**: core-only review is valid — report still follows standard format
- **Scrutator finds no state**: if review content has no meaningful state, Scrutator returns early — this is fine
- **Novator finds no decisions to challenge**: Novator returns early — this is fine
- **Brainstorm with existing proposal**: if `brainstorm` is explicit but content is a finished plan, warn user but proceed — treat the plan as problem space
- **Novator fails in Phase 1**: cannot continue brainstorm — clean up temp files (`rm -f /tmp/consilium-${CLAUDE_SESSION_ID}-context.md`), report failure, suggest re-running or falling back to review mode
- **All Phase 2 fail**: present Novator's raw output with a note that critic validation was incomplete. Still run Step B6 cleanup.
- **Single generator**: Novator is the sole Phase 1 generator. If it misses an approach, Phase 2 critics cannot introduce fundamentally new alternatives. This is a known v1 limitation — re-run with different framing if the approaches feel narrow.
- **Auto-detection ambiguity**: default to review mode when uncertain

## Rules

- **Parallel execution**: always launch core + selected optional reviewers in a single message
- **Autonomous**: do not ask the user questions during the review — resolve ambiguity yourself
- **Evidence required**: no finding survives without specific evidence
- **Clean up**: always remove session-specific `/tmp/consilium-${CLAUDE_SESSION_ID}-*` files when done
- **No modifications**: this is review only — never modify the reviewed content
- **Honest synthesis**: disagree with reviewers when your broader conversation context warrants it

## Keywords

consilium, critical review, stress-test, validate plan, think hard, ultrathink, review board, second opinion, devil's advocate, sanity check, PRD review, architecture review, brainstorm, how to, explore approaches, solution design, what's the best way
