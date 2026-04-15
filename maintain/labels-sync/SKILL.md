---
name: labels-sync
description: >
  Synchronize or export GitHub repository labels with a predefined label set.
  Compares, creates, updates, deletes, or reads labels as reusable JSON definitions.
  Use when the user asks to sync, check, manage, or export GitHub labels.
license: MIT
model: claude-sonnet-4-6
compatibility: Claude Code, Codex
allowed-tools: Bash Read AskUserQuestion
user-invocable: true
argument-hint: "[apply|check|get]"
---

# Labels Sync: GitHub Label Synchronization

## Purpose

Synchronize GitHub repository labels with a predefined set of standard labels, or export the current repository labels as reusable JSON. The skill can compare the repo against a JSON definition, apply the missing changes, or return the repo's current label definitions in copy-ready form.

## When to Use This Skill

Use when the user asks to:
- "Sync labels", "update labels", "fix labels"
- "Check labels", "show label differences", "preview label changes"
- "Manage GitHub labels", "set up labels"
- "Apply standard labels to this repo"
- "Export labels", "get current labels", "show labels JSON", "copy labels to another repo"

Trigger phrases: "labels-sync", "labels sync", "sync labels", "label sync", "github labels", "check labels", "export labels", "get labels"

## Operations

For sync and check flows, the script compares repository labels against the defined list and reports:
- **CREATE**: Labels in the definition but not in the repository
- **UPDATE**: Labels that exist but have different name case, description, or color
- **DELETE**: Labels in the repository but not in the definition
- **UNCHANGED**: Labels that match exactly

For export flows, the script reads the current repository labels and returns a normalized JSON array with:
- `name`
- `description`
- `color`

## Execution Steps

### Step 1: Determine Intent

From the command arguments or conversation context, determine the user's intent:

**Apply changes** if user explicitly requests (keywords in args or context):
- `apply`, `sync`, `update`, `fix`, `set`, `enforce`
- Example: `labels-sync apply` or "sync my labels"

**Report only** if user wants to check (keywords):
- `check`, `list`, `show`, `preview`, `dry-run`, `diff`
- Example: `labels-sync check` or "show label differences"

**Export current labels** if user wants reusable output (keywords):
- `get`, `export`, `read`, `copy`, `json`
- Example: `labels-sync get` or "export current labels so I can copy them to another repo"

If intent is unclear or no arguments are provided, use `AskUserQuestion` when
available. Otherwise ask in normal chat with a short numbered list and wait for
the user's reply:

1. `Check` (Recommended) — Compare the repo labels against the bundled definition
2. `Get` — Export the repo's current labels as reusable JSON
3. `Apply` — Sync the repo labels to match the bundled definition

### Step 2: Export Current Labels When Requested

For **get/export** mode, fetch and return the current repository labels directly:

```bash
scripts/sync-labels.sh --get
```

Return the output in a fenced `json` block so the user can copy it into another repository later. Keep the fields in the reusable definition shape:

```json
[
  {
    "name": "bug",
    "description": "Something isn't working",
    "color": "B60205"
  }
]
```

If the user explicitly asks for only `name` and `color`, summarize those fields in the prose response, but keep the script output in the full reusable format unless they ask to omit descriptions.

### Step 3: Read Label Definitions for Sync/Check

Read the label definitions from the bundled JSON file:

```
references/labels.json
```

Use the Read tool to load the file contents.

Skip this step for **get/export** mode.

### Step 4: Execute Sync Script

Pipe the label JSON to the sync script:

For **dry-run** (report only):
```bash
cat references/labels.json | scripts/sync-labels.sh
```

For **applying changes**, add `--apply` flag:
```bash
cat references/labels.json | scripts/sync-labels.sh --apply
```

### Step 5: Present Results

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

For **get/export** mode, prefer returning the exact JSON in a fenced code block first, then optionally add a short summary table of label names and colors if that helps the user scan it.

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

- `scripts/sync-labels.sh` — Generic sync/export script (exports current labels, or reads stdin JSON, diffs via `jq`, and applies via `gh`)
- `references/labels.json` — Label definitions (single source of truth)

## Prerequisites

- `gh` CLI authenticated (`gh auth login`)
- `jq` installed
- Must be run from within a GitHub repository
