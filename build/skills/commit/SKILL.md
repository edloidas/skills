---
name: commit
description: >
  Stage safe changes on the current branch and create a single conventional commit. Skips
  generated artifacts, caches, logs, and editor cruft. Accepts hints like "only staged",
  "relevant", or "amend".
when_to_use: >
  When current work should be committed quickly — "commit this", "commit my changes", "amend
  that". Not for pushing, opening PRs, or splitting work across several commits.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
argument-hint: "[instructions]"
allowed-tools: Read Grep Bash(git:*) Bash(gh issue view:*) Agent Skill
metadata:
  author: edloidas
---

# commit

Fast path to commit. Gather the state below in one batch, reason about file safety
and scope, then commit.

## Arguments

`$ARGUMENTS` may be empty or contain directives. Recognize and combine:

| Directive                     | Behavior                                                                               |
| ----------------------------- | -------------------------------------------------------------------------------------- |
| `only staged` / `staged only` | Stage nothing. Commit the existing index as it stands.                                 |
| `relevant` / `scoped`         | Stage only files that fit the current task's scope; leave unrelated tweaks out.        |
| `amend`                       | Use `git commit --amend --no-edit` after staging. Do not rewrite the existing message. |
| `no trailer`                  | Never append a `Co-Authored-By` trailer, even if the repo uses them.                   |
| anything else                 | Treat as a message hint or additional constraint — see step 5.                          |

## Current state

Gather this before anything else, in one batch where the host allows it. Every
section below reasons off this output — do not re-run these commands later.

| Command                     | Used for                                  |
| --------------------------- | ----------------------------------------- |
| `git branch --show-current` | issue-number suffix on the title          |
| `git status --short`        | what is untracked vs. modified vs. staged |
| `git diff --stat`           | unstaged size and file list               |
| `git diff --cached --stat`  | staged size and file list                 |
| `git log --oneline -5`      | recent title style                        |
| `git log -1 --format='%B'`  | trailer style of the last commit          |

When the batch returns, print one line: `State: <N> staged, <M> unstaged, <K> untracked
on <branch>`.

Then read the repo's own commit convention, if it has one:

```bash
grep -B 1 -A 10 -i "^##.*commit\|commit message\|commit format\|conventional commit" \
  CLAUDE.md AGENTS.md .github/CONTRIBUTING.md 2>/dev/null | head -80 \
  || echo "(none found — use conventional commits)"
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

## Heavy-diff delegation

The `git diff --stat` output from **Current state** shows the size. Handle the common
case in-thread. Only delegate when the staged OR unstaged diff exceeds
**~500 changed lines** or **~20 files** AND you need actual diff content
(not just stats) to decide scope, classify files, or compose the body.

Delegation is an optimization, not a requirement. On a host with no subagent facility, read
the diff in-thread instead — in chunks if it is large — and carry on. Nothing else in this
skill depends on the delegation step.

When delegating, dispatch one subagent:

- A read-only subagent is enough — it inspects the diff and answers, nothing more.
- The subagent has no conversation history — pass the exact `git diff` output (or the
  subset you need) in the prompt.
- Ask a single narrow question. Good shapes:
  - *"From this diff, which files belong to scope: `<scope from $ARGUMENTS>`? Return file paths only."*
  - *"Summarize the distinct changes in this diff as 3-5 past-participle bullets, no prose."*
- Use the returned answer directly. Do not ask the subagent to write the
  commit message — that stays in-thread with full project context.

Do not delegate for small diffs. The round-trip is slower than reading the
diff inline, and the main thread already has the conventions context.

## Steps

1. Parse `$ARGUMENTS`.
2. If `only staged`: go to step 4.
3. Stage safe files with `git add <path>`. Apply the rules above.
   - If `relevant`: from the unstaged diff, pick only files whose changes fit
     the scope described in `$ARGUMENTS` or obvious from the combined diff;
     leave the rest.
4. Look at the staged diff (you already have `git diff --cached --stat` from
   **Current state**; read `git diff --cached` only if the message needs detail
   beyond the stat).
   If nothing is staged, stop and tell the user.
5. Compose the commit message:
   - Single-line title, ≤72 chars, `<type>: <description>`.
   - Types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `style`, `ci`.
   - Follow the project convention from **Current state** when present.
   - If the current branch is `issue-<N>`, the title is `<Issue Title> #<N>`, matching
     `issue-flow` — fetch it with `gh issue view <N> --json title --jq .title`. Where `gh`
     fails, fall back to `<type>: <description> #<N>` and say so.
   - A hint in `$ARGUMENTS` — whatever the Arguments table did not match — steers the
     message, not the staging: let it shape the title's description, and pass it
     verbatim to `commit-summary` so the body reflects it too. It narrows what the
     message leads with; it never drops changes the commit contains.
   - Body: invoke the `commit-summary` skill and use what it returns. Where the host
     cannot chain skills or it is not installed, write past-tense paragraphs wrapped at 80
     answering, from the code rather than the diff, what forced the change, which call
     paths reach it, how it failed, and what breaks on update, dropping any with no answer
     and naming no hash or path a command did not return. A rename or regenerated tree gets
     two or three mechanical lines. A project convention from **Current state** overrides both.
   - Attribution: this step runs the `git commit`, so it is the last place a
     footer can be caught. Read the assembled message and **remove** any
     "Drafted with AI" or "Generated with" line, session or transcript link,
     `<sub>` line, trailing `---` rule, badge, promotional line, or
     `Co-Authored-By` trailer crediting an assistant — wherever it came from,
     including a body `commit-summary` returned and a message being amended.
     Add none either, and do not copy one forward from the previous commit: a
     trailer already in the log is not licence to repeat it. A *human*
     co-author trailer is fine where the repo's convention asks for one.
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
   create a new commit (do not amend unless the user asked).
8. Final output: one line — `Committed <short-sha> on <branch>: <title>` —
   followed by a short `skipped: …` list if anything was left out.
9. Then stop. Do not push, do not open a PR, do not switch branches, do not split the
   work into a second commit, and do not rewrite history beyond the single
   `--amend --no-edit` above.

