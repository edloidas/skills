# Playbook: Performance

Something is slow or heavy, the user wants it faster or lighter, and there is no issue for it.

1. **Name the metric** in one line: what is measured, on which input, in which unit, and which
   direction is better — "wall time of `pnpm build` on a clean tree, seconds, lower is better".
2. **Measure a baseline before changing anything.** Use the `live-probe` skill's way of running
   the thing, at least five runs. Paste the runs, then the median and the range (min–max).
3. **Find where the time goes** — a profile, a trace, timestamps around the suspect step — and
   name the one cause you will change, with `file:line`.
4. **One change, one measurement.** Make a single change, as targeted edits, and measure it the same way. Stack a
   second change only on top of a measured first one.
5. **Judge it** against the baseline: a new median better than the baseline's best run is a gain;
   worse than its worst run is a regression; anywhere inside its range is no difference. Keep a gain. Undo a
   regression or a no-difference change hunk by hunk with targeted edits — never a file-level
   checkout or restore, which also discards the user's own uncommitted work — then go back to
   step 3 for the next cause. Stop after three changes without a gain.
6. **Attack and clean up** a kept change: invoke `changes-review` on the uncommitted changes, fix
   what survives inside the task, then invoke `code-cleanup`.
7. **Final run,** after the last edit: the project's checks — a faster wrong answer is a bug — and
   the measurement once more, judged as in step 5. Paste both.

End with one line: `Perf: <metric> <baseline median> → <final median> (<range>), <gain | no gain after <N> changes, all undone>.`

Then write the report (SKILL.md, Phase 4). Do not commit, and do not tune anything the
measurement did not point at.
