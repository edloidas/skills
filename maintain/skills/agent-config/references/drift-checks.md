# Drift Checks

How to tell whether an instruction file still describes the repository it sits in. Read
this when running the **check** half of `agent-config`.

## 1. Find the structural sections

Parse the instruction file into sections by Markdown heading, tracking line numbers for the
report. A section is *structural* — worth verifying — only if it documents one of these:

| Category      | Heading keywords                                   | Content indicators                                   |
| ------------- | -------------------------------------------------- | ---------------------------------------------------- |
| **Commands**  | scripts, commands, tasks, npm, pnpm, make, gradle  | Backtick-wrapped commands, `npm run`, `pnpm`, `make` |
| **Structure** | structure, directory, tree, layout, organization   | Tree-like ASCII art, indented file listings          |
| **Paths**     | paths, files, configuration, config                | File paths with extensions, relative paths           |
| **Build**     | build, tooling, stack, dependencies, tech          | Tool names, bundler references, compiler flags       |
| **Counts**    | _(any section)_                                    | Phrases like "5 skills", "3 packages", "12 modules"  |

Sections matching none of these are prose and are skipped entirely. Never rewrite prose.

## 2. Collect ground truth

Detect the build system at the repo root:

| File                                | System   | Command source                        |
| ----------------------------------- | -------- | ------------------------------------- |
| `package.json`                      | npm/pnpm | `scripts` object keys via `jq`        |
| `build.gradle` / `build.gradle.kts` | Gradle   | Task names via `gradle tasks --quiet` |
| `Makefile`                          | Make     | Target names via `make -qp`           |
| `pyproject.toml`                    | Python   | `[project.scripts]`                   |
| `go.mod`, `Cargo.toml`              | Go, Rust | No script registry — standard commands |

Then, per structural section:

- **Commands** — the actual script/task names from the build system
- **Structure** — depth-limited directory listing for each referenced directory
- **Paths** — existence check for every referenced path
- **Build** — presence of each referenced tool or config file
- **Counts** — the real count of whatever is being counted

## 3. Classify

| Class            | Meaning                                          | Action when applying            |
| ---------------- | ------------------------------------------------ | ------------------------------- |
| `STALE`          | Documented item no longer exists                 | Remove the reference            |
| `RENAMED`        | Exists under a different name (fuzzy match)      | Confirm with the user, then update |
| `COUNT_MISMATCH` | A documented count is wrong                      | Update the number only          |
| `PATH_MISSING`   | A referenced path does not exist                 | Remove, or ask                  |
| `INFORMATIONAL`  | Exists in the repo but is not documented         | Report only — never auto-add    |

`INFORMATIONAL` is never applied. This skill updates and removes existing content; deciding
what deserves to be documented is the author's call.

## 4. Report

Group findings by section, with line numbers:

```markdown
### Section: "## Commands" (lines 45–62)

| # | Class          | Reference          | Actual              | Note                |
|---|----------------|--------------------|---------------------|---------------------|
| 1 | STALE          | `npm run deploy`   | _(not found)_       | Script removed      |
| 2 | COUNT_MISMATCH | "8 scripts"        | 6 scripts           | 2 were removed      |
| 3 | INFORMATIONAL  | _(not documented)_ | `npm run typecheck` | New script          |

### Section: "## Repository Structure" (lines 71–96)

| # | Class        | Reference        | Actual        | Note                     |
|---|--------------|------------------|---------------|--------------------------|
| 4 | PATH_MISSING | `src/legacy/`    | _(not found)_ | Deleted in the v3 layout |

4 findings: 3 fixable, 1 informational, 0 need confirmation.
```

Close with that summary line, in that shape, with the real counts.

## 5. Apply

Per-class actions; the skill body's step 6 states the edit mechanic.

- **STALE** — drop the line, list item, or table row. Leave an emptied section heading in
  place; removing it is an authoring decision.
- **COUNT_MISMATCH** — change the number and nothing else.
- **PATH_MISSING** — drop the reference; fix indentation if it sat inside an ASCII tree.
- **RENAMED** — confirm before applying, then replace the old name everywhere in the file.

## Edge cases

- **Examples, not references.** Content inside fenced blocks near "example", "e.g.", or
  "for instance" is illustrative. Skip it, or classify as `INFORMATIONAL` when unsure.
- **Template placeholders.** `<your-name>`, `YOUR_TOKEN`, `TODO` are intentional. Skip.
- **Monorepos.** Verify paths relative to the repo root, not the sub-package.
- **Generated trees.** A directory the repo documents as generated may legitimately be
  absent from a fresh clone. Check for it in `.gitignore` before calling it `PATH_MISSING`.
- **Global instruction files.** Never read or modify `~/.claude/CLAUDE.md`,
  `~/.codex/AGENTS.md`, or any other user-level file. This skill is repo-scoped.
