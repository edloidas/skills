# Playbook: Review and Fix

Attack the current changes, or check findings already in hand, fix what is real, and show the tree
still passes.

1. **Pick the scope.** A scope the user named — a base branch, a commit — wins. Otherwise the
   uncommitted changes if there are any, else the branch against its base. Say which in one line.
2. **Run the project's checks first** and paste them, so a later failure is attributable.
3. **Get the findings.** With findings already in hand — from a review, a bot, the user — invoke
   `doubt` on them. Otherwise invoke `changes-review` on the scope from step 1.
4. **Fix each finding that survives** inside the task's scope, with targeted edits per hunk. A
   finding you do not fix gets one line in the report: rejected with its evidence, or outside the
   task.
5. **Clean up:** invoke `code-cleanup`.
6. **Final run,** after the last edit: the project's checks. Paste them.

One review round. The fixes are checked by step 6, not by a second review.

End with one line: `Review: <N> findings → <N> fixed, <N> rejected, <N> outside the task.`

Then write the report (SKILL.md, Phase 4). Do not commit, and do not start a second round.
