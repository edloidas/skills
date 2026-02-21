---
name: claude-md-sync
description: >
  Detect and fix stale references in a project's root CLAUDE.md.
  Compares documented commands, directory structures, file paths, and counts
  against actual project state. Use when the user asks to sync or check CLAUDE.md,
  or auto-activate after modifying package.json scripts, renaming directories,
  or changing build configuration.
license: MIT
compatibility: Claude Code
allowed-tools: Read Edit Glob Grep Bash AskUserQuestion
user-invocable: true
arguments: "mode"
argument-hint: "[check|apply]"
metadata:
  author: edloidas
---

Detect and fix stale references in a project's root CLAUDE.md — commands, paths, directory structures, and counts that have drifted from the actual project state.

## Arguments

| Argument | Description                                                   |
| -------- | ------------------------------------------------------------- |
| _(none)_ | Interactive — show drift report, ask before applying fixes    |
| `check`  | Report only, do not modify CLAUDE.md                          |
| `apply`  | Apply fixes without confirmation (still asks for ambiguous cases) |

## When to Use

**Manual triggers:**
- "Sync CLAUDE.md", "check CLAUDE.md", "update CLAUDE.md"
- "Are my docs up to date?", "validate project docs"

**Auto-activation — run in check mode when:**
- You just renamed, added, or removed scripts in `package.json`, `Makefile`, etc.
- You just renamed or moved directories referenced in CLAUDE.md
- You just changed build configuration (added/removed tools, changed output paths)
- You just added or removed skills, plugins, or tools documented in CLAUDE.md

When auto-activating, always run in **check** mode first. Only apply after showing the report and getting user confirmation.

## Steps

### 1. Load CLAUDE.md

Read the **project-level** CLAUDE.md (root of the working directory). Never touch the global `~/.claude/CLAUDE.md`.

If no CLAUDE.md exists at the project root, report that and stop.

Parse the file into sections by Markdown headers (`#`, `##`, `###`, etc.). Track line numbers for each section — you'll need them for the report.

### 2. Identify Structural Sections

Scan section headers and content for structural references. A section is "structural" if it documents any of the following:

| Category       | Header keywords                                    | Content indicators                                  |
| -------------- | -------------------------------------------------- | --------------------------------------------------- |
| **Commands**   | scripts, commands, tasks, npm, pnpm, make, gradle  | Backtick-wrapped commands, `npm run`, `pnpm`, `make` |
| **Structure**  | structure, directory, tree, layout, organization    | Tree-like ASCII art, indented file listings          |
| **Paths**      | paths, files, configuration, config                | File paths with extensions, relative paths           |
| **Build**      | build, tooling, stack, dependencies, tech           | Tool names, bundler references, compiler flags       |
| **Counts**     | _(any section)_                                    | Phrases like "5 skills", "3 packages", "12 modules"  |

Sections that don't match any category are skipped entirely.

### 3. Collect Project State

Detect the build system by checking for these files at the project root:

| File                        | System    | Commands source                        |
| --------------------------- | --------- | -------------------------------------- |
| `package.json`              | npm/pnpm  | `scripts` object keys via `jq`         |
| `build.gradle` / `build.gradle.kts` | Gradle | Task names via `gradle tasks --quiet`  |
| `Makefile`                  | Make      | Target names via `make -qp`            |
| `go.mod`                    | Go        | N/A (no script registry)               |
| `Cargo.toml`               | Cargo     | N/A (standard commands)                |
| `pyproject.toml`            | Python    | `[project.scripts]` section            |

For each structural section found in Step 2, collect the corresponding ground truth:

- **Commands** — list of actual script/task names from the build system
- **Structure** — `ls` or `tree` output for referenced directories (depth-limited)
- **Paths** — `Glob` to verify each referenced file path exists
- **Build** — check that referenced tools/configs are present
- **Counts** — count actual items (scripts, directories, files, skills, etc.)

### 4. Analyze Drift

Compare CLAUDE.md content against collected state. Classify each finding:

| Class              | Meaning                                                     | Action in apply mode        |
| ------------------ | ----------------------------------------------------------- | --------------------------- |
| `STALE`            | Documented item no longer exists in the project             | Remove the reference        |
| `RENAMED`          | Item exists under a different name (fuzzy match)            | Ask user to confirm, then update |
| `COUNT_MISMATCH`   | A documented count doesn't match the actual count           | Update the number           |
| `PATH_MISSING`     | A referenced file path doesn't exist                        | Remove or ask user          |
| `INFORMATIONAL`    | New item exists in project but is not documented            | Report only — never auto-add |

**INFORMATIONAL items are never applied.** The skill only updates or removes existing content. Adding new documentation is the author's responsibility.

### 5. Report

Present findings as a markdown report grouped by section:

```markdown
## CLAUDE.md Drift Report

### Section: "## Available Scripts" (lines 45–62)

| # | Class          | Reference          | Actual                | Note                        |
|---|----------------|--------------------|-----------------------|-----------------------------|
| 1 | STALE          | `npm run deploy`   | _(not found)_         | Script removed              |
| 2 | COUNT_MISMATCH | "8 scripts"        | 6 scripts             | 2 scripts were removed      |
| 3 | INFORMATIONAL  | _(not documented)_ | `npm run typecheck`   | New script, not in CLAUDE.md |

### Section: "## Project Structure" (lines 12–30)

| # | Class        | Reference      | Actual          | Note                  |
|---|--------------|----------------|-----------------|-----------------------|
| 1 | PATH_MISSING | `src/legacy/`  | _(not found)_   | Directory removed     |
| 2 | RENAMED      | `src/utils/`   | `src/lib/`      | Possible rename       |

### Summary

- 2 fixable issues (STALE, COUNT_MISMATCH, PATH_MISSING)
- 1 informational (new items not in CLAUDE.md)
- 1 requires confirmation (RENAMED)
```

If no drift is found, report that CLAUDE.md is in sync and stop.

If the mode is `check`, stop after the report.

### 6. Apply Fixes

For each fixable finding, apply a **surgical edit** — change only the specific reference, not the surrounding text:

- **STALE** — remove the line or list item containing the stale reference. If it's in a table row, remove the row. If removing it leaves an empty section, leave the section header (the author can decide to remove it).
- **COUNT_MISMATCH** — update only the number in the text. E.g., change "8 scripts" to "6 scripts".
- **PATH_MISSING** — remove the reference. If the path appears in a tree/ASCII structure, remove that line and fix indentation.
- **RENAMED** — ask the user to confirm the rename before applying. Show the old and new names. If confirmed, replace the old name with the new one everywhere in CLAUDE.md.

Use the `Edit` tool for all modifications. Never rewrite entire sections — preserve the author's formatting, prose style, and ordering.

After applying, re-read CLAUDE.md and confirm the fixes look correct.

## Edge Cases

- **No CLAUDE.md** — report "No CLAUDE.md found at project root" and stop.
- **No structural sections** — report "CLAUDE.md has no structural references to verify" and stop.
- **Code blocks with examples** — content inside fenced code blocks (` ``` `) that looks like commands or paths may be examples, not actual references. Look for surrounding context ("example", "e.g.", "for instance") and skip those. When unsure, classify as INFORMATIONAL.
- **Monorepos** — if CLAUDE.md references paths in sub-packages, verify relative to the project root, not the sub-package.
- **Global CLAUDE.md** — never read or modify `~/.claude/CLAUDE.md`. This skill only operates on the project-level file.
- **Template placeholders** — strings like `<your-name>`, `YOUR_TOKEN`, `TODO` are intentional placeholders, not stale references. Skip them.
