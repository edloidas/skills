---
name: labels-sync
description: >
  Synchronize or export GitHub repository labels against a predefined label set. Compares,
  creates, updates, deletes, or reads labels as reusable JSON definitions.
when_to_use: >
  On "sync labels", "check the labels", or "export the labels", and when a new repository
  needs the standard label set applied.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash Read AskUserQuestion
argument-hint: "[apply|check|get]"
---

# Labels Sync: GitHub Label Synchronization

**Writes to an external service.** `apply` mode creates, renames, recolours and **deletes**
labels on the GitHub repository through `gh`. Deleting a label strips it from every issue and
PR that carries it and cannot be undone, so apply runs only after the diff has been shown and
approved (**Step 6**). `check` and `get` modes read only and change nothing, locally or remotely.

## Purpose

Compare a repository's labels against a JSON definition, apply the difference, or export the
repo's current labels in copy-ready JSON. Which of the three runs is decided in **Step 1**.

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

## Asking the User

Every question in this skill is written as `AskUserQuestion` options. Use that tool where
the host offers it, or the host's nearest structured-choice equivalent. Where the host has
neither, ask the same question in normal chat as a numbered list of 2–5 options —
recommended first, one short line of description each — and wait for the user to reply
with a number.

## Execution Steps

### Step 1: Determine Intent

Match the arguments or the conversation against one of three modes:

| Mode | Keywords | Effect |
|------|----------|--------|
| Apply | `apply`, `sync`, `update`, `fix`, `set`, `enforce` | Diff, then write to GitHub after approval |
| Check | `check`, `list`, `show`, `preview`, `dry-run`, `diff` | Diff only |
| Get | `get`, `export`, `read`, `copy`, `json` | Print current labels as JSON |

If intent is unclear or no arguments are provided, ask per **Asking the User**:

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

Skip this step for **get/export** mode.

### Step 4: Compute the Diff

Run the dry-run first, in every mode including apply — the diff is what the approval in Step 6
is given against:

```bash
cat references/labels.json | scripts/sync-labels.sh
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

End the phase with one line carrying the counts: `7 to create, 2 to update, 1 to delete, 12 unchanged`.
If every count is zero, that line is `All 22 labels already in sync` and the run is finished.

For **get/export** mode, return the exact JSON in a fenced code block first, then optionally a
short summary table of names and colors.

#### Worked example

```markdown
#### Labels to Create
| Name | Description | Color |
|------|-------------|-------|
| `feature` | New functionality | 1D76DB |
| `chore` | Maintenance work with no user-facing change | FEF2C0 |

#### Labels to Update
| Name | Field | From | To |
|------|-------|------|-----|
| `bug` | color | d73a4a | b60205 |
| `Documentation` | name | Documentation | docs |

#### Labels to Delete
| Name |
|------|
| `wontfix` |

#### Unchanged Labels
- enhancement, good first issue, help wanted, question
```

Then the phase line: `2 to create, 2 to update, 1 to delete, 4 unchanged`.

### Step 6: Gate the Apply

In **check** and **get** mode, stop after Step 5. Do not offer to apply, and do not run the
script again with `--apply`.

In **apply** mode, the diff from Step 5 is on screen; deletions cannot be undone. Ask, per
**Asking the User**, naming the counts and every label in the delete list:

1. `Apply all` (Recommended) — create 2, update 2, delete 1 (`wontfix`)
2. `Apply without deletes` — create and update only; leave extra labels in place
3. `Cancel` — change nothing

Then run the choice:

```bash
cat references/labels.json | scripts/sync-labels.sh --apply
```

`--apply` performs the whole diff, so `Apply without deletes` means editing the definition or
running the create/update `gh` calls individually — never `--apply` with a delete the user
declined.

### Step 7: Report and Stop

Report what the script's stderr log confirms — `Created 2, updated 2, deleted 1` — and name any
`gh` error verbatim. Then stop: do not re-run the diff to confirm, and do not touch issues,
milestones, or anything else in the repo.

## Customization

To customize the label set, edit the JSON file at:
```
references/labels.json
```

Apply targeted edits per entry; never rewrite the whole file, so the diff shows only the labels
that actually changed. Each label entry requires three fields:
- `name` — Label name (case-sensitive)
- `description` — Short description
- `color` — Hex color without `#` prefix (e.g., `B60205`)

## Bundled Files

- `scripts/sync-labels.sh` — the sync/export script driving every step above
- `references/labels.json` — label definitions (single source of truth)

## Prerequisites

- `gh` CLI authenticated (`gh auth login`)
- `jq` installed
- Must be run from within a GitHub repository
