# Measuring a timing claim

A claim about speed, timing, memory, or frame rate is settled by a series of runs, not by one. A
single run carries the machine's noise as if it were the code's cost, so one number can show a
gain, a regression, or nothing at all, depending on what else the machine was doing.

The probe stays one hypothesis and one command; only the observation becomes a series. Find the way
to run it exactly as SKILL.md says — the project's declared command, never an invented benchmark.

## Before the first timed run

1. **Write the claim as you would report it**, with the metric, the input, and the unit: "`pnpm
   build` on a clean tree takes longer than 40 s", "the list renders at under 30 fps with 5,000
   rows". The series below tests that sentence and nothing wider.
2. **Confirm the work runs inside the timed region.** Check one run for the evidence that the work
   happened: the request reached the server, the rows were written, the output was produced and is
   correct. Lazy code — a generator nobody iterates, a promise nobody awaits, a result the runtime
   discards — and fast failures produce numbers for work that never ran. A run that errored is not
   a data point; count errors, and report them.
3. **Warm up.** Run the command at least once untimed, so first-run costs — compilation, caches,
   lazy initialisation, disk reads — do not land on whichever side runs first. When the claim is
   about a cold start, the cold state is the thing measured: reset it before every run instead,
   and say so.
4. **Note the environment**: the machine, the build mode (debug or release, dev server or
   production build), and the load — what else is running. A busy machine is not a reason to stop;
   it is a reason to alternate and to say so.

## The series

- **At least 5 timed runs per side.** A side is one state being measured: the code before and after
  a change, option A and option B, or the one state an absolute claim is about.
- **Alternate A and B** — A, B, A, B — so warm-up, caches, thermal throttling, and background drift
  favour neither. When the two sides are two states of the tree, keep one in a separate checkout at
  the scratch location — a worktree or a clone, never inside the working tree — so both can run in
  turn. When alternating is impossible, run the sides back to back and
  name that on the report line.
- **Report the median and the range (min–max) per side**, with the raw runs. Not the mean: one
  stalled run moves the mean and leaves the median alone.
- **Cap the series at about 10 minutes of wall time.** When 5 runs per side cannot fit, measure a
  smaller input that still exercises the claimed path and say so, or report `unverified` with the
  cost named.

## Reading the result

- **A difference inside the run-to-run range is no difference.** B is faster only when its median
  is below A's minimum, and slower only when its median is above A's maximum. Anything between is
  `no difference`, however the medians compare.
- **An absolute claim** ("takes longer than 40 s") holds when the whole range sits on its side of
  the threshold, fails when the whole range sits on the other side, and is `unverified` when the
  range straddles it.
- **Check the bound.** Removing or speeding up a part that takes a fraction *p* of the run can make
  the whole run at most 1 / (1 − *p*) times faster: a part taking 10% gives at most about 1.11×. A
  measured gain past that bound measured something else — a cache, a skipped step, a bug — and is
  reported as `unverified` with that named.
- **Map the outcome onto the verdict by the claim's direction.** `no difference` refutes a claimed
  speedup or regression and reproduces a claimed non-effect; a measured difference reproduces the
  claim when it points the claimed way and refutes it otherwise.
- **Name the gap** when the series could not answer: the work could not be confirmed to run, runs
  errored, or the sides could not run under the same conditions.

## Report line

The evidence field of the probe's result carries one line in this form, followed by the raw runs:

```text
<metric>: A <median> (<min>–<max>) vs B <median> (<min>–<max>), <n> runs each, <alternating | back to back>, <k> warm-up; <verdict>. Env: <machine>, <build mode>, <load>
```

A filled instance, inside the result block:

```text
- **Verdict**: refuted
- **Rung**: 3 — `pnpm build`, run 7 times per side alternating with the commit before the change
- **Evidence**: build wall time: A 41.8 s (40.9–43.5) vs B 41.2 s (40.3–42.7), 7 runs each,
  alternating, 1 warm-up; no difference — B's median sits inside A's range, so the claimed 20%
  speedup did not appear. Env: 8-core laptop on mains power, production build, editor and browser
  open. Runs A: 41.8 40.9 43.5 41.6 42.0 41.1 42.4; B: 41.2 40.3 42.7 41.0 41.9 40.8 41.5
- **Cleanup**: removed the second checkout at the scratch location
```
