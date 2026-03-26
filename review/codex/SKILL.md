---
name: codex
description: >
  Quick external opinion from Codex CLI. Two modes: ask a specific question with context,
  or review code changes. Use when the user says "ask codex", "codex opinion", "review with codex",
  or when you want a fast second perspective. Lighter and faster than consilium's full review board.
license: MIT
compatibility: Claude Code
allowed-tools: Bash(bash:review/codex/*)
user-invocable: true
arguments: "review"
argument-hint: "[review, or empty for ask mode]"
metadata:
  author: edloidas
---

# Codex — Quick External Opinion

## Purpose

Get a fast external opinion from Codex CLI. This is a lightweight alternative to consilium — one reviewer instead of six, no synthesis step. Use it when you need a quick sanity check or second perspective, not an exhaustive review.

## When to Use

- User says "ask codex", "get codex opinion", "what does codex think", "review with codex"
- `/codex` or `/codex review` invocation
- You want a quick external sanity check on an approach or decision
- You want an independent review of current code changes

## Modes

| Mode | Command | Use case |
|------|---------|----------|
| **ask** (default) | `bash review/codex/scripts/run-codex.sh ask` | Ask a specific question with context |
| **review** | `bash review/codex/scripts/run-codex.sh review [flags]` | Review code changes via `codex exec review` |

## Ask Mode

Use when you have a specific question and want Codex's take.

### Steps

1. **Prepare a focused question with context.** Extract only the relevant code or plan excerpt — don't dump the entire conversation. Keep under 2000 words.

2. **Run the script with a heredoc:**

```bash
bash review/codex/scripts/run-codex.sh ask <<'CODEX_EOF'
## Question
<clear, specific question>

## Context
<relevant code, plan excerpt, or description>
CODEX_EOF
```

3. **Present the output** as Codex's opinion (see Presenting Output below).

## Review Mode

Use when you want Codex to review actual code changes.

### Scope Selection

| Flag | When to use |
|------|-------------|
| `--uncommitted` | There are staged, unstaged, or untracked changes |
| `--base <branch>` | On a feature branch, review changes against the base |
| `--commit <sha>` | Review a specific commit |

If no scope flag is given, the script defaults to uncommitted changes.

### Steps

1. **Determine the scope:**
   - Uncommitted changes exist → `--uncommitted`
   - On a feature branch → `--base main` (or the actual base branch)
   - Reviewing a specific commit → `--commit <sha>`

2. **Run the script** (set Bash timeout to 620000ms — review takes 3-10 min):

```bash
bash review/codex/scripts/run-codex.sh review --uncommitted
```

3. **Present the output** as Codex's review findings.

## Presenting Output

Frame Codex's response as an external opinion, not as authoritative truth:

- **Lead with**: "Codex's take:" or "From Codex:"
- **Don't blindly adopt** Codex's findings — evaluate them with your own context
- **Highlight agreements** if Codex confirms your thinking
- **Flag disagreements** if Codex contradicts your assessment — explain why you agree or disagree
- If the output is empty or an error message, note that Codex couldn't provide input and move on

## Timeouts

- Ask mode: 300s (5 min) default
- Review mode: 600s (10 min) default
- Override by passing a number as the last argument: `bash review/codex/scripts/run-codex.sh ask 120`

## Edge Cases

- **Codex not installed**: script prints a skip message and exits cleanly — don't retry
- **Timeout**: script prints a timeout message — note it to the user and proceed without
- **Empty response**: Codex had nothing to say — move on
- **Large context**: keep ask mode input under 2000 words; for large reviews, prefer review mode which handles diff extraction internally
