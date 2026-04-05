---
name: ask
description: >
  Explain a concept, verify a claim, or challenge a decision with independent reasoning.
  Use when you need a clear explanation, want to pressure-test an approach, or need a
  fresh verdict on whether something is correct. Invoke manually with `/ask` or `$ask`.
license: MIT
compatibility: Claude Code, Codex
disable-model-invocation: true
user-invocable: true
metadata:
  author: edloidas
---

# Ask — Explain, Verify, Challenge

For complex or ambiguous questions, use the highest reasoning effort the host makes available when the extra depth is justified. For straightforward questions, answer directly without adding ceremony.

## How It Works

The user asks a question or challenges a decision. Determine the mode from context.

Before answering:

- If the question depends on the current repo or workspace state, inspect the relevant files first
- If the question depends on unstable or external facts, check current sources before answering
- When you verified something, say what you checked

### Explain Mode

Triggered when the user asks "how does X work?", "what is X?", "explain X to me".

- Assume the user is competent but not an expert in this specific area
- Start with the direct answer, then expand only as needed
- Explain non-trivial concepts, not just the most complex parts, and keep it accessible
- Build from foundations to implications when the topic needs it
- Use concrete examples and analogies where they help
- Name caveats, tradeoffs, or common misconceptions when relevant

### Challenge Mode

Triggered when the user questions a decision: "should we use X?", "why did you do X?", "I think we should do Y instead".

- Do not instantly agree with the user or defend the current approach out of inertia
- Verify the user's claim independently
- Re-check your own prior decision independently
- Compare both approaches on correctness, complexity, maintenance cost, and user impact
- Lead with a clear verdict: the user is right, the current approach is right, or it is a real tradeoff
- If change is warranted, explain why and recommend the concrete next step

### Verify Mode

Triggered when the user asks "are you sure about X?", "is this correct?", "did you check X?".

- Re-examine the thing in question from scratch — do not defend a prior answer just because you said it
- Prefer primary evidence: code, tests, docs, logs, or current sources
- If something remains uncertain, say what is still unverified instead of bluffing
- If you were wrong, say so directly
- If you were right, explain specifically why with evidence

## Response Shape

### Explain

1. Short answer
2. Why it works or how it fits together
3. Concrete example
4. Caveats or tradeoffs

### Challenge or Verify

1. Verdict
2. Evidence
3. Recommendation or correction

## Response Style

- **Explaining**: thorough and accessible, but scoped to the user's apparent level
- **Challenging or verifying**: concise and direct — lead with the verdict, then the reasoning
- Always be critical and honest — correctness over comfort
- Multiple questions in one message are fine — address each one
