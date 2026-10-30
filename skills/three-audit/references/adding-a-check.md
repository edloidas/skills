# Adding a New Check

1. Create `references/checks/<name>.md` using the existing checks as a
   template. Required sections: **What it is**, **Why it matters**,
   **How to detect**, **Anti-patterns**, **Canonical fix**, **Notes**, and
   **How to report this finding**.
2. Append a row to the appropriate **Checks** table in SKILL.md with topic and
   severity.
3. If the check is conditional on a project convention, state the activation
   signal in a `**Conditional:**` line in its header block and add the
   detection command to SKILL.md Step 3.
4. If the check needs special detection (beyond grep + read), describe it in
   the check file itself rather than baking shell scripts into the skill —
   keeps each check portable across Claude / Codex / future hosts.
