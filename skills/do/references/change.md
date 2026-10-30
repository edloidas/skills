# Playbook: Change

A small feature or refactor that has no issue.

1. **Plan in 3–5 lines:** what changes, in which files, what stays the same, and the check that
   shows it works. Print the plan, then go on without waiting.
2. **Implement** with targeted edits per hunk, matching the code around it.
3. **Run the project's checks** and paste the result lines. A refactor keeps behaviour, so the
   existing tests must pass unchanged.
4. **Attack it** when the diff is more than about 20 lines or spans more than one file: invoke
   `changes-review` on the uncommitted changes and fix what survives inside the task.
5. **Clean up:** invoke `code-cleanup`.
6. **Final run,** after the last edit: the project's checks again, pasted.

End with one line: `Change: <what is true now> — <N> files, checks <passed | failed>.`

Then write the report (SKILL.md, Phase 4). Do not commit, and do not widen the change past the
plan; anything the plan did not cover goes under **Outside this task**.
