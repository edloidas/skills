---
name: commit
description: >
  Stage safe changes on the current branch and create a single conventional
  commit. Use when the user wants to quickly commit current work. Skips
  generated artifacts, caches, logs, and editor cruft. Accepts hints like
  "only staged", "relevant", or "amend".
license: MIT
compatibility: Claude Code
model: claude-haiku-4-5-20251001
effort: medium
disable-model-invocation: true
user-invocable: true
argument-hint: "[instructions]"
allowed-tools: Read Grep Bash(git:*)
metadata:
  author: edloidas
---

# commit

Fast path to commit. Inline context is already gathered below — prefer it over
extra tool calls. Reason about file safety and scope, then commit.

## Arguments

`$ARGUMENTS` may be empty or contain directives. Recognize and combine:

| Directive                     | Behavior                                                                               |
| ----------------------------- | -------------------------------------------------------------------------------------- |
| `only staged` / `staged only` | Do NOT stage anything. Commit the existing index.                                      |
| `relevant` / `scoped`         | Stage only files that fit the current task's scope; leave unrelated tweaks out.        |
| `amend`                       | Use `git commit --amend --no-edit` after staging. Do not rewrite the existing message. |
| `no trailer`                  | Never append a `Co-Authored-By` trailer, even if the repo uses them.                   |
| anything else                 | Treat as a message hint or additional constraint.                                      |

## Current state

Branch: !`git branch --show-current`

Status:

```
!`git status --short`
```

Unstaged diff (stat):

```
!`git diff --stat`
```

Staged diff (stat):

```
!`git diff --cached --stat`
```

Last 5 commits:

```
!`git log --oneline -5`
```

Last commit message (for trailer style):

```
!`git log -1 --format='%B'`
```

CLAUDE.md / AGENTS.md commit conventions (if any):

```
!`grep -B 1 -A 10 -i "^##.*commit\|commit message\|commit format\|conventional commit" CLAUDE.md AGENTS.md .github/CONTRIBUTING.md 2>/dev/null | head -80 || echo "(none found — use conventional commits)"`
```

## Staging rules

Source code, docs, and tracked configs are safe by default — don't overthink
them. Focus the skip judgement on generated and machine-specific artifacts.

**Never auto-stage these:**

- Build or incremental artifacts: `*.tsbuildinfo`, `dist/`, `build/`, `out/`, `.next/`, `.turbo/`, `.parcel-cache/`, `coverage/`, `node_modules/`
- Caches and logs: `.cache/`, `*.log`, `logs/`, `npm-debug.log*`, `pnpm-debug.log*`, `yarn-debug.log*`
- OS / editor cruft: `.DS_Store`, `Thumbs.db`, `*.swp`, `*.swo`, `*~`
- Secrets: `.env`, `.env.*` — warn the user if they appear untracked
- Local machine state: `.playwright-mcp/`, `.claude/settings.local.json`, `.vscode/settings.json` unless already tracked

Anything else — use judgement. If a path looks generated (hash suffix, inside a
cache-like dir, editor backup) and is untracked, skip it and list it in the
final report. If ambiguous, ask by skipping and reporting, not by prompting.

Never use `git add .`, `git add -A`, or `git add -f`. Stage with explicit paths.

## Steps

1. Parse `$ARGUMENTS`.
2. If `only staged`: go to step 4.
3. Stage safe files with `git add <path>`. Apply the rules above.
   - If `relevant`: from the unstaged diff, pick only files whose changes fit
     the scope described in `$ARGUMENTS` or obvious from the combined diff;
     leave the rest.
4. Look at the staged diff (`git diff --cached --stat` is already above; read
   `git diff --cached` only if the message needs detail beyond the stat).
   If nothing is staged, stop and tell the user.
5. Compose the commit message:
   - Single-line title, ≤72 chars, `<type>: <description>`.
   - Types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `style`, `ci`.
   - Follow the project convention from the grep block when present.
   - If the current branch is `issue-<N>`, append ` #<N>` to the title.
   - Body only if the diff spans 3+ distinct changes: 2–4 short lines,
     past participle, no bullets.
   - Trailers: only include `Co-Authored-By` if the last commit already uses
     one. Never add promotional footers.
6. Commit:
   ```bash
   git commit -m "$(cat <<'EOF'
   <title>

   <optional body>
   EOF
   )"
   ```
   If `amend` was requested: `git commit --amend --no-edit`.
7. Never pass `--no-verify`. If a pre-commit hook fails: fix the issue, re-stage,
   create a NEW commit (do not amend unless the user asked).
8. Final output: one line — `Committed <short-sha> on <branch>: <title>` —
   followed by a short `skipped: …` list if anything was left out.

## Out of scope

- Pushing, opening PRs, switching branches.
- Splitting into multiple commits.
- Rewriting history beyond a single `--amend --no-edit`.
- Adding files listed in `.gitignore` via `-f`.
