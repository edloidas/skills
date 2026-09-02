---
name: live-probe
description: >
  Settle a claim about observable behavior by running the thing and looking at the result, once.
  Finds the project's declared way to run and observe, picks the cheapest rung that answers the
  claim — a narrowed existing check, a throwaway probe, the built artifact queried directly, a
  rendered frame compared — and returns a verdict with the artifact it read. One hypothesis, one
  observation, then it stops. Not a debugging loop.
when_to_use: >
  When a verification step reaches a claim about output that reading cannot settle — layout,
  rendering, wire format, exit code, timing, log content, a golden or snapshot result — and on
  "prove it", "did that actually fix it", "run it and check".
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash Read Write Edit Glob Grep
user-invocable: false
metadata:
  author: edloidas
---

# Live Probe

Runs commands and may create scratch files; every one it creates is removed before it returns. It
never edits source, never commits, and never changes what it is observing.

## The premise

**Reading settles claims about code structure. Only running settles claims about observable
output.** A missing writer, an unreachable branch, a wrong framework default — those are read by
grepping and by opening the resolved artifact. Layout, rendering, wire format, exit code, timing,
log content — those leave no trace in the source that reading can check.

A claim of the second kind reported as "verified by reading" is **not verified**. That is the whole
gap this skill fills, and it is the one place a review is most likely to be confidently wrong: "I
fixed the overflow" cannot be refuted from a diff, and neither can it be confirmed.

**This is not debugging.** One hypothesis, one observation, one verdict. A probe that does not
answer its question is a probe that ends — it does not become an investigation. Debugging is a
different activity with a different budget, and conflating them is how a verify step eats an hour.

## What a probe is

Three properties, all required:

- **Bounded** — one command and one observation. If setup alone outgrows a couple of minutes,
  drop to a cheaper rung or report the claim unverified with that cost named.
- **Citable** — it yields something specific to point at: a response body, an exit code, a log
  line, a golden diff, a rendered frame, a stack trace with a file and line. "It looked right" is
  not an artifact.
- **Discarded** — scratch files, scratch scripts, and captured output leave the tree. Nothing a
  probe creates is committed.

## Which claims need one

| Claim is about | Settled by | Example |
| -------------- | ---------- | ------- |
| Code structure | Reading | "Nothing writes this field any more" |
| A dependency's behavior at the resolved version | Reading the resolved artifact | "The supertype default returns null" |
| Reachability from an actor | Reading call paths | "No caller can pass that value" |
| **Observable output** | **Running** | "The container overflows at narrow widths" |
| **Wire format or protocol** | **Running** | "The response omits the field" |
| **Exit code, timing, log content** | **Running** | "It exits 0 on a malformed input" |
| **A golden, snapshot, or image result** | **Running** | "The snapshot still matches" |

Where a claim splits — a premise about the world and a conclusion about this code — a probe answers
whichever half is about output, and reading answers the other. Both halves need an answer.

## Finding the way to run

In this order. The point of the order is that the project and the user already decided this, and a
guess that contradicts them is worse than no probe.

1. **The agent instruction layer** — `CLAUDE.md`, `AGENTS.md`, `.claude/rules/`, `.agents/rules/`,
   and the project docs they point at. Where it names a tool for running the app, driving a
   browser, or rendering components in isolation, that tool is the answer. It also owns the local
   conventions: which ports, which flags, where captured artifacts belong.
2. **The repo's declared commands** — manifest scripts, a `Makefile`, a task runner, the CI
   workflow. CI is the most reliable of these: it is the one list of commands that is known to run.
3. **Nothing else.** Never invent a command the repo does not define, and never assume a tool is
   installed because the ecosystem usually has it. Absent both sources, the answer is `unverified` —
   do not manufacture a test suite, a harness, or a fixture the project does not have. A repo with
   no way to run itself is reported as such; filling that gap is scope expansion wearing a safety
   vest.

Expect **one** such tool to exist, not a matched pair. A project with a component harness often has
no browser driver, and the reverse is as common. Detect what is there; do not require a pair.

## The ladder

Cheapest rung that can answer the claim. Stop there — a rung that answers it makes every rung below
it waste.

| Rung | What it is | Costs |
| ---- | ---------- | ----- |
| 1 | **An existing check, narrowed** — the one test, golden, or snapshot covering the touched path | Seconds. Always try this first |
| 2 | **A throwaway probe** — a scratch script or test that executes the exact case, deleted after | Seconds to a minute |
| 3 | **The built artifact, queried** — start the server, binary, or CLI; hit the one endpoint or invoke the one command; read the output | A minute, plus a process to clean up |
| 4 | **Rendered and compared** — a component harness, a headless browser, an image or golden diff | Slowest. Only for a claim that is genuinely visual |

Two techniques for rungs 2 and 3 when ambient state gets in the way: probe with an identifier that
cannot already exist, so nothing masks the result; and remove whatever props the happy path up, so
the real symptom appears.

At rung 4, read computed values rather than markup. A class name, an attribute, or a DOM shape is
the input to rendering, not its result — the claim is about the result.

**A snapshot or golden is inspected, never accepted.** Updating it to match makes any claim pass.

Before running, print one line: `Probing <the claim> at rung <N>: <the command>`.

## The one-hypothesis boundary

The probe tests the claim as stated. When the first observation does not settle it:

| Situation | Do |
| --------- | -- |
| The observation contradicts the claim | Report `refuted` with the artifact |
| The observation reproduces the claim | Report `reproduced` with the artifact |
| The setup failed — nothing built, nothing started, the tool is absent | Report `unverified`, name what was missing |
| The observation is ambiguous, or answering needs a second hypothesis | **Stop.** Report `unverified` and say what a real investigation would have to establish |

That last row is the rule that keeps this cheap. Callers running rounds — a fix loop, a polish
pass — may probe again after changing the code, because that is a new hypothesis about new code.
A second probe against the *same* code to chase the *same* question is debugging, and belongs to a
debugging workflow instead.

## Running things without breaking things

The instruction layer owns the specifics. These hold regardless of what it says:

- **Probe ownership before touching a port or process.** Something already listening was not
  started here. Use it read-only and never stop it.
- **Clean up only what this probe started**, and only what it started.
- **Suppress anything that opens a window or a browser tab** on a machine a person is using.
- **Captured artifacts go where the project puts them** — the instruction layer names the
  directory. Absent one, the scratch location, never the working tree.
- **Never edit source to make a probe work.** Removing a prop to expose a symptom is reverted the
  moment the observation is taken.

## What to return

One block. Callers quote the evidence line verbatim into their own reports, so it has to be the
specific thing.

```text
- **Verdict**: reproduced | refuted | unverified
- **Rung**: 1 | 2 | 3 | 4 — <the command or tool actually used>
- **Evidence**: <the artifact: response, exit code, log line, diff, frame — not "checked the code">
- **Cleanup**: <what was removed, or "nothing created">
```

`unverified` also carries **what was missing** — no declared runner, the tool is not installed, the
build failed, the observation was ambiguous. A named absence is a usable result; a silent one reads
as a pass. Never report `reproduced` or `refuted` without an artifact on the evidence line.

A filled instance:

```text
- **Verdict**: refuted
- **Rung**: 2 — `node --test test/scratch-offset.probe.mjs`
- **Evidence**: `parseOffset('-1.5')` returned `-2`, not the `-1` the finding claimed; the same
  probe returned `-1` against the previous commit
- **Cleanup**: removed `test/scratch-offset.probe.mjs`
```

Then stop. Do not fix what the probe revealed, do not probe the same code a second time, and do not
turn the result into an investigation. The caller decides what happens next.
