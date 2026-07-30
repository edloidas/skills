---
name: stale-process-cleanup
description: >
  Find and kill stale, leftover, or orphaned developer processes owned by the
  current user — abandoned dev servers (Vite / Vite+), editor LSP servers
  (oxlint), and duplicate or zombie MCP servers (playwright, context7, obsidian)
  left running after a shell, editor, or agent session exited. Use when the user
  notices stray node processes, asks who spawned them, or wants to clean them up.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash Read AskUserQuestion
user-invocable: true
argument-hint: "[report|apply]"
---

# Stale Process Cleanup

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

## Workflow

1. Run the script with no flags and show the user the **ORPHANED** and **LIVE** sections.
2. If there are orphans and the user wants them gone, confirm with `AskUserQuestion` (or honor an explicit "kill them"), then run with `--apply --yes`.
3. Never run `--apply` against LIVE entries — surface duplicates and suggest an app restart instead.

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
