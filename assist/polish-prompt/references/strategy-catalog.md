# Strategy Catalog

Strategies for generating **diverse** candidate prompts in one round. Diversity is the point — four near-identical prompts give the judge nothing to discriminate between. Pick N strategies that differ along at least one axis: structure, verbosity, example use, constraint density, or framing.

## Round-1 default mix (N = 4)

A reasonable baseline when no prior signal exists:

| Label | Strategy              | In one line                                              |
| ----- | --------------------- | -------------------------------------------------------- |
| A     | Structural            | Sections, tags, explicit I/O schema, numbered steps      |
| B     | Exemplar-driven       | Few-shot with 1–2 worked examples before the real input  |
| C     | Constraint-heavy      | Dense rule list, explicit negatives ("do not …")         |
| D     | Minimalist            | Shortest wording that still carries the full instruction |

## Full catalog

### Structural
- Uses XML tags, Markdown sections, or a numbered step list
- Declares an explicit output schema ("Return JSON with keys …" or "Return sections: Cause / Fix / Test")
- Best when the downstream model needs a predictable shape

### Exemplar-driven
- Includes 1–2 worked examples before the real input, in the same format the model should produce
- Examples should be representative, not corner cases
- Best when the task has a learnable pattern that's hard to describe abstractly

### Constraint-heavy
- Leads with rules; includes explicit negatives ("never", "do not", "avoid")
- Good at suppressing specific failure modes
- Risk: over-constrained outputs become wooden

### Minimalist
- Shortest phrasing that still includes the goal and any non-obvious requirement
- Tests whether extra scaffolding is earning its keep
- Often surprising — a well-worded paragraph can beat three-page prompts

### Role / persona
- Opens with "You are an X who …"
- Sets implicit quality bar via domain framing
- Works when the task benefits from a specific voice or expertise register
- Be wary of generic roles ("helpful assistant") — they add tokens without signal

### Chain-of-verification
- Instructs the model to produce a draft, then self-check against criteria, then revise
- Costs more tokens per run but often improves factual fidelity
- Useful when the rubric includes criteria like "no invented details"

### Inverted-negative / failure-first
- Leads with "Here is a bad output: …" and tells the model to avoid producing something similar
- Counter-intuitively strong when the main failure mode is subtle

### Comparative / criteria-aligned
- The prompt literally mirrors the rubric: one section per criterion
- Honest — the model optimizes for what will be graded
- Risk: feels mechanical; the judge's rubric is not always the reader's rubric

### Think-then-answer (scratchpad)
- Instructs the model to produce reasoning in a hidden scratchpad before the final answer
- Works when the output requires correctness the model can self-critique
- Make the scratchpad explicitly discardable so only the final answer is returned

### Socratic / question-led
- Frames the task as answering specific questions about the input
- Good when the output is naturally enumerable (facts, findings, items)
- Less good when the output is a single piece of prose

### Baseline (special)
- Reserved for when the user supplies an existing prompt — include it unchanged so the tournament measures relative improvement

## Picking strategies in later rounds

1. **Keep what worked.** If an exemplar-driven prompt won, the next round should include at least one exemplar-driven variant — but with different example choices or ordering to see which part carried the win.
2. **Drop dead ends.** If minimalism lost badly, don't keep retrying it in pure form. Mix it with a stronger strategy.
3. **Attack the rubric bottleneck.** If the runner-up lost on "edge-case coverage", try a candidate explicitly oriented at edge cases (constraint-heavy or chain-of-verification).
4. **Use prior winners as ingredients, not templates.** Refactor what worked into new candidates rather than shipping the same prompt twice.

## Diversity check before dispatch

For each pair of candidates, ask: could the judge tell these apart? If two candidates differ only in whitespace or synonym choice, replace one with a more divergent strategy.
