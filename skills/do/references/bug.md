# Playbook: Bug

Something produces the wrong result, the user wants it fixed, and there is no issue for it.

1. **Reproduce first.** Find the cheapest command that shows the failure — a test in the project's
   runner, a script, a request — and run it before touching code. A failure that only shows at
   runtime goes through the `live-probe` skill. Paste the failing output, unedited. With no cheap
   reproduction, print `Repro: impractical — <reason>` and pick the closest executable check on the
   same path. It stands in for the observation only if it fails now; one that already passes
   cannot show a fix, so the fix will be reported as unverified. A narrowed test that passes before
   any edit has not reproduced the bug either: narrow it once more against the user's steps, and if
   it still passes, it is a stand-in that passed.
2. **Find the cause** in the code the failure points at. State it in one sentence, with `file:line`.
3. **Fix it** with targeted edits per hunk. Add a regression test where the project has tests and
   none covers the case.
4. **Run the same observation again** and paste it passing.
5. **Two fix attempts at the same check have each failed?** Before a third, write the premise
   both assumed as one sentence — "the value is already normalized when it reaches X" — and test
   it directly: a log line, a probe, an assertion. Fix from what that shows, not from the premise.
6. **Attack the diff:** invoke `changes-review` on the uncommitted changes, and fix each finding
   that survives inside the task's scope.
7. **Clean up:** invoke `code-cleanup`.
8. **Final run,** after the last edit: the observation from step 4 and the project's checks. Paste
   both.

End with one line: `Bug: <fixed | fixed (stand-in: <check>) | unverified | not fixed> — <before → after, in one clause>.`

Then write the report (SKILL.md, Phase 4). Do not commit, and do not fix what step 2 or step 6
found outside the task — list it.
