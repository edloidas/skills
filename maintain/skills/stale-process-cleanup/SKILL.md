---
name: stale-process-cleanup
description: >
  Find and kill stale, leftover, or orphaned developer processes owned by the current user —
  abandoned dev servers (Vite / Vite+), editor LSP servers (oxlint), and duplicate or zombie
  MCP servers (playwright, context7, obsidian) left running after a shell, editor, or agent
  session exited.
when_to_use: >
  When stray node processes turn up, when the user asks who spawned them, or on "kill the
  stale servers", "what is still running", "clean up leftover dev servers".
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash Read AskUserQuestion
argument-hint: "[report|apply]"
---

# Stale Process Cleanup

**Kills processes — destructive and irreversible.** The default run reports only and changes
nothing; `--apply` sends SIGTERM then SIGKILL to the processes it listed as orphaned. Nothing
is killed until the user has seen that list and approved it. No file is written either way.

## Purpose

Developer tooling — dev servers, language-server processes, and MCP servers —
gets reparented to launchd (PPID 1) when the shell, editor, or agent session
that launched it exits. These survive invisibly, hold ports, and pile up. This
skill scans the process table, separates genuinely **orphaned** tooling from
**live** processes that still belong to a running app or session, and reaps only
the orphans.

## When to Use

- "What are all these node processes?" / "Who spawned these?"
- Stray `vp dev` / Vite dev servers, oxlint `--lsp` servers, or `*-mcp` servers piling up
- Ports stuck in use after closing an editor or agent session
- A duplicate MCP server appeared after a reconnect

## Staleness Rule (the safety contract)

A matching process is **stale only if the root of its process tree (the ancestor
whose PPID is 1) is itself abandoned dev tooling.** If the tree traces up to a
live terminal (e.g. cmux), the Claude desktop app, VS Code, or an active agent
session, it is **LIVE** and is never killed — even if it looks redundant. A
duplicate MCP server attached to a running app is reported, not reaped; collapse
it by restarting the owning app.

## Usage

The script lives next to this file and is zsh (macOS `/bin/bash` is 3.2 and lacks
associative arrays — run it directly or via `zsh`, not `bash`). Default is a
dry-run report.

```bash
<skill-dir>/scripts/reap-stale.sh            # report only
<skill-dir>/scripts/reap-stale.sh --apply    # kill orphans (prompts once)
<skill-dir>/scripts/reap-stale.sh --apply --yes   # kill, no prompt
```

## Asking the User

Every question in this skill is written as `AskUserQuestion` options. Use that tool where
the host offers it, or the host's nearest structured-choice equivalent. Where the host has
neither, ask the same question in normal chat as a numbered list of 2–5 options —
recommended first, one short line of description each — and wait for the user to reply
with a number.

## Workflow

1. Run the script with no flags and show the user the **ORPHANED** and **LIVE** sections
   verbatim, in a fenced block. End the phase with one line carrying the counts:
   `3 orphaned, 2 live (2 duplicates)`.
2. The kill is gated on the list from step 1. Ask only after that list is on screen, and name
   the same count in the option. An explicit "kill them" in the original request already counts
   as approval; otherwise ask, per **Asking the User**:
   1. `Kill orphans` (Recommended) — reap the 3 orphaned processes listed above
   2. `Keep them` — leave everything running
   With approval, run `--apply --yes`. Without it, stop here — do not re-run the script, and do
   not kill anything one PID at a time instead.
3. `--apply` reaps only what the script itself classified as orphaned. A LIVE entry is reported,
   never killed: surface the duplicates and suggest restarting the owning app.
4. After a reap, report the script's closing line — `Reaped 3/3 orphaned process(es).` — and
   stop. Do not re-scan to confirm, do not restart what was killed, and do not free ports.

### Example report

```
Stale dev/agent process scan -- user: edloidas

ORPHANED (abandoned tooling, reparented to launchd -- safe to reap):
  PID 4821   06:14:02   vite dev server  node /Users/edloidas/repo/voidvigil/node_modules/.bin/vite-plus dev
  PID 4830   06:14:02   vite dev server  node .../vite-plus/dist/dev-server.js --port 5173
  PID 9142   1-03:22:10 oxlint LSP       oxlint --lsp

LIVE (traces up to a running session/app -- left alone):
  PID 2210   02:41:55   MCP server       (owner: Claude.app)
  PID 2244   02:41:55   MCP server       (owner: Claude.app)

NOTE: possible duplicate live servers (same command running 2+ times): 2210 2244
      Restart the owning app to collapse them; don't blind-kill a live one.

Dry run. Re-run with --apply to kill the 3 orphaned process(es) (add --yes to skip the prompt).
```

Then the phase line: `3 orphaned, 2 live (2 duplicates)`.

## What it detects

| Label            | Matches |
| ---------------- | ------- |
| vite dev server  | `vite-plus … dev`, `vp dev`, generic Vite dev |
| oxlint LSP       | `oxlint … --lsp` |
| MCP server       | `*-mcp`, `mcp-obsidian`, `playwright-mcp`, `@playwright/mcp`, `context7-mcp` |
| dev server       | `next dev`, `storybook`, `webpack-dev-server`, `nodemon`, `vitest` |

Scoped to the current user; the running agent's own process and its live parent
chain are never in the kill set (they trace up to a live session). To add a
pattern, extend the `classify()` function in `scripts/reap-stale.sh`.

## Common Mistakes

- **Killing by PID alone.** A `vp dev` server is a tree (wrapper + vite core); the script reaps the whole orphaned tree by classifying every node and checking each one's root.
- **Reaping a live duplicate.** Two MCP servers under one running app is a reconnect leftover, not an orphan — restart the app, don't kill blind.
