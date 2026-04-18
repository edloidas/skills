# Rubric Patterns

Prior-art criteria for common task classes. **Not a menu.** Read, then derive 3–6 criteria that are actually discriminating for the current task. Skip anything generic that does not distinguish good outputs from bad for *this* goal.

## Principles

- **Discriminating, not descriptive.** If every reasonable output scores 5/5, the criterion is dead weight.
- **Observable in the output.** The judge sees the output, not the prompt. Criteria must be gradeable from the output alone.
- **Task-shaped.** "Conciseness" is not universal. For some tasks, detail matters more than brevity. Invert or drop criteria that fight the goal.
- **3–6 total.** Fewer loses signal; more makes the scoring table noisy without adding discrimination.

## By task class

### Explain code / a function to an AI
- **Semantic fidelity** — does the explanation match what the code actually does?
- **Edge-case coverage** — are null/empty/error paths named?
- **No invented caller context** — no hallucinated assumptions about callers the code does not show
- **Actionable for downstream generation** — a model given this explanation could re-implement or modify correctly
- **Invariants named** — preconditions/postconditions called out where they exist

### Summarize a bug report / incident
- **Preserves reproduction steps** — exact repro survives the summary
- **Names root cause (or marks unknown)** — no hallucinated causes
- **Severity calibrated** — matches evidence
- **Caller-agnostic** — no assumptions about who the reader is
- **Timeline intact** — events in order, key times preserved

### Generate SQL from natural language
- **Semantically correct** — returns what was asked for
- **NULL handling** — correct semantics for missing data
- **Index-friendly** — avoids functions on indexed columns where possible
- **Portable syntax** — avoids dialect-specific constructs when not needed
- **Handles empty result gracefully** — the requested edge cases aren't silently dropped

### Write a PR review comment
- **Specific to the diff** — references actual lines/symbols
- **Suggests a concrete change** — not just "this is bad"
- **Cites evidence** — points to prior art, docs, or a test
- **Calibrated tone** — matches severity; no performative politeness
- **Actionable without follow-up** — the author can apply it without re-asking

### Draft a user-facing error message
- **Clear cause** — what went wrong, in plain terms
- **Next action** — what the user can do now
- **No jargon** — terms the target user audience actually uses
- **Correct register** — matches product voice
- **No blame** — does not accuse the user of error when system state caused it

### Convert informal notes into a ticket / issue
- **Captures the ask** — the actual request survives
- **Acceptance criteria named** — or marked as TBD if genuinely unknown
- **Scoped** — what is in and out of scope
- **Reproducible** — enough detail that someone else could start
- **Priority signal** — urgency implicit or explicit

### Generate a test case from a spec
- **Covers the stated behavior** — not a weaker variant
- **Failure mode distinct** — a broken impl would actually fail this test
- **Deterministic** — no time-based or network flakiness
- **Readable** — intent clear without comments
- **Minimal** — no unrelated setup

## Recipe when unsure

1. Read the goal again. What does "good" look like *concretely*?
2. Write 3 criteria that a bad output could plausibly fail. If you cannot name a failure mode for a criterion, it is not discriminating.
3. Check for missing axes: correctness, completeness, style, and safety are the four most commonly missed — scan for each.
4. Cap at 6. Combine related criteria rather than splitting hairs.

## Anti-patterns

- **"Helpfulness"** — too vague to grade
- **"Quality"** — same
- **"Correct"** when the task has no single correct answer — use "plausible" or "internally consistent" instead
- **"Concise"** applied to tasks that need detail — invert to "sufficient detail" or drop
- **Criteria the judge cannot verify** — e.g., "factually accurate" when the judge has no source of truth
