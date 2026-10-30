# Run State Schema

The fields of `run.json`. `SKILL.md` → **Run State** owns where the file lives, when it is
rewritten, and when a unit may become `done`.

- **`status`** — `open` or `closed`.
- **`goal`** — the goal sentence, as Phase 0 settled it.
- **`settings`** — every setting from the plan, defaults included.
- **`units`** — one object per unit, in plan order:
  - `id`
  - `kind` — `issue`, `new-issue`, `task`, `own-pr`, `others-pr`, or `decision`
  - `ref` — the issue or PR number the unit acts on; for a task, its one-line statement
  - `endgame` — `pr` or `merge`
  - `status` — `queued`, `running`, `pr-open`, `done`, `blocked`, or `dropped`
  - `branch`, `pr`
  - `evidence` — what showed the unit `done`
  - for a task: `endgame` and `pr` are `null`, and `status` is never `pr-open`
  - `attempts` — every worker sent on the unit, the first included
  - `outcome` — one line
