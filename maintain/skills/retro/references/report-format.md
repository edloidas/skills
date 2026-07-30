# Report Format

The retro report is YAML frontmatter + structured Markdown. The format is
deliberately stable so a future cross-retro analysis skill can parse multiple
reports and find recurring `low`-confidence signals that became real patterns.

## File path

```
~/.claude/projects/<encoded-cwd>/retro/YYYY-MM-DD-HHMM.md
```

`encoded-cwd` is the absolute working directory with every `/` replaced by `-`.

## Skeleton

```markdown
---
date: 2026-05-06
time: 14:30
cwd: /Users/edloidas/repo/skills
findings: 5
applied: 0
---

# Session Retrospective

## Project memory

### 1. Terse-response preference confirmed

- **Confidence:** high
- **Signal:** User: "stop summarizing what you just did at the end of every response, I can read the diff"
- **Target:** `~/.claude/projects/-Users-edloidas-repo-skills/memory/feedback_terse_responses.md` + MEMORY.md index
- **Change:**
  > New file `feedback_terse_responses.md` with type=feedback. Body: "User wants terse responses with no trailing summaries. **Why:** Stated explicitly mid-session. **How to apply:** End turns with the change + next step only; skip recap."
- **Status:** pending

### 2. Project uses Bun, not npm

- **Confidence:** high
- **Signal:** User ran `bun install` in turn 4 after I suggested `npm install`.
- **Target:** `~/.claude/projects/-Users-edloidas-repo-skills/memory/project_package_manager.md` + MEMORY.md index
- **Change:**
  > New file `project_package_manager.md` with type=project. Body: "This project uses Bun for install/run scripts. **Why:** Confirmed in session via `bun install`. **How to apply:** Default to `bun <cmd>` over `npm <cmd>` for this repo."
- **Status:** pending

## Skill fixes

### 3. issue-flow missed epic-* base branch

- **Confidence:** medium
- **Signal:** Skill suggested `main` as the base for a branch off `epic-auth`; user corrected.
- **Target:** `plan/skills/issue-flow/SKILL.md` (or `scripts/` if logic lives there)
- **Change:**
  > Add to base-branch detection: include `epic-*` pattern alongside `main` and `master`.
- **Status:** pending

## Tooling

### 4. Add a pre-push check that runs validate-skills.sh

- **Confidence:** medium
- **Signal:** Two skills shipped without their `<group>/skills/<name>` symlink in the past month (per git log of fixups).
- **Target:** `.husky/pre-push` or `.github/workflows/`
- **Change:**
  > Run `.github/scripts/validate-skills.sh` on push. Fail fast on missing discovery symlinks.
- **Status:** pending

## Discuss-only

### 5. Stale lockfile detour

- **Confidence:** low
- **Signal:** ~12 turns spent debugging missing types before identifying a stale `bun.lock`.
- **Target:** none — record only.
- **Change:** none. Saved for cross-retro pattern detection.
- **Status:** pending

## Applied

(populated at end of Phase 6)
```

## Frontmatter fields

| Field      | Required | Notes                                                          |
| ---------- | -------- | -------------------------------------------------------------- |
| `date`     | yes      | YYYY-MM-DD                                                     |
| `time`     | yes      | HH:MM, 24-hour, local time at write                            |
| `cwd`      | yes      | absolute working directory at retro time                       |
| `findings` | yes      | total count of findings in the file                            |
| `applied`  | yes      | count of findings whose Status is `applied` after Phase 6      |

Keep frontmatter minimal. Anything else belongs in the finding body or section.

## Group ordering

Use this order, omit groups with zero findings:

1. Personal preferences (`~/.claude/CLAUDE.md`)
2. Project conventions (`<project>/CLAUDE.md`)
3. Style rules (`.claude/rules/`)
4. Project memory
5. Global memory
6. Skill fixes
7. Tooling
8. Discuss-only

## Finding fields

Every finding has these fields, in this order:

- **Confidence:** `high` | `medium` | `low`
- **Signal:** verbatim quote or close paraphrase. Prefix with role if a user
  message ("User:", "Assistant:", "Tool error:", "Tool output:").
- **Target:** absolute or repo-relative path + section/identifier.
- **Change:** described as a diff or as exact text being added. Use a
  blockquote (`>`) for the literal new content.
- **Status:** `pending` | `applied` | `skipped` | `discussed`

The fields are stable so cross-retro tooling can parse them. Do not invent new
fields. If something doesn't fit, put it in a free-text paragraph after the
fields, not as a new field.

## Numbering

Findings are numbered globally (`### 1.`, `### 2.`, …) across all groups in
group-order. Numbers are stable for the lifetime of the report file — when
applying or skipping, do not renumber.

## Status mutation

During Phase 6, update the `Status` line in place as findings are acted on:

- `pending` → `applied` if the change landed
- `pending` → `skipped` if user said skip
- `pending` → `discussed` if it was talked through but no edit landed

After Phase 6, update the frontmatter `applied` count and append a final
`## Applied` section listing applied / skipped / discussed by number with
one-line summaries.

## Anti-patterns in reports

- Empty groups (omit instead).
- Findings with `Signal: (paraphrased)` but no actual paraphrase — drop them.
- Multiple findings collapsing the same signal — merge into one.
- Numbered list inside a finding's Change field — use a blockquote with the
  literal text.
- Editorializing (`"This is a great win"`) — the format is mechanical; commentary
  goes in the Phase 4 chat summary, not the file.
