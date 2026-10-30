# Bug Evidence

An issue is a bug when its label or issue type says so, or when `issue-analyze`'s Scope
Analysis describes current behaviour as wrong rather than missing. For a bug the run
carries a failing-before and a passing-after observation of the same thing. Any other
issue skips **Before** and **After**; **Attack the Premise** applies to every issue.

## Before: reproduce, at the start of Phase 3

Before the first edit, find the cheapest command that shows the failure and run it:

- **A narrowed failing test** in the project's runner — one test file, or one test by name,
  not the whole suite. Where the project has tests, this is the default: written now, it
  becomes the regression test that ships with the fix.
- **A `live-probe` observation**, when the failure only shows at runtime — a rendered page,
  a response, an exit code. Where it cannot be chained, run what the repo declares.

Paste the failing output in a fenced block, unedited, in the message that runs it; if you
cut lines, say how many and from where. The Phase 6 summary quotes its decisive line. This run is the one exception to Phase 3's "no checks as you go".

With no cheap reproduction, print `Repro: impractical — <reason>` and pick the closest
executable check on the same code path. It stands in for the reproduction only if it fails
now; one that already passes cannot show a fix, so the bug is reported `unverified`. The
same holds for a narrowed test that passes before any edit: it has not reproduced the bug.
Narrow it once more against the issue's own steps; if it still passes, it is the stand-in
that passed.

The repro test is not committed on its own. It stays in the working tree with the fix, and
`issue-flow`'s squash rules decide the commit, as for any other change. In slice mode,
reproduce before the slice that carries the fix.

## After: the same observation, at the end of Phase 4

Re-run exactly the command from **Before** — same test, same probe input — once the
selected set is green, and paste it passing the same way. For a bug, this replaces Phase
4's opt-in probe question: the observation was already chosen. From here on the repro is
one of the Phase 4 checks, so every later re-run — after Phase 4.4, 4.5, 4.6 and 7 edits —
includes it, and the summary's `after:` line quotes the last of those runs.

| Before | After | `bug:` line in the summary |
| ------ | ----- | -------------------------- |
| failed | passes | `fixed` |
| failed | still fails | none yet — Phase 4 → On failure |
| impractical, stand-in failed | stand-in passes | `fixed (stand-in: <check>)` |
| impractical, stand-in passed or none | any | `unverified — <reason>` |

## Attack the Premise: two failed fixes

Once two fix attempts at the same check have each failed, do not try a third. Write the
one sentence both fixes assumed — "the value is already normalized when it reaches X" —
then run one observation that would come out differently if that sentence were false: a
log line, a probe, an assertion. Hand back with the failure output, the premise, what the
observation showed, and any stash Phase 2 recorded. Unlike `do`'s bug playbook, which fixes
from that result, solve-issue stops here: a third fix would rest on a premise nobody
re-planned.

```text
Phase 4: stopped — `unit: parseRange` failed twice after two fixes.
Premise: `end` is exclusive when it reaches `clamp()`.
Observation: logged at `range.ts:58` for input "3-7" — `end` is 7 and index 7 is kept,
so `end` is inclusive. The premise is false.
```
