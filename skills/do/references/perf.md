# Playbook: Performance

Something is slow or heavy, the user wants it faster or lighter, and there is no issue for it.

1. **Name the metric** in one line: what is measured, on which input, in which unit — "wall time
   of `pnpm build` on a clean tree, seconds".
2. **Measure a baseline before changing anything.** Use the `live-probe` skill's way of running
   the thing, at least five runs. Paste the runs, then the median and the range (min–max).
3. **Find where the time goes** — a profile, a trace, timestamps around the suspect step — and
   name the one cause you will change, with `file:line`.
4. **One change, one measurement.** Make a single change and measure it the same way. Stack a
   second change only on top of a measured first one.
5. **Judge it** against the baseline: a new median below the baseline's minimum is a gain; above
   its maximum is a regression; anywhere inside its range is no difference. Revert a regression
   and a no-difference change; keep a gain.
6. **Attack and clean up** a kept change: invoke `changes-review` on the uncommitted changes, fix
   what survives inside the task, then invoke `code-cleanup`.
7. **Final run,** after the last edit: the project's checks — a faster wrong answer is a bug — and
   the measurement once more, judged as in step 5. Paste both.

End with one line: `Perf: <metric> <baseline median> → <final median> (<range>), <gain | no difference | regression, reverted>.`

Then write the report (SKILL.md, Phase 4). Do not commit, and do not tune anything the
measurement did not point at.
