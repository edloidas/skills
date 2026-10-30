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
disable-model-invocation: true
allowed-tools: Bash Read AskUserQuestion
argument-hint: "[apply|check|get]"
metadata:
  tier: manual
---

# Labels Sync: GitHub Label Synchronization

**Writes to an external service.** `apply` mode creates, renames, recolours and, unless the
user keeps them, deletes labels on the GitHub repository through `gh`, and runs only after the
diff has been shown and approved (**Step 5**). `check` and `get` modes read only and change
nothing, locally or remotely.

## Purpose

Compares a repository's labels against `references/labels.json` and reports each as CREATE,
UPDATE (name case, description, or color), DELETE, or UNCHANGED; applies that diff, with or
without the deletes; or exports
the repo's current labels as reusable JSON (`name`, `description`, `color`).

## Asking the User

Every question in this skill is written as `AskUserQuestion` options. Use that tool where
the host offers it, or the host's nearest structured-choice equivalent. Where the host has
neither, ask the same question in normal chat as a numbered list of 2–5 options —
recommended first, one short line of description each — and wait for the user to reply
with a number.

## Execution Steps

`<skill-dir>` below is the directory holding this `SKILL.md`. Run every command from the target
repository, since `gh` resolves the repo from the working directory.

Done means: in get mode the Step 2 JSON is presented, in check mode the Step 4 results; in sync
mode Step 6 has reported — or the Step 5 gate is waiting on the user.

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
bash <skill-dir>/scripts/sync-labels.sh --get
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
In get mode, the run ends here.

### Step 3: Compute the Diff

Run the dry-run first, in every mode including apply — the diff is what the approval in Step 5
is given against:

```bash
bash <skill-dir>/scripts/sync-labels.sh < <skill-dir>/references/labels.json
```

### Step 4: Present Results

Parse the JSON output and present it in the shape of the worked example below — a table each
for create, update, and delete, and a comma list of unchanged labels. End the phase with one line carrying the counts: `7 to create, 2 to update, 1 to delete, 12 unchanged`.
If every count is zero, that line is `All <N> labels already in sync`, where `<N>` is the number of labels in the target set and the run is finished.

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

### Step 5: Gate the Apply

In **check** mode, stop after Step 4 (and in **get** mode, after Step 2). Do not offer to apply, and do not run the
script again with `--apply`.

In **apply** mode, the diff from Step 4 is on screen. Name the target repo
(`gh repo view --json nameWithOwner`) and the create and update counts, then print the delete
list on its own, one label per line, followed by this line verbatim:

> Deleting a label strips it from every issue and PR that carries it, and cannot be undone.

Ask, per **Asking the User**:

1. `Sync without deletes` (Recommended) — create 2, update 2; keep `wontfix`
2. `Sync with deletes` — create 2, update 2, delete 1 (`wontfix`)
3. `Cancel` — change nothing

When the delete list is empty, skip the deletion line and offer only `Sync` and `Cancel`. Run
the choice — `--no-delete` moves the extra labels from `delete` to `kept` and makes no
`gh label delete` call:

```bash
bash <skill-dir>/scripts/sync-labels.sh --apply --no-delete < <skill-dir>/references/labels.json   # without deletes
bash <skill-dir>/scripts/sync-labels.sh --apply < <skill-dir>/references/labels.json               # with deletes
```

### Step 6: Report and Stop

Report the script's last stderr line — `Created 2, updated 2, deleted 0, kept 1` — and name
any `gh` error verbatim. The script re-reads the labels before writing, so if its counts differ
from the ones approved at Step 5, say which. The first failing `gh` call stops the run, so name
which writes before it landed; deletes run last. Then stop: do not re-run the diff to confirm, and do not touch issues,
milestones, or anything else in the repo.

## Customization

`references/labels.json` is the label set. Edit it with targeted edits per entry, never a
whole-file rewrite; each entry needs `name` (case-sensitive), `description`, and `color` (hex, no `#`).

## Prerequisites

- `gh` CLI authenticated (`gh auth login`) and `jq` installed — the script checks both first and
  exits 1 naming the missing one; report that line and stop
- Must be run from within a GitHub repository
