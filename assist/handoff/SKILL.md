---
name: handoff
description: >
  Compact the current conversation into a handoff so a fresh agent (or
  future-you) can pick up the work cold. Use when the user asks to hand off,
  summarize the session, or prepare context for the next session. With `doc`,
  `document`, or `--doc` keyword, writes a per-project handoff file and prints
  only the path and a copy-paste shortcut to start the next session.
license: MIT
compatibility: Claude Code
argument-hint: "[doc] [focus...]"
allowed-tools: Read Write Bash Glob Grep
metadata:
  author: edloidas
---

# Handoff — Pass The Baton

Summarize the current in-context conversation into a handoff a fresh agent (or
future-you) can pick up without re-reading the session. Two output modes:

- **Inline mode** (default) — render the handoff as Markdown directly in chat.
  Nothing else. The output IS the handoff.
- **Doc mode** — write the handoff to a per-project file and print only two
  lines in chat: a link to the file and a copy-paste shortcut for the next
  session.

## Hard Rules

1. **No preamble.** Do not say "Here's the handoff" or summarize what you're
   about to write. The output is the handoff itself.
2. **No duplication.** If a fact is captured in a committed file, plan, PRD,
   issue, PR, or diff, link or path-reference it. Do not restate it.
3. **No fabrication.** Every fact in the handoff comes from the in-context
   conversation, files you read this session, or tool output you observed.
   Don't invent decisions, file paths, or commit messages.
4. **Redact secrets.** Never include API keys, tokens, passwords, PII, or
   credentials visible in the conversation. If a secret is load-bearing
   context, reference where it lives (env var name, 1Password item, secret
   manager path) instead of pasting it.
5. **Empty sections never render.** Pick from the section pool only what
   applies. If only Goal and Next step exist, that's the whole handoff.

## Argument parsing

The skill accepts a free-form argument string (`$ARGUMENTS`). Parse it once:

1. **Mode keyword.** If the tokens contain any of `doc`, `document`, or
   `--doc` (case-insensitive, as a standalone token), switch to doc mode and
   remove that token. Otherwise inline mode.
2. **Focus.** The remaining tokens, joined with spaces, become the **focus**
   string. The focus slants what the handoff emphasizes and seeds the
   filename slug. Empty focus is fine — the handoff still works.

Examples:

| Invocation                         | Mode   | Focus                |
| ---------------------------------- | ------ | -------------------- |
| `/handoff`                         | inline | _(none)_             |
| `/handoff fix login bug`           | inline | `fix login bug`      |
| `/handoff doc`                     | doc    | _(none)_             |
| `/handoff doc fix login bug`       | doc    | `fix login bug`      |
| `/handoff fix the login bug --doc` | doc    | `fix the login bug`  |

## Section pool

Pick from this pool. Include a section only if you actually have content for
it from the conversation. Order them as listed.

**Core (almost always present)**

- **Goal** — what the user wants, in one or two sentences. Top-level intent.
- **Where we are** — project path, branch, working-tree state (clean / dirty /
  staged), last commit hash + subject. One short paragraph or a tight list.
- **What's been decided** — design choices, assumptions adopted, scope cuts.
  Prevents the next session from re-litigating settled questions.
- **Next step** — the specific concrete action the next session should take
  first. What "progress" means from here.

**Conditional (only when applicable)**

- **Problem & repro** — bug sessions: failure, reproduction steps, expected
  vs actual.
- **Findings** — discoveries from this session that aren't yet captured in
  code or commits.
- **Tried & ruled out** — paths explored and dropped, with the reason. Stops
  the next agent re-walking dead ends.
- **Open questions** — gaps the previous session didn't close.
- **Gotchas** — non-obvious constraints learned the hard way.
- **References** — paths and URLs to issues, PRs, plans, ADRs, diffs.
  Pointers, not copies.
- **Suggested skills** — by name (e.g. `superpowers:systematic-debugging`,
  `dev:gh-actions-debug`). One short line each — what the next agent might
  reach for, why.

**Deliberately not standalone sections**

- "Impact" — folds into Goal if it matters.
- "Changes made" — that's what `git log` / `git diff` is for. Reference the
  branch and commits under Where we are / References.
- "Summary of what we did" — narrative recap of the session is noise. The
  core sections already say where we ended up.

## Inline mode

Render the handoff directly as Markdown in chat. No code-fence wrapper.

Start with:

```
# Handoff

<project-name> · <branch> · <YYYY-MM-DD HH:MM>
```

Then the applicable sections, each as `## Section name` followed by its
content. Do not print a trailing summary, sign-off, or question.

## Doc mode

1. Resolve the encoded cwd: take the absolute working directory and replace
   every `/` with `-`. Example: `/Users/foo/repo/proj` → `-Users-foo-repo-proj`.
2. Build the filename: `YYYY-MM-DD-HHMM[-slug].md`, local time. Slug is
   derived from the focus string if present:
   - Lowercase, replace non-alphanumeric runs with `-`, trim leading/trailing
     `-`, collapse repeats, cap at ~40 chars. Use the first 4–6 meaningful
     words.
   - Omit the slug entirely if focus is empty.
3. Target path:
   `~/.claude/projects/<encoded-cwd>/handoff/<filename>`
4. Create the `handoff/` directory if needed.
5. On collision (same filename), suffix with `-2`, `-3`, … before `.md`.
6. Write the same Markdown body as inline mode to the file.
7. Print to chat exactly two lines, nothing else:

   ```
   [<filename>](<absolute-path>)
   Read @<absolute-path> and continue the work.
   ```

   The first line renders as a clickable link in Claude Code; the second is
   the copy-paste shortcut for starting the next session.

## Gathering data

Use only what the in-context conversation already provides plus light,
read-only inspection if needed:

- `git rev-parse --abbrev-ref HEAD` — current branch.
- `git status --short` — working-tree state.
- `git log -1 --oneline` — last commit.
- `basename "$PWD"` — project name for the strap line.

Do not run mutating commands, do not edit code, do not commit. Reading
project files to ground a fact is fine, but only if the conversation pointed
at them — don't go exploring.

## Edge cases

- **Empty session / nothing substantive happened** — exit with one line:
  > **Nothing worth handing off from this session.**
  No file, no Markdown body.
- **Compacted session** — early turns may be invisible. Note this once under
  Goal or in a one-line aside if it materially affects the handoff.
- **Focus argument unrelated to actual session work** — trust the focus as
  the user's framing for the next session, even if the previous session
  drifted. Slant the handoff toward continuing in the focus direction.
- **Multiple intermixed threads in the session** — pick the one the focus
  points at; if no focus, pick the thread the user spent the most recent
  turns on. Mention dropped threads under Open questions only if they're
  load-bearing.
