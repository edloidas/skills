---
name: editor-config
description: >
  Initialize a project with canonical editor configurations (Zed, VSCode). Asks which editors
  to set up, then writes or merges the bundled settings into the repo. On conflict our values
  win; keys we do not define are preserved.
when_to_use: >
  On "set up editor config", "init .zed", "apply .vscode settings", or "sync the editor
  configs".
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash Read AskUserQuestion
argument-hint: "[zed] [vscode] [--dry-run]"
---

# Editor Config

**Local writes only.** It creates or merges `.zed/` and `.vscode/` files in the target repo.
It never stages, commits, pushes, or calls a remote service.

## Purpose

Drops a small, opinionated set of editor configuration files into a project. The bundled
`assets/` are the source of truth; changing them is maintainer work, described in
`references/maintaining.md`.

## Canonical Set

Two editors, each with one or more target files:

| Editor | Target | Source |
|--------|--------|--------|
| Zed    | `.zed/settings.json`        | `assets/zed/settings.json` |
| VSCode | `.vscode/settings.json`     | `assets/vscode/settings.json` |
| VSCode | `.vscode/extensions.json`   | `assets/vscode/extensions.json` |

## Sync Algorithm

For each target file:

- **Missing in target** → write our copy verbatim.
- **Already exists in target** →
  - `settings.json` files: deep-merge with **our values winning** every conflict.
    Keys the user has that we do not define are preserved.
  - `extensions.json`: **union** the `recommendations` and
    `unwantedRecommendations` arrays, de-duplicated (the result is sorted).

Existing files are read tolerantly — `//` line comments and `/* … */` block
comments (valid in JSONC) are stripped before parsing. The output is always
plain JSON.

The skill prints a per-file plan (`Write`, `Merge`, `Identical`) and asks for
confirmation before writing.

### Edit mechanic

`scripts/editor-config.sh` owns every write to a target repo, and it generates each target
file whole from the merge result — that is correct here, because the merge already carries
the user's own keys forward. Do not hand-edit a target file instead of re-running the script.

## Asking the User

Every question in this skill is written as `AskUserQuestion` options. Use that tool where
the host offers it, or the host's nearest structured-choice equivalent. Where the host has
neither, ask the same question in normal chat as a numbered list of 2–5 options —
recommended first, one short line of description each — and wait for the user to reply
with a number.

## Workflow

1. **Determine editor selection.**
   - If arguments include `zed` and/or `vscode`, use those.
   - Otherwise ask per **Asking the User**, accepting more than one pick:

     ```
     Question: Which editor configs should I set up?
     Header:   Editors
     Options:
       - Zed (Recommended) — Apply .zed/settings.json
       - VSCode            — Apply .vscode/settings.json and .vscode/extensions.json
     ```

     In chat, accept one or more numbers comma-separated (e.g. `1,2`).

2. **Run the script with `--dry-run`** for the selection — without `--yes` the script waits on
   a terminal prompt an agent cannot answer.

   ```bash
   bash <skill-dir>/scripts/editor-config.sh [--dry-run] [--yes] <editor> [<editor> ...]
   ```

   `<editor>` is one of `zed`, `vscode`. Flags:
   - `--dry-run` — print the plan and exit
   - `--yes` / `-y` — skip the per-run confirmation
   - `-h`, `--help` — usage

3. **Review the plan.** The script prints `Target`, `Editors`, then a per-file action
   (`Write`, `Merge`, `Identical`). Show that table and end the phase with one line carrying
   the counts: `3 targets: 1 write, 1 merge, 1 identical`.

4. **Confirm**, per **Asking the User**, then re-run the same command with `--yes` in place of
   `--dry-run`. A `Merge` drops JSONC comments from that file; say so in the question. A
   `ParseError` row blocks the whole run — report which file failed and stop; do not repair the file to get past it unless the
   user asks.

5. **Report the changed files** the script lists, then stop. Do not stage or commit them, and
   do not reopen them to reformat.

### Example plan

```
Target: /Users/edloidas/repo/voidvigil
Editors: zed vscode

Action     File
------     ----
Merge      .zed/settings.json
Write      .vscode/settings.json
Identical  .vscode/extensions.json
```

Then the phase line: `3 targets: 1 write, 1 merge, 1 identical`.

## Edge Cases

- **`jq` missing, or a target with trailing commas.** The script needs `jq`, and reports a
  trailing comma as a parse error without writing — report either and stop.
- **Existing `recommendations` array contains a string we also define.** The
  union de-duplicates by exact string match, so no double entries appear.
- **The user has set a key we also define to a different value.** Ours wins —
  this is the explicit design. If a user customization needs to survive,
  remove that key from `assets/<editor>/settings.json` (see `references/maintaining.md`).
