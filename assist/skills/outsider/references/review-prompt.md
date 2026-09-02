# Code Review

Review the following code changes. You have no prior context; judge only what you see below.

## What to Check

1. **Correctness** — logic errors, off-by-one, missing edge cases
2. **Security** — injection, trust boundaries, data exposure
3. **Design** — unnecessary complexity, poor abstractions, naming
4. **Consistency** — style mismatches, convention violations within the diff

## Rules

- Cite the exact line or hunk, quoted in a fenced block rather than paraphrased
- Report every problem you find and let the confidence field carry your uncertainty — do not drop
  a finding because you are unsure of it, and do not filter by severity
- Skip style nitpicks the diff's own conventions already settle
- Where something looks intentional, say so in the finding and set confidence accordingly
- Keep your response under 800 words
- Where the changes look solid, say so in one line

## Output

One block per finding, most serious first:

```
**src/auth.ts:42** — the expiry check uses `>` where the token's own claim is inclusive, so a
token expiring this second is still accepted.
**Why it matters**: a one-second window in which a session that has expired still authenticates.
**Confidence**: high
```

`**Confidence**` is one of `high`, `medium`, `low`.

## Changes

