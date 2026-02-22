# Brainstorm Synthesis Guide

Instructions for combining Novator's Phase 1 proposals with Phase 2 critic feedback into a final brainstorm recommendation. This guide is the brainstorm-mode equivalent of `synthesis-guide.md`.

## Handling Reviewer Absence

Not all Phase 2 reviewers run every time — this is normal. When synthesizing:
- Only reference reviewers that actually ran
- Adjust agreement thresholds proportionally (same rules as review mode)
- Do not speculate about what absent reviewers might have found

## Step 1: Map Findings to Approaches

Each Phase 2 critic finding maps to one of:
- **Specific approach** — the finding targets Approach 1, 2, or 3 specifically
- **Cross-cutting** — the finding applies to all approaches (e.g., a constraint all approaches miss)
- **Problem framing** — the finding challenges the problem definition itself

Tag every finding before proceeding. If a finding is ambiguous, use your broader conversation context to assign it.

## Step 2: Score Approaches

For each approach, tally findings by severity:

```
Approach N: <name>
- Critical: X
- Warning: Y
- Note: Z
- Cross-cutting issues that apply: list
```

A single Critical finding does not automatically disqualify an approach — assess whether the risk is mitigable.

## Step 3: Refine Recommendation

Compare Novator's original recommendation against the Phase 2 evidence:

- **Confirm**: critic feedback supports the recommendation or raises only minor issues → keep it, incorporate mitigations
- **Amend**: critics found significant but addressable issues → keep the recommendation but modify it to address the findings
- **Switch**: critics found Critical issues that are unmitigable AND another approach fares better → switch recommendation with clear reasoning

State your decision and one-line reasoning.

## Step 4: Synthesize Mitigations

For each risk or finding on the recommended approach:
1. Identify the specific concern
2. Propose a concrete mitigation (not "be careful" — an actual action or design change)
3. Note if the mitigation was suggested by a reviewer or is your own synthesis

Skip mitigations for Notes unless they're trivially actionable.

## Step 5: Compile Non-Recommended Approaches

For each approach NOT recommended:
- One-line summary of why it was not chosen
- Under what circumstances it would become the better choice
- Any valuable ideas from it worth incorporating into the recommended approach

## Autonomous Decision Threshold

**Decide autonomously** (do not ask the user):
- Dismissing false positives from Phase 2 reviewers
- Resolving disagreements between critics
- Merging duplicate findings across reviewers
- Confirming or amending Novator's recommendation when evidence is clear

**Flag for user attention** (present but don't block on):
- Genuine trade-off decisions where approaches are close in quality
- Critical findings that would fundamentally change the recommendation
- Unresolved disagreements where both sides have strong evidence

## Output Format

```markdown
## Consilium Brainstorm

**Problem**: <one-line summary>
**Reviewers**: Novator (lead) + [Phase 2 reviewers that ran]
**Approaches Evaluated**: N
**Recommendation**: Approach N — <name>

### Recommended Approach

<refined description incorporating critic feedback and mitigations>

**Key Trade-offs**:
- <strength vs weakness summaries>

**Risks Identified**:
1. <risk> — Mitigation: <action>

**Mitigations**:
- <concrete changes to the approach based on critic feedback>

### Other Approaches Considered

#### Approach N: <Name>
- **Summary**: what it does
- **Why not recommended**: one-line reason
- **When it would be better**: changed circumstances that favor this approach
- **Worth borrowing**: any ideas from this approach worth incorporating (if any)

### Open Questions

<unresolved disagreements between critics, genuine trade-offs requiring user input>

### Dismissed Concerns

<brief list of false positives or irrelevant findings with reasons>
```

If a reviewer failed or timed out, note it at the top:
```
**Note**: <Reviewer> did not complete — critique coverage may be incomplete.
```

If all Phase 2 reviewers failed, present Novator's raw output with a note:
```
**Note**: All Phase 2 reviewers failed. The following is Novator's unvalidated proposal.
```
