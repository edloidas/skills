---
name: claude
description: >
  Quick external opinion from Claude Code CLI. Two modes: ask a specific question with context,
  or review code changes. Use when the user says "ask claude", "claude opinion", "review with claude",
  or when you want a fast second perspective from a different model. Lighter and faster than a full
  review board. The mirror of the `codex` skill — run it from a non-Claude host.
license: MIT
compatibility: Codex, OpenCode, Pi
allowed-tools: Bash(bash:assist/skills/claude/*) Write(*/claude-*)
disable-model-invocation: true
user-invocable: true
argument-hint: "[review, or empty for ask mode]"
metadata:
  author: edloidas
---

# Claude — Quick External Opinion

## Purpose

Get a fast external opinion from the Claude Code CLI. This is the cross-model counterpart to the
`codex` skill: run it from Codex, OpenCode, or pi to get a perspective from a different model
family. One reviewer, no synthesis step — a quick sanity check, not an exhaustive review.

Pointless inside Claude Code — calling Claude from Claude adds no independent perspective, so use
the `codex` skill there instead. Claude Code's plugin loader auto-discovers every skill in the
`assist` group and does not read `compatibility`, so `/claude` still appears there; the
`disable-model-invocation: true` above keeps Claude from reaching for it on its own.

## When to Use

- User says "ask claude", "get claude's opinion", "what does claude think", "review with claude"
- `/claude` or `/claude review` invocation
- You want a quick external sanity check on an approach or decision
- You want an independent review of current code changes

## Modes

| Mode | Command | Use case |
|------|---------|----------|
| **ask** (default) | `bash assist/skills/claude/scripts/run-claude.sh ask` | Ask a specific question with context |
| **review** | `bash assist/skills/claude/scripts/run-claude.sh review [flags]` | Review code changes from a diff |

## Ask Mode

Use when you have a specific question and want Claude's take.

### Steps

1. **Prepare a focused question with context.** Extract only the relevant code or plan excerpt —
   don't dump the entire conversation. Keep under 2000 words.

2. **Resolve the temp directory** (run once, reuse for all files in this session):
   ```bash
   bash assist/skills/claude/scripts/resolve-tmp.sh
   ```
   Use the output as `<TMP>` in subsequent file paths.

   Also pick a run id `<ID>` once and reuse the same literal string for every file in this run —
   a short token such as the current `YYYYMMDD-HHMMSS`. Its only job is to keep concurrent runs
   from overwriting each other's files.

3. **Write the question to a temp file** using a file-write tool (not a Bash heredoc — heredocs
   with markdown headers trip security heuristics on some hosts).
   Write to `<TMP>/claude-<ID>-question.md`:
   ```
   ## Question
   <clear, specific question>

   ## Context
   <relevant code, plan excerpt, or description>
   ```

4. **Run the script with the file path:**

```bash
bash assist/skills/claude/scripts/run-claude.sh ask <TMP>/claude-<ID>-question.md
```

5. **Present the output** as Claude's opinion (see Presenting Output below).

## Review Mode

Use when you want Claude to review actual code changes.

### Scope Selection

| Flag | When to use |
|------|-------------|
| `--uncommitted` | There are staged or unstaged changes |
| `--base <branch>` | On a feature branch, review changes against the base |
| `--commit <sha>` | Review a specific commit |

If no scope flag is given, the script defaults to uncommitted changes.

### Steps

1. **Determine the scope:**
   - Uncommitted changes exist → `--uncommitted`
   - On a feature branch → `--base main` (or the actual base branch)
   - Reviewing a specific commit → `--commit <sha>`

2. **Run the script** (review takes 3-10 min). Pass `540` so the script's own
   timer fires first and can print its timeout message, and set the Bash timeout to its
   600000ms maximum:

```bash
bash assist/skills/claude/scripts/run-claude.sh review --uncommitted 540
```

3. **Present the output** as Claude's review findings.

## Presenting Output

Frame the response as an external opinion, not as authoritative truth:

- **Lead with**: "Claude's take:" or "From Claude:"
- **Don't blindly adopt** the findings — evaluate them with your own context
- **Highlight agreements** if Claude confirms your thinking
- **Flag disagreements** if Claude contradicts your assessment — explain why you agree or disagree
- If the output is empty or an error message, note that Claude couldn't provide input and move on

## Timeouts

- Ask mode: 300s (5 min) default
- Review mode: 600s (10 min) default
- Override by passing a number as the last argument: `bash assist/skills/claude/scripts/run-claude.sh ask 120`

## Edge Cases

- **Claude Code CLI not installed**: script prints a skip message and exits cleanly — don't retry
- **Timeout**: script prints a timeout message — note it to the user and proceed without
- **Empty response**: Claude had nothing to say — move on
- **Large context**: keep ask mode input under 2000 words; for large reviews, prefer review mode
  which handles diff extraction internally
