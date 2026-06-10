---
name: rules-sync
description: >
  Sync agent rule files (.claude/rules/, .agents/rules/) in a repo against a
  canonical set bundled with this skill. Detects which side is the real
  directory vs a symlink and writes only to the real one. Overwrites existing
  canonical rules, adds missing canonical rules only when the project actually
  uses the relevant technology (React, Tailwind, Storybook, Radix, Vitest,
  Three.js, TypeScript), and never touches project-specific rule files outside
  the canonical set. Use when initializing rules in a new repo or refreshing
  rules in an existing one.
license: MIT
compatibility: Claude Code, Codex
allowed-tools: Bash Read
user-invocable: true
argument-hint: "[<target-dir>] [--dry-run]"
---

# Rules Sync

## Purpose

Propagate a canonical set of agent rule files into other repos. The skill is the
**source of truth** — its bundled rules in `assets/rules/` are what every target
repo gets. To update the canonical set, edit the files in this skill (or copy
fresh versions from the reference repo) and commit; the next run propagates the
change everywhere else.

## When to Use This Skill

Trigger phrases: "rules sync", "rules-sync", "sync rules", "init rules",
"update rules", "set up rules", "apply rules to this repo".

## Canonical Set

Ten rule files, all stored in `assets/rules/`:

| File | Applies when |
|------|--------------|
| `comments.md` | `tsconfig.json` exists, or `typescript` in `package.json` |
| `typescript.md` | same as above |
| `frontend-structure.md` | `react` or `preact` in deps |
| `react.md` | `react` in deps |
| `radix.md` | `radix-ui` or `@radix-ui/*` in deps |
| `storybook.md` | `@storybook/*` in deps, or `.storybook/` exists |
| `tailwind.md` | `tailwindcss` or `@tailwindcss/*` in deps |
| `testing.md` | `vitest` in deps (rule is Vitest-specific) |
| `three.md` | `three` or `@react-three/*` in deps |
| `kotlin.md` | `.kt` files under `src/`, or `kotlin(...)` plugin in `build.gradle.kts` |

A rule is **applicable** when its detection check passes. Detection runs only
for rules that need to be **added** — rules already present in the target are
always overwritten regardless of detected stack, on the assumption that the user
put them there for a reason.

## Storage Detection

The skill picks the **real directory** between `.claude/rules/` and
`.agents/rules/` and writes only there:

| Layout | Action |
|--------|--------|
| Only `.claude/rules` | Write to `.claude/rules` |
| Only `.agents/rules` | Write to `.agents/rules` |
| `.claude/rules` real, `.agents/rules` is a symlink to it | Write to `.claude/rules` |
| `.agents/rules` real, `.claude/rules` is a symlink to it | Write to `.agents/rules` |
| Both symlinks resolving to the same path | Write to that resolved path |
| Both symlinks resolving to different paths | Refuse (exit 3) |
| Both real, identical contents | Write to `.claude/rules`, note the duplicate |
| Both real, differing contents | Refuse (exit 3) — user must consolidate first |
| Neither exists | **Init mode**: create `.claude/rules/` and a relative symlink `.agents/rules → ../.claude/rules` |

The symlink side is never modified directly — writing to the real directory
naturally propagates to the symlink.

## Sync Algorithm

For each canonical file:

- **Already exists in target** → overwrite (silent; only the file content
  changes, no diff is shown). If contents are identical, mark as `Identical`.
- **Missing in target** → add **only if the applicability check passes**;
  otherwise mark as `Skip`.

For each non-canonical file in the target rules dir:

- **Preserve** — leave it untouched. Examples: `preact.md`, `patterns.md`,
  `structure.md` in `enonic-ui`.

The skill prints a five-line plan summary (`Overwrite`, `Add`, `Identical`,
`Skip`, `Preserve`) and asks for confirmation before writing. Confirmation is
all-or-nothing — there's no per-file gate. To preview without writing, pass
`--dry-run`.

## Workflow

1. **Resolve target.** Default is the current working directory; an explicit
   path can be passed as the first positional argument.
2. **Run the apply script.**

   ```bash
   bash <skill-dir>/scripts/rules-sync.sh [--dry-run] [--yes] [<target-dir>]
   ```

   Flags:
   - `--dry-run` — print the plan and exit
   - `--yes` / `-y` — skip the interactive confirmation
   - `--no-init` — refuse to scaffold a rules directory if neither side exists
3. **Review the plan.** The script prints `Target`, `Mode` or `Rules dir`, and
   the five-bucket plan (`Overwrite`, `Add`, `Identical`, `Skip`, `Preserve`).
4. **Confirm.** Type `y` to apply. Anything else aborts.
5. **Verify.** After apply, the changed files are listed. Run `git status` /
   `git diff` in the target repo to inspect.

## Edge Cases

- **No `package.json`.** Detection falls back to `tsconfig.json` for
  `typescript`/`comments`. Other rules are treated as non-applicable. In init
  mode this means a brand-new repo gets a `.claude/rules/` directory but few or
  no rules — re-run after the project's deps are installed.
- **`jq` missing.** Stack detection silently treats every dependency check as
  false. Install `jq` (`brew install jq`) for accurate detection.
- **Both `.claude/rules` and `.agents/rules` real and divergent.** The script
  refuses to write (exit 3). Pick one as canonical, replace the other with a
  relative symlink (e.g. `rm -rf .agents/rules && ln -s ../.claude/rules
  .agents/rules`), then re-run.
- **Init mode in a repo that already has `.agents/` but no `.agents/rules`.**
  The script creates the `.agents/rules` symlink alongside the real
  `.claude/rules`. If `.agents/rules` already exists as something other than a
  symlink to `.claude/rules`, init mode does not apply (the dir exists, so it
  takes that path).
- **Pre-existing canonical rule that the user customized.** It will be
  overwritten without warning. If a customization needs to survive, rename the
  file (`react-custom.md`) so it falls outside the canonical set and is treated
  as preserved.

## Updating the Canonical Rules

The bundled rules in `assets/rules/` are the source of truth. To refresh them
from the reference repo:

```bash
cp ~/repo/voidvigil/.claude/rules/*.md <skill-dir>/assets/rules/
```

Commit the change in the skills repo. The next `rules-sync` run in any other
repo picks up the new content.

When adding a brand-new canonical rule:

1. Drop the file into `assets/rules/`.
2. Add it to the `RULE_FILES` array in `scripts/rules-sync.sh`.
3. Add an applicability case in the `applies()` function (and a helper like
   `uses_<tech>` if needed).
4. Add a row to the **Canonical Set** table above.

When removing a canonical rule, delete it from `assets/rules/`, the
`RULE_FILES` array, and the `applies()` case. Existing copies in target repos
become "extras" on the next run — they're preserved, not deleted. Remove them
manually in each repo if desired.
