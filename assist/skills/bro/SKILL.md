---
name: bro
description: >
  Say the last message again, straight. Reworks the previous answer — or the connected thread of
  answers — into something shorter and easier to act on: the bottom line first, only what matters,
  and anything you have to decide at the end. Use when the user runs /bro, or asks to say that again
  simply, cut the fluff, or put it in plain words.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
disable-model-invocation: true
argument-hint: "[focus]"
metadata:
  author: edloidas
---

# Bro

Say the last thing again, straight. A rewrite, not a second attempt.

Rework the last assistant message, or the last few when they are one continuous thread — a plan, a
diagnosis, a set of options. `$ARGUMENTS` narrows it, as in `/bro just the fix`.

**No tools** — everything needed is in the conversation. **No new work** — do not investigate,
revisit the conclusion, or fix anything. **No preamble** — the output is the rework. **Shorter than
the original**, always; if it is not, cut more. Where the original is already tight, say so in a
line and stop — precision is never what gets cut to hit a length.

## Language

Open with the sentence the reader would keep if they kept only one. Plain words and real names — the
actual file, flag, number, or error, never a category standing in for it. Say the thing rather than
naming the kind of thing it is: a concrete noun in place of "architectural considerations", "robust
solution", "surface area", "leverage". One idea per paragraph, three sentences at most, and bold the
lead of a bullet so the whole thing reads at a glance.

## Shape

Bottom line first, anything to decide last, and between them whatever the content actually has.
Include a part only when there is something to put in it.

| The original had | The rework has |
| --- | --- |
| A result, a diagnosis, a state of the world | One sentence on what is true now |
| Several facts that each stand alone | One short bullet per fact |
| One thing going on | Prose. Two bullets is not a list |
| Steps that happen in order | A numbered list, each step a thing to actually do |
| Something genuinely hard | Two plain sentences and one concrete example, then move on |
| A next step you would take | One line at the end naming it |
| A choice only the user can make | The decision block, last |

## The Decision Block

Anything the user has to decide goes at the end, never buried mid-answer and never mixed in with the
facts. One numbered question per decision, each carrying your own lean so agreeing costs one word.
Offer the options that are real, drop any that exist for symmetry, and name what the decision turns
on in a clause rather than a balanced summary of both sides. Where the host offers a structured
question prompt and there is exactly one decision, use it; for several related decisions ask inline,
so the context they share stays visible.

## Keep And Cut

Keep decisions already made with their one-line reason, numbers, filenames, commands, versions,
error codes, anything that blocks or breaks if ignored, and questions still open.

Cut process narration, alternatives already rejected, caveats that do not change what the user does,
hedges, apologies, restated context, and anything already visible in the output or diff above.
