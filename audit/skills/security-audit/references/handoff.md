# Task Emission (Step 4, options 1–3)

Skip this entirely when the host has no task tracker.

- One task per finding from the Step 3 report (options 1, 2). For option 3, emit a single task whose description is a numbered list of all findings.
- `subject`: short finding title (e.g., "Pin `actions/checkout@v6` to SHA").
- `description`: severity (including any `(policy)` qualifier), source subagent (`[Actions]`, `[Release]`, `[Repo Settings]`, `[Package Manager]`, `[Code]`), file:line or API path, the exact remediation snippet from the report.
- `metadata`: minimum set — `severity`, `source_area`, `change_kind` (`code` for file edits / `server_state` for `gh api` writes), `intended_action` (`fix` / `file_issue` / `summary`). Keep metadata light — the task queue is a handoff, not the audit's persistence layer.
- **Sequencing**: for any pair from Step 3's `### Sequencing` section, record the downstream task as blocked by the upstream one, using whatever dependency field the host's tracker exposes. If it has none, state the ordering in the task description.
- Emit tasks worst-first within each severity, matching the report's order.
