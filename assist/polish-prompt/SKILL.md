---
name: polish-prompt
description: >
  Iteratively polishes a prompt for a specific task using blind-judged tournaments.
  Each round runs 4 strategically different candidate prompts against an example input via
  parallel subagents; a separate judge scores the outputs (not the prompts) on task-specific
  criteria. Use when the user asks to polish, refine, write, or optimize a prompt — especially
  when they say "polish prompt", "iterate on prompt", "tournament", or describe a reusable
  task they want a good prompt for. Invoke manually with `/polish-prompt`.
license: MIT
compatibility: Claude Code
disable-model-invocation: true
user-invocable: true
argument-hint: "[variant-count] <goal or prompt>"
metadata:
  author: edloidas
---

# Polish Prompt — Tournament Iteration

## Purpose

Turn a task description or draft prompt into a high-quality, reusable prompt through blind-judged tournaments. Each round, N (default 4) strategically diverse candidate prompts run against the same example input(s) via parallel subagents. A separate blind judge scores the **outputs** (not the prompts) on **task-specific** criteria. The user reviews top-2 after each round and decides whether to iterate.

## When to Use

- User says "polish this prompt", "iterate on this prompt", "write me a prompt for…", "optimize this prompt", "tournament"
- `/polish-prompt` invocation
- User has a task they will run many times and wants a reusable prompt for it

## When NOT to Use

- One-off prompts — orchestration overhead outweighs gains
- Tasks with no concrete input to test on (pure meta-instructions without a ground-truth to evaluate)
- User already has a working prompt and just wants a small edit — do the edit directly

## Inputs

Collect in this order, skipping anything already provided:

1. **Goal** — what the prompt should accomplish
2. **Starting point** — existing draft to refine, or writing from scratch?
3. **Example input(s)** — the actual things the final prompt will operate on (a function body to explain, a bug report to summarize, an SQL request, etc.). If none provided, synthesize 1–2 representative ones and show them for approval before round 1. If the user cannot supply or approve an example, abort — this skill needs ground-truth to evaluate outputs.
4. **Variant count** — default `4`; if the first argument parses as an integer, use it as N
5. **Rubric** — derive 3–6 task-specific criteria; show for approval before round 1 (see [`references/rubric-patterns.md`](references/rubric-patterns.md))

## Scoring

Each criterion is an **integer 1–5**. Candidate total is the sum. Ties broken by the criterion the judge names as most important for the task. No decimals, no fake precision.

## Flow

```
Setup
  Parse goal / examples / N
  Derive rubric → user approves/edits
  Derive example input(s) → user approves if synthesized
  (if user cannot supply or approve any input → abort, see Edge cases)
    │
    ▼
Round M
  1. Write N candidate prompts — distinct strategies
     (see references/strategy-catalog.md).
     Keep strategy↔label mapping PRIVATE.
  2. Shuffle labels A..N. Record the shuffle.
  3. Dispatch N runner subagents in ONE message (parallel).
     Each: general-purpose, given (candidate prompt + input(s)),
     returns OUTPUT only — no commentary.
  4. Dispatch 1 judge subagent. Given: rubric + input(s) +
     outputs labelled A..N in shuffled order. Judge does NOT
     see the prompts, strategies, or prior rounds.
     See references/judge-contract.md.
  5. Un-shuffle. Append to log at
     .claude/tmp/polish-<slug>-<session-id>.md
  6. Show user: top-2 PROMPTS + their outputs + score table +
     1-line round summary.
  7. AskUserQuestion: continue / stop / tweak rubric / swap input.
    │
    ▼
Final reveal (on "stop" or user-confirmed convergence)
  • Top pick — full prompt, copy-ready fenced block
  • Runner-up — same format, under "Alternative"
  • 2–3 bullets on why the winner won
  • Offer light format polish, then delete the log file
```

## Steps

### 0. Parse arguments

- If `$ARGUMENTS[0]` is an integer in `[2, 8]`, treat it as N. Outside that range (including `0`, `1`, or `9+`), warn the user and fall back to N = 4. Non-integer first arg → N = 4 and the arg is part of the goal text.
- The rest of `$ARGUMENTS` (or the user's surrounding message) is the goal/source text.
- Pasted references, attached files, or quoted prompts all count as starting material.

### 1. Setup (pre-round)

1. Restate the goal in one sentence back to the user.
2. If no example inputs were provided, synthesize 1–2 realistic ones (representative of expected real usage — not toy examples). Show them.
3. Derive a rubric using [`references/rubric-patterns.md`](references/rubric-patterns.md) as prior art. 3–6 criteria. Do NOT default to generic criteria like "conciseness" unless they are actually relevant to *this* task.
4. Show rubric + examples via `AskUserQuestion` with options: **Proceed / Edit rubric / Edit examples / Cancel**. Wait for approval.

### 2. Candidate generation (per round)

Pick N distinct strategies from [`references/strategy-catalog.md`](references/strategy-catalog.md). In round 1 default to a mix (structural, exemplar-driven, constraint-heavy, minimalist). In later rounds, choose strategies informed by the log — lean toward variations of what worked, drop dead ends.

Write N candidate prompts. Record privately as:

```
A → strategy-X
B → strategy-Y
C → strategy-Z
D → strategy-W
```

### 3. Shuffle

Shuffle labels into random order (e.g., `C, A, D, B`). Record the shuffle map so outputs can be un-shuffled after the judge returns.

### 4. Dispatch runners (parallel)

**Dispatch all N Agent calls in a single message.** Each subagent:

- `subagent_type: general-purpose`
- Prompt template:
  ```
  Apply the prompt below to the input below. Return ONLY the output — no preamble,
  no self-critique, no meta-commentary, no explanation of your reasoning.

  <prompt>
  {candidate_prompt}
  </prompt>

  <input>
  {example_input}
  </input>
  ```
- If multiple example inputs: either run each input in a separate subagent (N × M calls) or pass all inputs at once and instruct the runner to produce one output per input. Default: one input per run; only do N × M when the user has asked for multi-input evaluation.

### 5. Dispatch the judge (blind)

One subagent, `subagent_type: general-purpose`, receiving the schema in [`references/judge-contract.md`](references/judge-contract.md). The judge must:

- See: rubric, example input(s), outputs labelled with the shuffled letters
- NOT see: the prompts, strategy names, author metadata, prior rounds, or any hint of ordering
- Return: per-criterion integer 1–5 per output, sum, top-2 ranking, and one line per output on strengths and weaknesses

### 5a. Validate the judge response

Before trusting the scores, check:

- Every candidate has every criterion scored (no blanks)
- All scores are integers in `[1, 5]`
- Sums match the per-criterion scores
- Ties are resolved by the declared tiebreaker
- "Notes per output" never name a specific strategy — if they do, the judge broke blind

On any failure, re-dispatch the judge with a single correction instruction pointing to the specific field. Do NOT patch the numbers yourself.

### 6. Un-shuffle + log

Apply the shuffle map to map scores back to A..N → strategies. Append a round section to `.claude/tmp/polish-<slug>-<session-id>.md` (see log format below).

### 7. Present to user + checkpoint

Show:
- Score table (candidates × criteria, sums, ranked)
- Top-2 candidate **prompts** with their **outputs** underneath as evidence
- One-line "what to keep / what to drop" from this round
- Current rubric

Use `AskUserQuestion`:

| Header | Options |
|--------|---------|
| Next step | **Run another round** (Recommended) · Stop with current top · Tweak rubric · Swap example input |

### 8. Next round

Based on the log:
- Carry forward strategies / phrasings that scored well
- Replace saturated criteria (all 5/5) with more discriminating ones
- Try strategies that address the bottom-2 weaknesses

### 9. Final reveal (on "Stop")

Output:

````markdown
### Winner
```
<top prompt, verbatim>
```

**Why it won:** <2–3 bullets from the final round's judge notes>

### Alternative (runner-up)
```
<runner-up prompt, verbatim>
```
````

Ask if the user wants format polish. Then ask via `AskUserQuestion`: **Keep log / Delete log**. Only run `rm -f .claude/tmp/polish-*-<session-id>.md` after the user picks delete.

## Log format

Append-only, one section per round. Example:

```markdown
# Polish log — <goal slug>
Session: <session-id>
Goal: <goal>

## Example input(s)
<input 1>

## Rubric v1
- fidelity (1–5)
- completeness (1–5)
- actionability (1–5)

## Round 1
Strategies: A=structural, B=exemplar, C=constraint, D=minimalist
Shuffle sent to judge: C, A, D, B

Scores (un-shuffled)
| Cand | fidelity | completeness | actionability | sum |
| ---- | -------- | ------------ | ------------- | --- |
| A    | 4        | 3            | 4             | 11  |
| B    | 5        | 4            | 5             | 14  |
| C    | 3        | 5            | 4             | 12  |
| D    | 2        | 2            | 3             | 7   |

Top-2: B, C
Keep: concrete exemplars (B), explicit constraint list (C)
Drop: minimalism lost detail (D); pure structure without exemplars felt abstract (A)
Rubric adjustment for round 2: fidelity saturating on top-2 — add "handles edge cases".
```

## Bias guards

1. Main loop does NOT pre-rank candidates before the judge returns.
2. Judge only sees outputs + rubric + input(s) — never the prompts, strategies, or author metadata.
3. Labels are re-shuffled every round; the judge starts fresh with no memory of prior rounds.
4. Rubric is frozen before each dispatch; mid-round tweaks are forbidden (edits apply from next round onward).
5. If one candidate is identical to a prior round's winner, relabel it fresh — do not tell the judge it was preferred before.

## Edge cases

- **User provides an existing prompt:** use it as baseline. Round 1's four candidates = `baseline + 3 variations`.
- **All 4 outputs bad:** log it, do not promote any. Checkpoint with user — tweak rubric, swap input, or increase N.
- **Rubric saturation:** when all candidates score 5/5 on a criterion, replace it in the next rubric version.
- **Compaction mid-run:** the log file is the source of truth. Re-read it on resume and continue from the last round.
- **Ambiguous task class:** if you cannot derive 3+ task-specific criteria confidently, ask the user one clarifying question before deriving the rubric (never dispatch against a generic rubric).

## References

- [`references/rubric-patterns.md`](references/rubric-patterns.md) — prior-art rubric criteria by task class
- [`references/strategy-catalog.md`](references/strategy-catalog.md) — candidate-generation strategies
- [`references/judge-contract.md`](references/judge-contract.md) — judge subagent I/O schema
