# Synthesis Guide

Instructions for combining and evaluating findings from all 4 consilium reviewers (Seneca, Librarius, Censor, Codex).

## Step 1: Deduplication

Merge findings that describe the same underlying issue. When merging:
- Use the clearest description from any reviewer
- Note all reviewers who flagged it (e.g., "Flagged by: Seneca, Codex")
- Keep the strongest evidence from each
- Use the highest severity assigned by any reviewer

## Step 2: Contradiction Resolution

When reviewers disagree:
- **Factual disagreements** (e.g., "API exists" vs "API doesn't exist"): side with the reviewer who provides verifiable evidence (URLs, docs). If both provide evidence, flag for user.
- **Severity disagreements**: use the higher severity if 2+ reviewers agree; otherwise use the middle value.
- **Scope disagreements** (e.g., "this is a problem" vs "this is out of scope"): you have the broader conversation context — use it to determine whether the finding is relevant.

## Step 3: Severity Calibration

Adjust severities based on cross-reviewer agreement:
- **Upgrade to Critical**: a Warning flagged by 3+ reviewers independently
- **Maintain severity**: finding from 1-2 reviewers with strong evidence
- **Downgrade**: finding from 1 reviewer with weak or speculative evidence

## Step 4: False Positive Filter

Dismiss findings that:
- Misunderstand the scope or constraints of the proposal (you know the full context, reviewers may not)
- Flag intentional design decisions that were already discussed and accepted
- Apply generic advice that doesn't fit this specific situation
- Reference code or APIs that don't exist in this project

When dismissing, briefly note why (e.g., "Dismissed: intentional trade-off discussed in conversation").

## Step 5: Evidence Requirement

Every finding in the final report must have:
- **What**: clear description of the issue
- **Where**: specific location (quote, section, file, line)
- **Why**: which principle or fact makes this a problem
- **Who**: which reviewer(s) flagged it

Findings missing any of these are incomplete — either fill in the gaps from your broader context or drop them.

## Step 6: Autonomous Decision Threshold

**Decide autonomously** (do not ask the user):
- Dismissing false positives
- Resolving severity disagreements
- Merging duplicate findings
- Dropping findings with insufficient evidence

**Flag for user attention** (present but don't block on):
- Genuine trade-off decisions where both sides have merit
- Findings that would require significant plan changes
- Critical-severity findings from 2+ reviewers

## Output Format

Present the synthesized report grouped by severity:

```markdown
## Consilium Review

**Reviewers**: Seneca, Librarius, Censor, Codex
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

(brief list with reasons)
```

If a reviewer failed or timed out, note it at the top:
```
**Note**: <Reviewer> did not complete — findings may be incomplete.
```
