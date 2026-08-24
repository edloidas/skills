# Fix and Reverify — Re-check

The finding below is **unsettled**. Either a previous round raised it and rated its own confidence
low, or a fix was applied and its symptom could not be re-observed afterwards. Either way nobody
knows whether it is true. That is your entire job: settle it.

You are not asked whether the finding is worth fixing, whether it is severe, or how it should be
fixed. Only whether it is **true**.

## The finding

{{FINDING}}

## How to settle it

**Demonstrate or refute.** Reading the code and finding the story plausible is what produced the low
rating in the first place; repeating that produces another low rating and wastes the round.

- Run the case the finding names. Execute the input, compile the change, write a throwaway probe,
  inspect what a dependency actually resolves to instead of recalling its documented default.
- **Probe with a name that cannot already exist** whenever ambient state could satisfy the thing you
  are testing. A probe that passes because something else already registered the identifier proves
  nothing.
- **Remove the ambient condition.** Delete or disable whatever props the happy path up — the
  seeded cache, the default config, the top-level registration — and see whether the symptom
  appears. It usually takes one line, and it is the whole difference between "this could fail" and
  "here it is failing".
- **Where the claim is about observable output, reading cannot settle it at all.** Layout,
  rendering, wire format, exit code, timing, log content, a golden or snapshot result: none of these
  leave a trace in the source. Find the way to run it from the agent instruction layer (`CLAUDE.md`,
  `AGENTS.md`, rules files) first, then the repo's declared commands — manifest scripts, `Makefile`,
  task runner, CI workflow — and never invent one. Read computed values, not markup. Inspect a
  snapshot; never accept it. Nothing runnable at all means `low`, with the absence named.
- Name who reaches it. A defect no caller, input, or configuration can arrive at is not a defect,
  however correct the mechanism reading is.
- **One hypothesis.** You get one observation of this finding. If it comes back ambiguous the answer
  is `low` — chasing a second theory turns a re-check into a debugging session on someone else's
  budget.

**Default to refuting.** If you cannot demonstrate the failure, the answer is `low` again — not
`medium` out of politeness to the reviewer who filed it. A finding nobody can demonstrate after two
attempts is being dismissed on purpose, and that is the correct outcome.

## What you return

```
Verdict: high | medium | low
Established by: execution | reading
<One paragraph: what you did, what happened, and what that proves. Name the input or state and the
result. If you narrowed the finding — the failure is real but only for a subset of what was
claimed — say exactly which part survives.>
```

- `high` — you made the failure happen, or the code cannot do otherwise and you can show why.
- `medium` — the defect is real but you could not reach it, or it holds only under a condition you
  could not confirm exists.
- `low` — you tried to demonstrate it and could not, or the reading it rests on turned out to be
  wrong.
