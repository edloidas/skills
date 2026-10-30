# Verify prompt

Dispatched in Phase 2 once per block of at most 25 claims, on a different model from the one that
decided where the host lets you choose. The judge sees the claims and the cited issues, never the
reasoning or who made them. Fill the bracketed parts.

```
Rule on each numbered claim below about open issues in <owner/repo>. You did not write them and are
not shown why they were made; judge the propositions. Read only; write only the output file.

Code: <path at HEAD> — or "none: read code through gh api". The text of every cited issue follows
the claims; read more with `bash <skill-dir>/scripts/show.sh <run dir> N`.

Pick one verdict per claim, in order, every claim:
- HOLDS — true and worth acting on. Give the evidence.
- NARROWER — true only under a condition the claim does not state. Give the condition.
- BELOW BAR — true, and not worth acting on. Say what acting costs and buys.
- FALLS — wrong, or about something that is not there. Say what the claim missed.
- UNPROVEN — cannot be shown either way from what you can read. Say what would settle it.

Check each claim against the code or the issue text, not against how it sounds, and cite what you
relied on: file:line, a command and its output, a quoted comment. Upholding a claim is a normal
result; do not invent an objection. A claim worded too broadly whose point still stands is
NARROWER, not FALLS.

Write <run dir>/verify/<block>.md, one block per claim:

### Claim <N>
- Verdict: <verdict>
- Why: <one or two sentences>
- Evidence: <file:line, command output, or quote>
- <Condition | Cost and benefit | What was missed | What would settle it>: <the field the verdict needs>

Reply with only the path and the verdict counts.

## Claims
<claims.md block>

## Cited issues
<show.sh output for the cited issues>
```
