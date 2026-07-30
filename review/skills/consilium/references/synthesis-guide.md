# Synthesis Guide

Instructions for combining and evaluating findings from consilium reviewers. Core reviewers (Seneca, Codex) always run. Optional reviewers (Scrutator, Novator, Librarius, Censor) run on-demand based on review content.

## Handling Optional Subagent Absence

Not all 6 reviewers run every time — this is normal, not a failure. When synthesizing:
- Only reference reviewers that actually ran
- Adjust agreement thresholds proportionally: "majority of reviewers that ran" replaces fixed counts like "3+"
  - For 2 reviewers (core only): both must agree to upgrade severity
  - For 3 reviewers: 2 of 3
  - For 4+: standard majority (>50%)
- If only core reviewers ran, severity calibration relies on evidence strength rather than cross-reviewer agreement
- Do not speculate about what absent reviewers might have found

## Step 1: Deduplication

Merge findings that describe the same underlying issue. When merging:
- Use the clearest description from any reviewer
- Note all reviewers who flagged it (e.g., "Flagged by: Seneca, Codex")
- Keep the strongest evidence from each
- Use the highest severity assigned by any reviewer

## Step 2: Contradiction Resolution

When reviewers disagree:
- **Factual disagreements** (e.g., "API exists" vs "API doesn't exist"): side with the reviewer who provides verifiable evidence (URLs, docs). If both provide evidence, flag for user.
- **Severity disagreements**: use the higher severity if majority of reviewers that ran agree; otherwise use the middle value.
- **Scope disagreements** (e.g., "this is a problem" vs "this is out of scope"): you have the broader conversation context — use it to determine whether the finding is relevant.

## Step 3: Severity Calibration

Adjust severities based on cross-reviewer agreement:
- **Upgrade to Critical**: a Warning flagged by majority of reviewers that ran independently
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

## Step 6: Integrating Scrutator Findings

When Scrutator ran:
- The **State Table** is reference material — do not include it verbatim in the report
- **Transition Matrix Gaps** become standard findings with the gap as evidence
- **Deduplicate with Seneca**: if both flag the same state issue, prefer Scrutator's wording (it has more state-specific detail)
- **Severity conflicts with Seneca**: if Seneca and Scrutator disagree on severity for the same issue, use Scrutator's severity (its analysis is more systematic) but note both perspectives
- Significant state coverage gaps go in the optional `### State Coverage Gaps` section of the report

## Step 7: Integrating Novator Findings

When Novator ran:
- **Premise Check**: if it raises concerns, include them in the report preamble (before Critical findings)
- **Alternatives with "Stronger" verdict**: map to Warning or Critical severity findings
- **Alternatives with "Comparable" verdict**: map to Note severity
- **Alternatives with "Weaker" verdict**: mention only if they contain genuinely insightful trade-off analysis
- **Lock-in Risks**: map directly to standard severity findings
- **Seneca Assumptions overlap**: if Seneca's Assumptions section identifies concerns that Novator's Premise Check also raises, merge them in the report preamble
- Strong alternatives go in the optional `### Alternatives Considered` section of the report

## Step 8: Autonomous Decision Threshold

**Decide autonomously** (do not ask the user):
- Dismissing false positives
- Resolving severity disagreements
- Merging duplicate findings
- Dropping findings with insufficient evidence

**Flag for user attention** (present but don't block on):
- Genuine trade-off decisions where both sides have merit
- Findings that would require significant plan changes
- Critical-severity findings from majority of reviewers that ran

## Output Format

Present the synthesized report grouped by severity:

```markdown
## Consilium Review

**Reviewers**: Seneca, Codex + [optional subagents that ran]
**Findings**: N total (X critical, Y warnings, Z notes)
**Dismissed**: N false positives

<optional: Novator premise concerns as a brief paragraph here, if any>

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

(optional — include only when Novator found Stronger or notable Comparable alternatives)

1. **Decision**: what the proposal chose
   - Alternative: the proposed different approach
   - Verdict: Stronger|Comparable
   - Trade-offs: key differences

### State Coverage Gaps

(optional — include only when Scrutator found significant gaps)

1. **Gap title**
   - States involved: which states from Scrutator's analysis
   - Issue: what is missing
   - Impact: consequence

### Dismissed

(brief list with reasons)
```

If a reviewer failed or timed out, note it at the top:
```
**Note**: <Reviewer> did not complete — findings may be incomplete.
```
