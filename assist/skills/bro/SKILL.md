---
name: bro
description: >
  Say the last message again, straight. Reworks the previous answer — or the
  connected thread of answers — into something short, structured, and skimmable:
  bottom line first, only what matters, concrete next steps. Use when the user
  runs /bro, or asks to say that again simply, cut the fluff, or explain it like
  they have no time.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
disable-model-invocation: true
argument-hint: "[focus]"
metadata:
  author: edloidas
---

# Bro

Say the last thing again, but straight.

## What to rework

The last assistant message. If the last few messages are one continuous thread —
a plan, a diagnosis, a set of options — cover the whole thread as one piece.

`$ARGUMENTS`, when present, narrows it: `/bro just the fix`.

## Hard rules

- **No tools.** Do not read files, run commands, search, or verify anything. It
  is all already in the conversation.
- **No new work.** Do not investigate further, revisit the conclusion, or fix
  anything. This is a rewrite, not a second attempt.
- **No preamble.** Never open with "here's a simpler version". The output *is*
  the rework.
- **Shorter than the original.** Always. If it is not, cut more.

## Shape

1. **Bottom line** — one sentence, first on the screen. What happened, or what
   is true now.
2. **What matters** — two to five bullets. One fact each, bolded lead, plain
   words.
3. **Next** — numbered steps, each one a thing to actually do. Drop this section
   entirely when there is nothing to do; never invent filler steps.

## Keep

- Decisions, each with its one-line reason
- Numbers, filenames, commands, versions, error codes
- Anything that blocks, costs, or breaks if ignored
- Open questions that need an answer

## Cut

- Process narration — "I checked X, then Y, then Z"
- Alternatives already rejected
- Caveats that do not change what the user does
- Hedges, apologies, restated context
- Anything already visible in the output or diff above

## Explaining

Adding new text is fine when something is genuinely hard. Two sentences in plain
words plus one concrete example, then move on. Never a tutorial.

## Formatting

Bold the lead of every bullet so the whole thing reads at a glance. Backticks
for code, paths, and flags. A paragraph longer than three sentences is a bug.
