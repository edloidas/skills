---
name: labels-sync
description: >
  Synchronize GitHub repository labels with a predefined label set.
  Compares, creates, updates, and deletes labels to match a JSON definition.
  Use when the user asks to sync, check, or manage GitHub labels.
license: MIT
compatibility: Claude Code
allowed-tools: Bash Read AskUserQuestion
user-invocable: true
arguments: "mode"
argument-hint: "[apply|check]"
model: claude-sonnet-4-5
---

# Labels Sync: GitHub Label Synchronization

## Purpose

Synchronize GitHub repository labels with a predefined set of standard labels. Compares the current repository labels against a JSON definition and reports differences — then optionally applies changes.

## When to Use This Skill

Use when the user asks to:
- "Sync labels", "update labels", "fix labels"
- "Check labels", "show label differences", "preview label changes"
- "Manage GitHub labels", "set up labels"
- "Apply standard labels to this repo"

Trigger phrases: "labels-sync", "labels sync", "sync labels", "label sync", "github labels", "check labels"

## Operations

The script compares repository labels against the defined list and reports:
- **CREATE**: Labels in the definition but not in the repository
- **UPDATE**: Labels that exist but have different name case, description, or color
- **DELETE**: Labels in the repository but not in the definition
- **UNCHANGED**: Labels that match exactly

## Execution Steps

### Step 1: Determine Intent

From the command arguments or conversation context, determine the user's intent:

**Apply changes** if user explicitly requests (keywords in args or context):
- `apply`, `sync`, `update`, `fix`, `set`, `enforce`
- Example: `/labels-sync apply` or "sync my labels"

**Report only** if user wants to check (keywords):
- `check`, `list`, `show`, `preview`, `dry-run`, `diff`
- Example: `/labels-sync check` or "show label differences"

**Ask user** if intent is unclear or no arguments provided.

### Step 2: Read Label Definitions

Read the label definitions from the bundled JSON file:

```
references/labels.json
```

Use the Read tool to load the file contents.

### Step 3: Execute Sync Script

Pipe the label JSON to the sync script:

For **dry-run** (report only):
```bash
cat references/labels.json | scripts/sync-labels.sh
```

For **applying changes**, add `--apply` flag:
```bash
cat references/labels.json | scripts/sync-labels.sh --apply
```

### Step 4: Present Results

Parse the JSON output and present as a readable markdown report:

#### Labels to Create
| Name | Description | Color |
|------|-------------|-------|
| ... | ... | ... |

#### Labels to Update
| Name | Field | From | To |
|------|-------|------|-----|
| ... | ... | ... | ... |

#### Labels to Delete
| Name |
|------|
| ... |

#### Unchanged Labels
- label1, label2, label3...

If no changes are needed, report that all labels are already in sync.

If changes were applied, confirm success. If any errors occurred, report them.

## Customization

To customize the label set, edit the JSON file at:
```
references/labels.json
```

Each label entry requires three fields:
- `name` — Label name (case-sensitive)
- `description` — Short description
- `color` — Hex color without `#` prefix (e.g., `B60205`)

## Bundled Files

- `scripts/sync-labels.sh` — Generic sync script (reads stdin JSON, diffs via `jq`, applies via `gh`)
- `references/labels.json` — Label definitions (single source of truth)

## Prerequisites

- `gh` CLI authenticated (`gh auth login`)
- `jq` installed
- Must be run from within a GitHub repository
