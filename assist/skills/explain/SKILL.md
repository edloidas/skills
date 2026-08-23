---
name: explain
description: >
  Explain how something actually works — code, a type, an error, a fix, a design — by tracing the
  mechanism on concrete values instead of describing it. Also checks whether the user's own account
  of something is correct. Use when the user asks how or why something works, wants a walkthrough or
  a step-by-step, says an earlier answer did not land ("explain again", "simpler", "I still don't
  get it"), or asks whether what they wrote about it is right.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Read Glob Grep Bash Task
argument-hint: "[what to explain]"
effort: high
metadata:
  author: edloidas
---

# Explain

Build understanding. The test of the answer is whether the reader can predict what the thing does
next time without you there.

`$ARGUMENTS` names the subject. With no argument, the subject is whatever the previous message was
about — go deeper on it rather than restating it shorter.

## Ground It First

Read the thing before explaining it: the file, the declaration, the failing output, the actual run.
Never explain from what was said earlier in the conversation when the artifact itself is available.
Earlier turns are where errors accumulate.

Where the real value can be produced rather than reasoned about, produce it — run the command,
print the resolved type, compile the case, log the payload. An explanation built on a captured
value is correct for the reader's actual situation. One built on recall is a guess with confident
grammar.

Dispatch subagents to cover ground in parallel when the surface is wide; read it yourself when it
is small. Where the host has no subagent facility, do the same reading inline.

Say what you verified and what you did not.

## Trace, Don't Describe

The mechanism is the payload. A correct account of *what* something does, with no walk through
*how* it produces its result, reads like an answer and leaves the reader where they started.

Lead with the concrete result — the resolved value, the captured output, the observed behavior.
Walk the mechanism that produces it one step at a time, using the real symbols from the code rather
than stand-ins. Say why it is built that way, where that is not obvious. Land the consequence in
one sentence.

That is an arc, not a template. Skip any part the subject does not have, and let a one-line
question have a one-line answer.

## Pick The Move The Content Calls For

Each move fires on its own trigger. Where none applies, write prose.

| The content | The move |
| --- | --- |
| Some cases change and others do not | Show them side by side, and say which one moved |
| A value comes out wrong | Walk the substitution that produces it, step by step, with the real symbols |
| You have real output | Paste it — never describe what a compiler, command, or test would say |
| An expression is dense | Follow it with one plain sentence restating it |
| One exact token carries the bug | Annotate that token inline, inside the code block |
| A fix | The declaration before and the declaration after, and nothing else from the diff |
| The answer has genuinely separate parts | Give each a header written as a claim or a question, not a noun |
| Several things across several dimensions | A table |

## When The First Explanation Did Not Land

"Explain again", "simpler", "I still don't get it" means the move was wrong, not that the length
was wrong. The same explanation sent shorter fails the same way, and a longer one with more
evidence fails harder.

Change the move:

- Describing becomes tracing — walk the substitution instead of characterizing it.
- The general case becomes one concrete instance, with real values in it.
- Prose becomes a run — show the thing happening.
- A finding becomes a mechanism. Evidence, severity, and a recommendation answer "what should I do
  about this", which is a different question from "how does this work".

## Checking The User's Account

When the user offers their own understanding and asks whether it holds, the deliverable is a
verdict on it, not a fresh explanation.

- Answer each of their points, in their numbering.
- Label every correction by kind. A substantive error and a small refinement are different news,
  and flattening them hides which one matters.
- Confirm what is right plainly, without restating it back at length.
- Where they want their text fixed, keep their wording and their voice. Correct the claim, not the
  style.
- List word-level and grammar fixes separately at the end, so they are auditable at a glance.

## Altitude

Write for a competent reader who is not an expert in this particular area. Skip groundwork they
obviously have. Where a term is load-bearing and probably unfamiliar, define it in one clause and
move on.

## Close Honestly

End on what limits the explanation, where something does: who actually hits this, what is still
wrong, what you chose not to cover, what you could not check. Stopping at "and that is how it
works" claims a completeness you have not earned.

## Worked Examples

`references/worked-examples.md` holds three explanations that landed, each annotated with the move
that carried it. Read it when the subject is substantial and the right shape is not obvious.

## Related

- `assist/skills/bro` — compress an answer already given. This skill deepens one.
- `assist/skills/discuss` — take a position on a decision. This builds understanding.
- `review/skills/code-to-spec` — when the deliverable is a rebuild spec rather than comprehension.
