# Answering a thread

A reply is not a review. A review opens a subject; a reply closes one. `changes-review`'s
`references/publishing-a-review.md` owns how a review is composed and is deliberately **not** reused
here — most of it is about earning standing across a whole diff, and a thread reply has standing
already: someone asked you a question.

What carries over is the gate, restated here because a cross-skill reference path is not loadable.

## The gate

Nothing goes out that has not been established:

- **A demonstration, or no claim.** A `reject` needs evidence a reader can check — a quoted default,
  a link to release notes, a traced call path, a command and its output. "I don't think that's right"
  is not an answer.
- **A green build, or no fix reply.** Never say a thing is fixed before the repo's own checks pass on
  it. This is the ordering that catches a wrong justification: in the run behind
  `verifying-a-claim.md`, the only reason a fabricated claim did not reach the pull request was that
  the fix would not compile.
- **The right version, or no framework claim.** See `verifying-a-claim.md`. A claim about library
  behavior sourced from memory or from the wrong artifact does not ship.
- **No verdict you did not execute.** If it was not verified, its verdict is not `fix` or `reject`.

## How a reply reads

Short, and answering rather than opening. One or two paragraphs is normal; the length is set by the
evidence, not by the effort you want to show.

- **The answer first**, in the first clause. "In short, `AnyStore` requires the wrong members." Not a
  preamble, not a restatement of the question.
- **The real symbols.** Reproduce the actual declaration, default, or line in a fenced block,
  unedited — never a description of it; if you cut lines from the middle, say how many and from
  where. Where a claim turns on a chain of resolution, walk it with the real values and label the
  steps: `Before: DeepMapStore<T> extends MapStore  // FALSE`.
- **Evidence with a link** where one exists — release notes, the source line, the changelog entry.
  A link is what turns a contradiction into a fact.
- **Concede immediately and plainly** when the commenter is right. "Hmm, I missed that part." A reply
  that concedes cheaply is trusted on the things it does not concede.
- **Say when your own point is weak.** "Maybe the least impactful of these." It costs nothing and it
  is the difference between an argument and a report.
- **Hand the decision back.** "Once again, your call." "Say the word and I'll drop the commit." The
  pull request belongs to whoever opened it, and a reply that issues instructions gets resisted on
  procedure instead of read on substance.
- **Answer the next objection** when you can see it coming. Naming the obvious counter-argument and
  addressing it saves a round trip and reads as having thought about it.
- **Never mirror the commenter's register.** A bot's confident phrasing is not a reason to be
  confident back.

## A reply that reports a fix

Shorter still, and a different job: the finding does not need re-explaining, because the fix is the
answer. Say **what changed, why, and how it was checked** — three sentences is usually plenty.

```
Fixed in <sha or "the latest push">. <What changed, in one clause.> <Why that is the right fix
rather than the obvious one, only if it is not obvious.> Verified with `<the repo's own command>`.
```

Do not restate the original claim, do not re-derive the mechanism, and do not thank the commenter for
a finding a bot produced.

## Per verdict

| Verdict | Reply | Resolve |
| ------- | ----- | ------- |
| `fix` | What changed, why, and the check that passed | Yes, if the root was a bot |
| `reject` | The evidence that refutes the premise, or the narrower true claim | Yes, if the root was a bot |
| `already-addressed` | The line or commit that handles it. `isOutdated` is the hint that led you here | Yes, if the root was a bot |
| `discuss` | The tradeoff, with a recommendation and no verdict | **Never** — it needs a human answer |
| `defer` | Why it is not being done now, plainly | Yes, if the root was a bot. Always listed in the report |
| `ack` | Nothing, or one line | Yes, if the root was a bot |

`discuss` triggers on **authority, not difficulty**: the finding is correct and the decision belongs
to a person because it is about scope, architecture, or product. A hard fix you are confident about is
still a `fix`.

Its second trigger is **unverifiability**: a claim about observable output that no probe could settle.
The reply says what could not be observed and why, and asks the author to confirm. Rejecting an
unobserved claim asserts something you did not check, in public, under your own name.

`defer` always appears in the report even though its thread is closed. A deferral nobody can see is
backlog that does not exist yet.
