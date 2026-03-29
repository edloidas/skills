---
name: working-docs
description: >
  Manage working documents in an Obsidian vault using a two-tier system
  (Inbox for quick dumps, Dev/Claude for persistent docs). Handles creating,
  finding, promoting, updating, and completing working documents with proper
  naming, headers, and lifecycle. Use when creating notes for multi-step tasks,
  looking up previous work, managing cross-session state, or when the user asks
  to write something to Obsidian.
license: MIT
compatibility: Claude Code, Codex
allowed-tools: Read Write Edit Glob Grep Bash(ls:*)
metadata:
  author: edloidas
---

# Obsidian Working Documents

Manage working documents in the Obsidian vault for cross-session, cross-project memory.

**Vault path:** `~/Documents/Obsidian Vault/`

Prefer the `obsidian:obsidian-cli` skill for vault interactions (read, create, search, manage notes). Fall back to direct file tools (Read, Glob, Grep, Edit) at the vault path only if that skill is unavailable.

## When to Use

- Multi-step or multi-session tasks — create a working document
- Starting work on a topic that may span sessions — check for existing docs first
- Research findings, implementation plans, PRDs — persistent Claude docs
- Quick findings during debugging or exploration — inbox dump

**Skip** for one-off questions, quick fixes, or trivial tasks.

## Two-Tier System

### Inbox (ephemeral, quick dumps)

- **Location:** `~/Documents/Obsidian Vault/Inbox/`
- **Format:** `YYYY-MM-DD <scope> - <Description>.md`
- **Scope:** freeform short topic — `react`, `auth`, `xp-debugger`, `contentstudio`
- Always `Draft` status
- Promote to `Dev/Claude/` when structured, or delete when stale

### Claude (persistent working documents)

- **Location:** `~/Documents/Obsidian Vault/Dev/Claude/`
- **Format:** `<Type> - <Scope> - <Description>.md`
- **Type:** `PRD` | `Plan` | `Note` | `Research` | `Log`
- **Scope:** freeform — repo name (`app-contentstudio`), skill name (`init-permissions`), tool name (`xp-debugger`), or `general`
- No date in filename — dates in frontmatter only (Created/Updated)
- **Status:** `Draft` | `Active` | `Completed` | `Archived`

### Index

The index file at `~/Documents/Obsidian Vault/Dev/Claude/Claude Working Docs.md` lists all persistent Claude docs. Update it whenever you create, promote, or complete a document.

## Document Header Template

Every working document (both Inbox and Claude) uses this header:

```markdown
# [Description]

#claude #[type] #[scope]

**Project**: [name]
**Repo**: [url or path]
**Created**: YYYY-MM-DD
**Updated**: YYYY-MM-DD
**Status**: Draft | Active | Completed | Archived

---
```

For Inbox docs, status is always `Draft`. Omit `**Repo**` if not project-specific.

## Operations

### Find Existing Documents

Before creating a new document, always check if one already exists. Search in order:

1. Read the index: `~/Documents/Obsidian Vault/Dev/Claude/Claude Working Docs.md`
2. Glob by type: `~/Documents/Obsidian Vault/Dev/Claude/Note - *`
3. Glob by scope: `~/Documents/Obsidian Vault/Dev/Claude/* - app-contentstudio - *`
4. Inbox by date: `~/Documents/Obsidian Vault/Inbox/2026-03*`
5. Grep for status: search `**Status**: Active` in `~/Documents/Obsidian Vault/Dev/Claude/`

If a matching document exists, update it instead of creating a new one.

### Create Inbox Note

Use for quick dumps during active work — findings, partial research, debug notes.

1. Determine scope from current context (repo name, topic, tool)
2. Write to `~/Documents/Obsidian Vault/Inbox/YYYY-MM-DD <scope> - <Description>.md`
3. Use the header template with `Status: Draft`
4. Write content below the `---` separator

### Create Claude Document

Use for structured, persistent documents that will be referenced across sessions.

1. Check for existing docs first (see **Find** above)
2. Determine type (`PRD`, `Plan`, `Note`, `Research`, `Log`) from content purpose
3. Determine scope from project/topic context
4. Write to `~/Documents/Obsidian Vault/Dev/Claude/<Type> - <Scope> - <Description>.md`
5. Use the header template with `Status: Draft` or `Active`
6. Write content below the `---` separator
7. Update the index file — add a line entry for the new document

### Update Existing Document

1. Read the document
2. Update content as needed
3. Bump `**Updated**: YYYY-MM-DD` in frontmatter to today's date
4. Update `**Status**` if it changed (e.g., `Draft` → `Active`)

### Promote from Inbox to Claude

When an Inbox note has grown into structured content worth keeping long-term:

1. Read the Inbox note
2. Determine the appropriate Type and Scope for Claude naming
3. Write the new file at `~/Documents/Obsidian Vault/Dev/Claude/<Type> - <Scope> - <Description>.md`
4. Update the header: set proper status, bump `**Updated**` date
5. Delete the original Inbox file
6. Update the index file

### Complete a Document

When the work described in a document is done:

1. Update `**Status**: Completed` and bump `**Updated**` date
2. Update the index file — mark as completed or move to a completed section

### Archive a Document

When a completed document is no longer actively referenced:

1. Update `**Status**: Archived` and bump `**Updated**` date
2. Update the index file accordingly
