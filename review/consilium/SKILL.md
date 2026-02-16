---
name: consilium
description: >
  Critical review board for plans, proposals, and research findings. Deploys 4 parallel
  subagents (Codex, Seneca, Librarius, Censor) to stress-test technical decisions, verify
  library APIs, check best practices, and find logical flaws. Use when the user asks to
  "think hard", "ultrathink", perform critical review, validate a plan, or before committing
  to a complex technical decision. Also triggers on large-scope tasks and PRD reviews.
  Autonomous — runs without user interaction, presents combined findings.
license: MIT
compatibility: Claude Code
allowed-tools: Read Write Glob Grep Task Bash(bash:review/consilium/*) Bash(codex:*) Bash(cat:*) Bash(rm:*)
user-invocable: true
arguments: "optional focus area or empty for full review"
argument-hint: "[focus-area]"
metadata:
  author: edloidas
---

# Consilium — Critical Review Board

## Purpose

Deploy 4 independent reviewers to stress-test a plan, proposal, or research finding from different angles. The reviewers run in parallel, then you synthesize their findings using your broader conversation context. The result is a severity-grouped report with evidence-backed findings.

This is autonomous — run all steps without user interaction. Present the final synthesized report when done.

## When to Use

**Explicit triggers:**
- User says "think hard", "ultrathink", "critical review", "stress-test this", "validate this plan"
- User asks to review a PRD, architecture proposal, or technical decision
- `/consilium` invocation

**Auto-invocation criteria:**
- Before committing to a complex multi-system architectural decision
- When a plan has high blast radius (affects many files, services, or users)
- When the user seems uncertain about a technical approach

**Focus areas** (optional `$ARGUMENTS`):
- `logic` — run only Seneca and Codex
- `libraries` — run only Librarius
- `practices` — run only Censor
- Empty or `all` — run all 4 reviewers (default)

## Subagent Roles

| Reviewer | Role | Type | Model | Max Turns |
|----------|------|------|-------|-----------|
| Seneca | Critical logic analyst — contradictions, assumptions, edge cases | Task (`general-purpose`) | `opus` | 8 |
| Librarius | Library/API verification — versions, signatures, deprecations | Task (`general-purpose`) | `sonnet` | 10 |
| Censor | Best practices reviewer — anti-patterns, SOLID, security | Task (`general-purpose`) | `sonnet` | 8 |
| Codex | Independent reviewer — no conversation context, fresh perspective | Bash script (`codex exec`) | codex default | N/A |

## Workflow

### Step 1: Identify Review Target

Determine what to review from the conversation:
- A plan file (e.g., written to `/tmp/plan.md` or discussed in conversation)
- The most recent proposal or architectural decision
- Research findings or a PRD

Extract the content into a single text block. If the target is unclear, use the last substantive proposal from the conversation.

### Step 2: Prepare Context

1. Write the review content to `/tmp/consilium-${CLAUDE_SESSION_ID}-context.md` with a header:
   ```
   # Consilium Review Context
   # Source: <what this is — plan, proposal, research>
   # Timestamp: <ISO 8601>

   <content>
   ```
2. This file is used by the Codex script and as the source for Task prompts.

### Step 3: Load Prompts and Launch Reviewers

Read the prompt templates from `references/`:
- `review/consilium/references/seneca-prompt.md`
- `review/consilium/references/librarius-prompt.md`
- `review/consilium/references/censor-prompt.md`

For each Task-based reviewer, replace `{{CONTEXT}}` in the prompt template with the actual review content.

Launch **all applicable reviewers in a single message** (parallel execution):

**Codex** — via Bash:
```
bash review/consilium/scripts/run-codex.sh /tmp/consilium-${CLAUDE_SESSION_ID}-context.md /tmp/consilium-${CLAUDE_SESSION_ID}-codex.txt
```
Run in background so it doesn't block the other subagents.

**Seneca** — via Task:
- `subagent_type`: `general-purpose`
- `model`: `opus`
- `max_turns`: 8
- `prompt`: contents of seneca-prompt.md with `{{CONTEXT}}` replaced

**Librarius** — via Task:
- `subagent_type`: `general-purpose`
- `model`: `sonnet`
- `max_turns`: 10
- `prompt`: contents of librarius-prompt.md with `{{CONTEXT}}` replaced
- This reviewer uses WebSearch and Context7 tools to verify claims

**Censor** — via Task:
- `subagent_type`: `general-purpose`
- `model`: `sonnet`
- `max_turns`: 8
- `prompt`: contents of censor-prompt.md with `{{CONTEXT}}` replaced

If focus area narrows the scope, only launch the relevant reviewers.

### Step 4: Collect Results

1. Read Codex output from `/tmp/consilium-${CLAUDE_SESSION_ID}-codex.txt`
2. Parse Task results from the 3 subagent responses
3. If any reviewer failed or timed out, note it — do not block on it

### Step 5: Synthesize Report

Read `review/consilium/references/synthesis-guide.md` and follow it exactly:

1. **Deduplicate** — merge identical findings across reviewers
2. **Resolve contradictions** — use your broader conversation context
3. **Calibrate severity** — upgrade multi-reviewer findings, downgrade weak ones
4. **Filter false positives** — dismiss findings that misunderstand scope or context
5. **Verify evidence** — every finding needs what/where/why/who
6. **Apply autonomous threshold** — decide what to resolve vs flag for user

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

**Reviewers**: <list of reviewers that ran>
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

### Dismissed

(brief list with reasons, if any)
```

## Edge Cases

- **Codex not installed**: script writes skip message to output file — proceed with 3 reviewers
- **Codex timeout (120s)**: script writes timeout message — proceed with 3 reviewers
- **Subagent failure**: note in report header, continue with available results
- **Empty context**: if no review target can be identified, tell the user and stop
- **No findings**: if all reviewers return "No findings", report that — it's a valid outcome
- **Focus area specified**: only launch relevant reviewers, adjust report header accordingly

## Rules

- **Parallel execution**: always launch all reviewers in a single message
- **Autonomous**: do not ask the user questions during the review — resolve ambiguity yourself
- **Evidence required**: no finding survives without specific evidence
- **Clean up**: always remove session-specific `/tmp/consilium-${CLAUDE_SESSION_ID}-*` files when done
- **No modifications**: this is review only — never modify the reviewed content
- **Honest synthesis**: disagree with reviewers when your broader context warrants it

## Keywords

consilium, critical review, stress-test, validate plan, think hard, ultrathink, review board, second opinion, devil's advocate, sanity check, PRD review, architecture review
