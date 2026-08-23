---
name: editor-config
description: >
  Initialize a project with canonical editor configurations (Zed, VSCode).
  Asks which editors to set up, then writes or merges the bundled settings
  into the repo. On conflict, our values win — keys we do not define are
  preserved. Use when the user asks to set up, init, apply, or sync editor
  configs / .zed / .vscode in a project.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash Read AskUserQuestion
argument-hint: "[zed] [vscode] [--dry-run]"
---

# Editor Config

## Purpose

Drop a small, opinionated set of editor configuration files into a project. The
skill is the **source of truth** — its bundled configs in `assets/` are what
every target repo gets. To update the canonical configs, edit the files in this
skill and commit; the next run propagates the change everywhere else.

## When to Use This Skill

Trigger phrases: "editor config", "editor-config", "init editor", "setup editor",
"apply editor config", "sync editor config", "init zed", "init vscode", "set up
.zed", "set up .vscode", "configure editor".

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
    `unwantedRecommendations` arrays. No duplicates, order preserved with our
    entries appended first.

Existing files are read tolerantly — `//` line comments and `/* … */` block
comments (valid in JSONC) are stripped before parsing. The output is always
plain JSON.

The skill prints a per-file plan (`Write`, `Merge`, `Identical`) and asks for
confirmation before writing.

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

2. **Run the apply script** for each selection.

   ```bash
   bash <skill-dir>/scripts/editor-config.sh [--dry-run] [--yes] <editor> [<editor> ...]
   ```

   `<editor>` is one of `zed`, `vscode`. Flags:
   - `--dry-run` — print the plan and exit
   - `--yes` / `-y` — skip the per-run confirmation
   - `-h`, `--help` — usage

3. **Review the plan.** The script prints `Target`, then a per-file action
   (`Write`, `Merge`, `Identical`).

4. **Confirm.** Type `y` to apply. Anything else aborts.

5. **Verify.** After apply, the changed files are listed. Run `git status` /
   `git diff` in the target repo to inspect.

## Edge Cases

- **`jq` missing.** The script requires `jq` for parsing and merging. Install
  with `brew install jq` (or your package manager).
- **JSONC with non-standard syntax.** The comment stripper handles `//` and
  `/* … */`. Trailing commas are not handled — if the existing file has them,
  the script reports a parse error and exits without writing. Remove trailing
  commas and re-run.
- **Existing `recommendations` array contains a string we also define.** The
  union de-duplicates by exact string match, so no double entries appear.
- **The user has set a key we also define to a different value.** Ours wins —
  this is the explicit design. If a user customization needs to survive,
  remove that key from `assets/<editor>/settings.json` in this skill (the
  canonical set).

## Updating the Canonical Configs

The bundled files in `assets/` are the source of truth. Edit them in place and
commit; the next run in any other repo picks up the new content.

When adding a brand-new target file:

1. Drop the file into `assets/<editor>/`.
2. Add a row to the **Canonical Set** table above.
3. Extend the editor block in `scripts/editor-config.sh` (the `apply_<editor>`
   function and the `TARGETS_<EDITOR>` array).

When adding a brand-new editor:

1. Create `assets/<editor>/` with the relevant files.
2. Add the editor to the script's `KNOWN_EDITORS` list and add an
   `apply_<editor>` function.
3. Add it to the **Canonical Set** table and the `AskUserQuestion` options.
