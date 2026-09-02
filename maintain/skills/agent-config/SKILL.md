---
name: agent-config
description: >
  Set up and maintain a repository's agent instruction layer — one real root instruction file,
  an AGENTS.md symlink so every agent reads the same document, a comment-convention block, and
  a drift check that catches documented commands, paths, structures, and counts that no longer
  match the repo.
when_to_use: >
  On "init ai config", "set up agent config", "create CLAUDE.md", "make AGENTS.md a symlink",
  "check repo instructions", "are my repo docs still accurate", "sync CLAUDE.md". Also right
  after renaming or removing build scripts, moving directories the instruction file names,
  changing build tooling, or changing a count it documents.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Read Edit Glob Grep AskUserQuestion Bash(bash:*) Bash(git status:*) Bash(git diff:*) Bash(jq:*) Bash(ls:*)
argument-hint: "[init|check|apply]"
metadata:
  author: edloidas
---

# Agent Config

**Local writes only.** `init` and `apply` create or edit files and symlinks inside the target
repo; nothing is staged, committed, pushed, or sent to a remote service. `check` is read-only.
No user-level file is read or written (step 2).

## Purpose

A repository's agent layer is one document read by many agents under different filenames.
This skill establishes that layout and then keeps the document honest:

- **Init** — establish the file-and-symlink layout in **Canonical Layout**.
- **Check** — find documented commands, paths, directory structures, and counts that have
  drifted from the actual repo.

It never seeds an ambient rules directory. Code-shaped conventions are applied on demand by
`code-cleanup` and the `audit/` skills; only the comment block below is cheap enough to live
in always-loaded instructions.

## Asking the User

Every question in this skill is written as `AskUserQuestion` options. Use that tool where
the host offers it, or the host's nearest structured-choice equivalent. Where the host has
neither, ask the same question in normal chat as a numbered list of 2–5 options —
recommended first, one short line of description each — and wait for the user to reply
with a number.

## Arguments

| Argument | Behavior                                                                 |
| -------- | ------------------------------------------------------------------------ |
| _(none)_ | Inspect, report, then ask what to do                                     |
| `init`   | Establish the layout: instruction file, symlinks, comment block          |
| `check`  | Drift report only — never modify anything                                |
| `apply`  | Report drift and apply the fixable findings without re-confirming each   |

`init` runs steps 1-4 and 7. `check` runs steps 1, 5. `apply` runs steps 1, 5-7. With no
argument, run steps 1 and 5, then ask which half the user wants.

## Requirements

The bundled script needs only `bash`, `ln`, and `readlink` — no external dependency. The
drift check reads `package.json` with `jq`; without `jq`, parse it with `grep`/`sed` and say
that command detection is best-effort. Gradle and Make task names come from
`gradle tasks --quiet` and `make -qp`, which fall outside `allowed-tools` and will prompt —
both are read-only, so approve them or skip the Commands category and say so in the report.

## Auto-Activation

Trigger phrases live in `when_to_use`. When activating on your own initiative rather than
on a request — right after build scripts, directory names, tooling, or documented counts
changed — always run `check` first and never apply without showing the report.

## Canonical Layout

One real file; everything else is a relative symlink to it.

| Path                              | Read by                                  | Required |
| --------------------------------- | ---------------------------------------- | -------- |
| `CLAUDE.md`                       | Claude Code                              | canonical |
| `AGENTS.md`                       | Codex, OpenCode, pi, and other agents on the AGENTS.md convention | yes |
| `GEMINI.md`                       | Gemini CLI                               | opt-in   |
| `.github/copilot-instructions.md` | GitHub Copilot                           | opt-in   |

`CLAUDE.md` is the default canonical file because it is the one filename no other host
claims, which keeps the symlink direction unambiguous. **If the repo already has a real
`AGENTS.md` and no `CLAUDE.md`, leave that direction alone** and link `CLAUDE.md` at it
instead — flipping an existing arrangement churns history for nothing.

Symlinks, never copies. Two copies drift the moment one is edited, and no agent will tell
you which one it read.

## Workflow

### 1. Inspect before writing anything

```bash
bash <skill-dir>/scripts/agent-config.sh status
```

Exit codes: `0` consistent, `2` no canonical file (or two competing ones), `3` drift found.

Also note whether the repo is a git repository, what build system it uses, and whether an
instruction file already carries real content. Report present / missing / drifted before
proposing a single edit, and end the phase with one line naming the state:

```
Canonical: CLAUDE.md (real, 214 lines) · AGENTS.md: missing · GEMINI.md: absent (opt-in) · git: yes · build: pnpm
```

### 2. Establish the instruction file

- **Missing** — draft a minimal file from `assets/instructions-skeleton.md`, scoped to what
  this repo actually is. Fill it from evidence: the build file, the directory layout, the
  existing README. Delete every skeleton section the repo does not need. A short accurate
  file beats a complete-looking one.
- **Exists** — leave the prose alone. It is the author's, and the built-in `/init` already
  covers writing one from scratch. Move to step 3.

Never write to `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, or any other user-level file.

### 3. Wire the symlinks

```bash
bash <skill-dir>/scripts/agent-config.sh link AGENTS.md --dry-run
bash <skill-dir>/scripts/agent-config.sh link AGENTS.md
```

Add `GEMINI.md` or `.github/copilot-instructions.md` only when the user says the repo is
used with those agents. Each unused link is one more file to explain.

Flags: `--canonical <file>` picks the real file explicitly, `--force` moves a conflicting
regular file to `<name>.bak` first. Without `--force` the script refuses to touch a regular
file and tells you to merge it by hand — that is the safe default, since such a file usually
holds instructions someone wrote.

If the script reports **both `CLAUDE.md` and `AGENTS.md` are regular files**, stop and ask
which is authoritative. Then merge the other into it and re-run with `--canonical`.

### 4. Add the comment block

Insert `assets/comments.md` into the instruction file verbatim, as its own `## Comments`
section, if and only if:

- the repo has source files using `//` line comments (or the block is adapted to the
  language's line-comment marker), **and**
- the file does not already document comment conventions.

If it already has a comment section, report the difference and let the user decide. Do not
merge two opinionated blocks.

This block is the one ambient rule that survived: comment prefixes are a local convention a
model cannot infer, and they are worth a handful of lines in every session.

### 5. Run the drift check

Read `references/drift-checks.md` and follow it. In short: parse the file into sections,
keep only the ones making structural claims, collect the matching ground truth, classify
each finding, report grouped by section with line numbers, and close with the summary line
that reference defines.

In `check` mode the run ends there. Do not apply a finding, and do not offer to.

### 6. Apply

The report from step 5 is on screen before the first edit. Apply only `STALE`,
`COUNT_MISMATCH`, and `PATH_MISSING` findings, plus `RENAMED` ones the user confirmed.
`INFORMATIONAL` findings are reported and never applied — deciding what deserves documenting
belongs to the author.

Edit mechanic: one targeted edit per finding, never a whole-file rewrite of the instruction
file. Change the reference; leave the surrounding prose, ordering, and whitespace byte-identical.

End with one line: `Applied 3 of 4 findings (1 stale, 1 count, 1 path); 1 informational left`.

### 7. Verify

Re-run `status`, then `git status` and `git diff` so the user sees exactly what changed. A
new symlink shows up in `git diff` as a mode `120000` entry — that is correct, not a
mistake.

Then stop. Do not stage or commit, and do not run `editor-config` or `repo-hardening` off the
back of this run — they are separate decisions (**Adjacent Skills**).

## Adjacent Skills

- `editor-config` owns `.zed` / `.vscode` and is a separate decision — mention it as a
  follow-up when this skill has just initialized a repo, but do not run it implicitly.
- `repo-hardening` owns GitHub-side settings. Unrelated to the instruction layer.
- `skill-audit`, `ci-audit`, and the rest of `audit/` own quality judgments. This skill only
  checks factual agreement between the instruction file and the repo.

## Edge Cases

- **No instruction file and no `init` intent.** In `check` mode, report that there is
  nothing to check and offer `init`. Do not create a file in check mode.
- **Non-git directory.** The layout still works; skip the `git status` verification and say
  so.
- **`AGENTS.md` is a copy, not a link.** The common failure mode. Diff it against the
  canonical file first: if they agree, replace it with a symlink; if not, the divergence is
  content someone wrote — show the diff and ask before collapsing it.
- **A host that reads a directory, not a file.** `.cursor/rules/`, `.claude/rules/`, and
  friends are out of scope. Report them if present, leave them untouched.
- **Symlinks on Windows checkouts.** A repo cloned without symlink support materializes
  `AGENTS.md` as a text file containing the target path. If a one-line file whose content is
  a path shows up, that is the cause — say so instead of treating it as a duplicate.
- **Monorepos.** This skill handles the repo root. Package-level instruction files are the
  author's business.
