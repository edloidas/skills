---
name: explain
description: >
  Explain how something actually works — code, a type, an error, a fix, a design — by tracing
  the mechanism on concrete values instead of describing it. Also checks whether the user's
  own account of something is correct.
when_to_use: >
  When the user asks how or why something works, wants a walkthrough or a step-by-step, says
  an earlier answer did not land ("explain again", "simpler", "I still don't get it"), asks
  again on a subject already explained, or asks whether what they wrote about it is right.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Read Glob Grep Bash Task
argument-hint: "[what to explain]"
metadata:
  author: edloidas
---

# Explain

Build understanding. The test of the answer is whether the reader can predict what the thing does
next time without you there.

`$ARGUMENTS` names the subject. With no argument, the subject is whatever the previous message was
about — go deeper on it rather than restating it shorter. Where that message already carried a
recommendation or a plan, keep it: the trace goes underneath it, and the recommendation is restated
unchanged at the end. Deepening the reasoning is not a reason to withdraw the answer.

This skill reports only: it reads, and it runs read-only commands to capture real values. It
edits nothing.

## Ground It First

Read the thing before explaining it: the file, the declaration, the failing output, the actual run.
Never explain from what was said earlier in the conversation when the artifact itself is available.
Earlier turns are where errors accumulate.

List every file, declaration, and output the trace will touch, and open all of them in one
response before writing a word — on a second pass over files already read this session, only the
ones carrying a step you are about to assert as mechanism. A trace built on one file out of five
reads as complete and is not.

Where the real value can be produced rather than reasoned about, produce it — run the command,
print the resolved type, compile the case, log the payload. An explanation built on a captured
value is correct for the reader's actual situation. One built on recall is a guess with confident
grammar. Where the artifact cannot be read or run at all, explain from what you can see and mark
every unverified step as unverified — recall is still the fallback, but it is never presented as a
captured value.

Read it yourself up to about **5 files** or **1000 lines**. Past that, dispatch subagents over
disjoint slices in parallel, each returning the values and declarations it found rather than a
summary. Where the host has no subagent facility, read the same slices inline.

Say what you verified and what you did not.

## Trace, Don't Describe

The mechanism is the payload. A correct account of *what* something does, with no walk through
*how* it produces its result, reads like an answer and leaves the reader where they started.

Lead with the concrete result — the resolved value, the captured output, the observed behavior.
Walk the mechanism that produces it one step at a time, using the real symbols from the code rather
than stand-ins — pseudocode is one. Say why it is built that way, where that is not obvious.
Land the consequence in one sentence.

That is an arc, not a template. Skip any part the subject does not have, and let a one-line
question have a one-line answer.

## A Term Is Not An Explanation

Naming a mechanism is not showing it, and one word that compresses three is a summary the reader
has to unpack alone. Before using a term, expand it silently. If the plain words come out more
specific than the term, they were the explanation and the term was hiding it.

"Fails closed" is one word for "when the check throws, the request is blocked rather than allowed".
The second is longer, complete, and needs nothing looked up. Prefer it. Compressing to a single
word is only free when expanding it would tell the reader nothing they cannot already see.

Keep the vocabulary that names what the reader is looking at — `extends`, `declaration`, an
identifier from the file, a header on the wire, a config key. Those are the subject, not shorthand
for it, and they survive every pass below.

## Pick The Move The Content Calls For

Each move fires on its own trigger. Where none applies, write prose.

| The content | The move |
| --- | --- |
| Some cases change and others do not | Show them side by side, and say which one moved |
| A value comes out wrong | Walk the substitution that produces it, step by step, with the real symbols |
| You have real output | Paste it in a fenced block, unedited — never describe what a compiler, command, or test would say |
| An expression is dense | Follow it with one plain sentence restating it |
| One exact token carries the bug | Annotate that token inline, inside the code block |
| The step turns on where a name sits in a nesting spread across files — a component tree, a middleware chain, a call stack | A plain-text tree of the real names, indented by depth: the path from the root to the node the step turns on, the siblings it is compared against, and that node marked inline |
| A fix | The declaration before and the declaration after, and nothing else from the diff |
| Control crosses several components, threads, or processes | Number the steps in execution order — see **Go Linear** |
| The answer has genuinely separate parts | Give each a header written as a claim or a question, not a noun |
| Several things across several dimensions | A table |

Real output goes in a fenced block exactly as it came back. Where you cut lines, say how many and
from where, inside the block:

```
FAIL  src/auth.test.ts > rejects a token that expired this second
AssertionError: expected 401 to be 200
    at isFresh (src/auth.ts:42:11)
[9 stack frames cut from the middle]
    at runTest (node_modules/vitest/dist/chunk.js:88:5)
```

Never trim silently, and never retype output from memory as though it were captured.

## The Second Pass

Invoking this skill again on the same subject *is* the signal, with or without a complaint. So are
"explain again", "simpler", and "I still don't get it". None of them mean the answer was too long.
The same explanation sent shorter fails the same way, and a second pass is often *longer* than the
first, because plain words take more of them than jargon does.

Three things change, and they compose.

### Change the move

- A finding becomes a mechanism. Evidence, severity, and a recommendation answer "what should I do
  about this", which is a different question from "how does this work". Check this one first: if
  round one answered the other question, this is the swap, and the rest follow from it.
- Describing becomes tracing — walk the substitution instead of characterizing it.
- The general case becomes one concrete instance, with real values in it.
- Prose becomes a run — show the thing happening.

### Strip the jargon

Round one may use the vocabulary of the subject. Round two may not use anything the reader would
have to already know, apart from the names of what is on the screen and the reader's own stack,
which stays at **Altitude** — per **A Term Is Not An Explanation**. What gets stripped is the term
standing in for the mechanism being explained, not the vocabulary the reader works in every day.
Replace every term standing in for a mechanism instead of showing it, and the
English doing the same job: "falls through", "inherited rather than introduced", "errs towards",
"surfaces", "propagates".

The replacement is what the term means *on this subject*, in plain words:

| Instead of | Say |
| --- | --- |
| predicate | the function, or "the check" |
| revokes / revocation | takes away access |
| falls through to the matcher | reaches the list check |
| opaque origin | what a sandboxed iframe or a `file://` page sends |
| fails closed | errs towards blocking |
| captured by closure | worked out while the controller was still running |
| mutation-checked | each branch was deleted in turn to confirm a specific test starts failing |
| RFC 6454 normalised | the port is left off when it is the scheme's default — 443 for https, 80 for http |
| inherited rather than introduced | the HTTP side already behaves the same way, so this change is not what introduced it |

The right column is not a dictionary. Each one is what that term meant on one subject, worked out
from the code in front of you — which is the work the term was avoiding.

### Go linear

Round two is a walk, not an essay. Show the machine running: you press the pedal, that opens the
fuel valve, that fills the cylinder, that fires.

- Fix one scenario at the top and carry it unchanged to the end — real host names, real config,
  real values. Never switch examples mid-walk.
- Where three or more components, threads, or processes each own a step and the walk runs past six
  steps, put one map between the scenario and step 1, and only one per answer. Lanes are the real
  names — `console.example.com`, `handshake thread`, not `Client` and `Server`. One arrow per
  crossing, labelled with the number of the step it starts and the call it carries. The map says
  where a step happens, never what it finds — no verdicts, no branch labels, or it becomes a second
  walk. Draw it as a Mermaid `sequenceDiagram` in pi, which renders one, and as a plain-text lane
  diagram everywhere else, where the fenced source is what the reader gets;
  `references/worked-examples.md` has one.
- Number the steps in the order execution reaches them, one thing per step. Title each step with
  what happens in it, not what it is about. **Pick The Move** applies per step, not per answer — one
  step may carry annotated code and the next pasted output.
- Introduce nothing before the step where it matters, and refer back to nothing that has not
  happened yet.
- Where a step is the surprising one, say so inside that step rather than warning about it earlier.
- End on the observable outcome the reader started from, and say what would have happened instead
  without the mechanism just walked.

Structure is what carries the second pass, so a step that only restates the previous one is a step
to delete, not to keep for symmetry.

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

Then stop. Do not fix what the explanation exposed and do not offer to — the deliverable is the
understanding, and the fix is a separate request. Restating a recommendation the previous message
already made is not that.

## Worked Examples

`references/worked-examples.md` holds four explanations that landed, each annotated with the move
that carried it — including one second pass over a subject already explained once. Read it when the
subject is substantial and the right shape is not obvious.

## Related

- `assist/skills/bro` — compress an answer already given. This skill deepens one.
- `assist/skills/discuss` — take a position on a decision. This builds understanding.
- `review/skills/code-to-spec` — when the deliverable is a rebuild spec rather than comprehension.
