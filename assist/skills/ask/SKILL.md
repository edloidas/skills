---
name: ask
description: >
  Answer the current question at the highest reasoning effort available, in one of three shapes:
  explain a concept, challenge a decision, or verify a claim. Use when a question deserves more
  depth than the default pass, or when a prior answer needs re-deriving from evidence rather
  than defending. Invoke manually with `/ask` or `$ask`.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
disable-model-invocation: true
user-invocable: true
effort: max
metadata:
  author: edloidas
---

# Ask

`effort: max` above raises reasoning effort on hosts that honor it. Where it is ignored, spend
the depth anyway on a complex or ambiguous question — and skip the ceremony entirely on a
straightforward one. A one-line question gets a one-line answer at any effort level.

Pick the shape from the question. Several questions in one message get several answers — run
each through its own shape rather than picking one.

| Question | Shape | Order | Length |
| --- | --- | --- | --- |
| "how does X work?", "what is X?" | **Explain** | Direct answer → why it works → concrete example → caveats and tradeoffs | Builds from foundations when the topic needs it |
| "should we use X?", "why did you do X?", "I think Y instead" | **Challenge** | Verdict — user is right, current approach is right, or a real tradeoff → evidence on both options → concrete next step | Short; the verdict is the payload |
| "are you sure?", "is this correct?", "did you check X?" | **Verify** | Verdict → what you actually re-checked → correction, or why it stands | Short |

**Explain** assumes a competent reader who is not an expert in this specific area — no
groundwork they obviously have, no condescension.

**Challenge** compares the options on correctness, complexity, maintenance cost, and user
impact. Naming all four is the point; a comparison that silently skips maintenance cost is how
the wrong option wins.

Re-derive the answer from primary evidence — code, tests, docs, logs, or current sources — not
from what you said earlier in the conversation. Name what you checked. Name what you could not
check.

Sibling: `bro` reworks an answer already given; `ask` shapes a fresh one.
