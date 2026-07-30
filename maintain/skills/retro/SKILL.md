---
name: retro
description: >
  Reflect on the current Claude Code session, surface what went well and what
  caused friction, and produce durable artifacts (memory entries, CLAUDE.md
  edits, rule files, skill fixes). Use when the user asks to retro, reflect on
  the session, or learn from the conversation we just had.
license: MIT
compatibility: Claude Code
allowed-tools: Read Write Edit Glob Grep Bash AskUserQuestion
metadata:
  author: edloidas
---

End-of-session retrospective. Scan the in-context conversation for friction and
wins, write a structured report to a per-project retro directory, then optionally
apply findings to memory, CLAUDE.md, rule files, or affected skills.

This skill is **user-invoked only**. Do not run it autonomously. You may
*suggest* running it at the end of a session if friction was visible, but the
user always triggers it.

## Hard Rules

1. **No edits to production source.** Only these targets are writable: SKILL.md /
   skill `scripts/`, project CLAUDE.md, global `~/.claude/CLAUDE.md`,
   `.claude/rules/*.mdc`, auto-memory files, and lint/test/CI configs.
2. **Quote the signal.** Every finding includes the verbatim or closely
   paraphrased trigger from the conversation. If you cannot reconstruct it, drop
   the finding — do not fabricate.
3. **Show the diff.** Before applying anything — even under `Apply safe` —
   display the exact line(s) being added and the exact target file/section.
4. **No findings → no file.** If nothing passes the value bar, print one bold
   line and exit. Do not write an empty report.
5. **Honest confidence.** Tag every finding `high`, `medium`, or `low`. Don't
   inflate. Low-confidence findings exist precisely so a future cross-retro
   pass can spot recurring patterns; promoting them defeats the point.
6. **Don't duplicate auto-memory.** Read `MEMORY.md` first. If a memory already
   covers the finding, skip it.

## Phases

### Phase 1 — Scan

Review the in-context conversation. For each candidate signal, classify it using
`references/signal-classes.md`. The signal classes are guidance, not enforcement
— session analysis is partly vibes, and the long-term value comes from
aggregating retros over time, not rigor within one.

For each candidate, collect:

- **Trigger:** verbatim or close paraphrase of the user message, tool error, or
  turn-N event.
- **Confidence:** `high` (user said it explicitly OR pattern recurred ≥2 times),
  `medium` (clear inferred pattern, single occurrence), `low` (a hunch — saved
  for cross-retro analysis only).
- **Bucket:** target destination per `references/bucket-routing.md`.
- **Proposed change:** exact diff/line, exact target file and section.

Apply the value bar from `references/signal-classes.md`. Drop findings that fail
it.

### Phase 2 — Decide whether to write

If zero findings remain after the bar, output exactly:

> **No findings worth saving from this session.**

Then exit. No file. No preamble. No turn count.

### Phase 3 — Write the report

Compute the encoded cwd: replace every `/` in the absolute working directory
with `-`. Example: `/Users/foo/repo/proj` → `-Users-foo-repo-proj`.

Write to: `~/.claude/projects/<encoded-cwd>/retro/YYYY-MM-DD-HHMM.md`

Create the `retro/` directory if it does not exist.

Use the structure documented in `references/report-format.md`. Findings are
grouped by bucket and **numbered globally across groups** so the user can
reference any finding by its number.

### Phase 4 — Present in chat

Print:

1. The path to the report file.
2. A 1-line-per-group prose summary. Do not repeat full findings — they live in
   the file.

Example:

> Report: `~/.claude/projects/-Users-edloidas-repo-skills/retro/2026-05-06-1430.md`
>
> - **Project memory (2):** terse-response preference, monorepo workspace layout.
> - **Skill fixes (1):** `issue-flow` missed an epic-* base branch.
> - **Discuss-only (1):** debugging detour around stale lockfile.

### Phase 5 — Ask the meta question

Use `AskUserQuestion` with these options (recommended first):

- **Walk through each** — Go finding-by-finding with apply/skip.
- **Apply safe (memory only)** — Auto-apply memory-bucket findings; surface the
  rest for discussion.
- **Discuss numbers** — User types the numbers they want to discuss in chat.
- **Skip all** — Leave the report as a record, take no action.

Headers ≤12 chars. Each option description must reflect the actual finding mix
(e.g., note how many memory items vs CLAUDE.md items exist) — do not fabricate
counts.

### Phase 6 — Act

Execute the chosen path:

- **Walk through each:** for every finding, show the exact diff, ask
  apply/skip/edit, then act.
- **Apply safe:** auto-apply only `Project memory` and `Global memory` bucket
  findings. For each one, still print the diff before writing. Do **not** apply
  any CLAUDE.md edit, rule file, or skill fix in this path.
- **Discuss numbers:** wait for user input listing finding numbers, then walk
  through each listed item.
- **Skip all:** do nothing further.

After each apply, mark the finding's `Status` field in the report from `pending`
to `applied` (or `skipped` / `discussed`). When the action sequence ends, append
a final `## Applied` section to the report listing what landed and what didn't.

## Bucket-to-target cheat sheet

| Bucket                 | Target                                                                                |
| ---------------------- | ------------------------------------------------------------------------------------- |
| Personal preference    | `~/.claude/CLAUDE.md`                                                                 |
| Project convention     | `<project>/CLAUDE.md`                                                                 |
| Style/convention rule  | `<project>/.claude/rules/<topic>.mdc`                                                 |
| Cross-session pattern  | `~/.claude/projects/<encoded-cwd>/memory/<feedback_*.md>` + `MEMORY.md` index update  |
| Skill gap or bug       | The affected skill's `SKILL.md` or `scripts/`                                          |
| Tooling gap            | Concrete edit to lint/test/CI config (proposed; not auto-applied)                     |
| Discuss-only / one-off | No save target — listed for record only                                                |

Full routing rules: `references/bucket-routing.md`.

## Confidence calibration

| Confidence | When to assign                                                  | Action default            |
| ---------- | --------------------------------------------------------------- | ------------------------- |
| `high`     | Explicit user statement, OR pattern recurred ≥2 times in session | Apply if user agrees      |
| `medium`   | Clear inferred pattern, single occurrence                        | Discuss before applying   |
| `low`      | Hunch only; might be a pattern, might be noise                   | Save to report; do not apply |

`low`-confidence findings are saved primarily so a future cross-retro analysis
can identify ones that recurred across sessions. Do not act on them within a
single retro.

## Edge cases

- **Compacted session:** if the conversation was auto-compressed, early-session
  signals may be invisible. Acknowledge this once in Phase 4 prose summary if
  relevant. Do not attempt to recover compressed turns.
- **Memory file already covers the finding:** drop it. Don't duplicate.
- **Session was short / pure Q&A:** likely Phase 2 exits with the bold no-op
  line. That is a correct outcome, not a failure.
- **Finding spans multiple buckets:** pick the most durable single bucket. Do
  not split one finding into two.
- **User asks to retro but the session was someone else's work (worktree, fresh
  shell):** if the in-context conversation has ≤3 substantive turns, exit with
  the no-op line.

## What this skill does NOT do

- Read saved session `.jsonl` files. Only the in-context conversation.
- Run on a cron or hook. User-invoked only.
- Edit production source code, even when a finding seems to point at code.
- Bulk-apply CLAUDE.md edits. Every CLAUDE.md change shows the exact line and
  needs explicit per-line approval.
- Aggregate across past retros. That's a separate future skill — this one
  produces the structured input for it.
