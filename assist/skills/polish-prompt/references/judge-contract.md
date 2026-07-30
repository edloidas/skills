# Judge Contract

Exact I/O schema for the judge subagent. The judge runs blind — it must not see prompts, strategies, or prior rounds.

## Invocation

- `subagent_type: general-purpose`
- One judge call per round (never split across agents — one head needs to compare them)
- Fresh subagent every round — no memory of prior rounds

## Input to the judge

Pass as a single prompt with this shape:

```
You are a blind judge evaluating the outputs of N candidate prompts applied to the same input.
You do not see the prompts. You do not know the strategies used. You only see the outputs.
Grade each output against the rubric and rank the top 2.

## Rubric

<list of 3–6 criteria, each scored 1–5 integer>

- criterion-1: <one-line description of what "good" looks like>
- criterion-2: ...
- ...

Tiebreaker criterion: <name one criterion that matters most for this task>

## Input the candidates were given

<the example input, verbatim>

## Outputs to grade

### A
<output from candidate labelled A>

### B
<output from candidate labelled B>

### C
<output from candidate labelled C>

### D
<output from candidate labelled D>

## Your task

1. For each output A..D, score each criterion as an integer 1–5.
2. Sum the scores per candidate.
3. Rank candidates by sum, breaking ties with the named tiebreaker criterion.
4. For each output, write one line on its strongest point and one line on its weakest.
5. Pick the top 2.

Do NOT:
- speculate about which prompt or strategy produced which output
- reference the labels beyond the required scoring (no "A seems more structured, suggesting…")
- carry assumptions from outside the rubric
- invent criteria not in the rubric

Return the response in the exact format below.
```

## Required output format

The judge must return exactly this format — the main loop parses it:

```
## Scores

| Cand | <crit-1> | <crit-2> | <crit-3> | ... | Sum |
| ---- | -------- | -------- | -------- | --- | --- |
| A    | 4        | 3        | 5        |     | 12  |
| B    | 5        | 4        | 5        |     | 14  |
| C    | 3        | 5        | 4        |     | 12  |
| D    | 2        | 2        | 3        |     | 7   |

## Ranked

1. B — sum 14
2. C — sum 12 (tiebreaker: <crit>)
3. A — sum 12
4. D — sum 7

## Notes per output

- A: strongest = <one line>. weakest = <one line>.
- B: strongest = <one line>. weakest = <one line>.
- C: strongest = <one line>. weakest = <one line>.
- D: strongest = <one line>. weakest = <one line>.

## Top 2

<letter>, <letter>
```

## Validation (main loop)

After the judge returns, verify:
- Every candidate has every criterion scored (no blanks)
- All scores are integers in [1, 5]
- Sums match
- Ties resolved by the declared tiebreaker

If any check fails, re-dispatch the judge with a single correction instruction pointing to the specific field. Do not "fix" the judge's numbers yourself.

## Bias guards inside the contract

- The input section shows the user's input to the candidates, not the prompts themselves
- Labels A..D are shuffled relative to strategy order — the judge cannot infer strategy from position
- The judge sees no round history, so bias from prior rounds cannot leak in
- "Notes per output" uses labels only — any mention of a specific strategy in the notes means the judge broke blind; re-dispatch
