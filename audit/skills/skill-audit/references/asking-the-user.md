# Asking the User — Canonical Section

Any skill declaring a non-Claude host and asking a question carries this section verbatim,
immediately before its first procedural section, at `##`, or `###` where the skill nests its
conventions. `validate-skills.sh` compares the paragraph below against each asking skill's
copy, whitespace-collapsed. Call sites say `Ask, per **Asking the User**:` and do not restate
the fallback.

## Asking the User

Every question in this skill is written as `AskUserQuestion` options. Use that tool where
the host offers it, or the host's nearest structured-choice equivalent. Where the host has
neither, ask the same question in normal chat as a numbered list of 2–5 options —
recommended first, one short line of description each — and wait for the user to reply
with a number.
