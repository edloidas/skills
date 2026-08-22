---
name: outsider
description: >
  Quick opinion from an agent CLI outside this session. Two modes: ask a specific question with
  context, or review code changes. Picks an installed agent that is not the one running this skill,
  so the answer comes from a different model in a different process. Use when the user says "ask
  codex", "ask claude", "outside opinion", "second opinion", "review with another agent", or when
  you want a fast independent perspective. Lighter and faster than a full review board.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash(bash:*) Write(*/outsider-*)
user-invocable: true
argument-hint: "[review] [agent], or empty for ask mode"
metadata:
  author: edloidas
---

# Outsider — Quick Opinion From Another Agent

## Purpose

Get a fast opinion from an agent CLI running outside this session. One reviewer, no synthesis step
— a sanity check, not an exhaustive review. Use `review:consilium` when you want a board.

The value is structural: the responder shares none of this conversation's context and runs in its
own process, usually on a different model family. Which vendor answers is incidental, which is why
this skill resolves the agent instead of naming one.

## When to Use

- "ask codex", "ask claude", "what would another agent say", "get an outside opinion"
- `/outsider`, `/outsider review`, `/outsider codex review`
- A quick external sanity check on an approach or decision
- An independent review of the current code changes

## Agent Selection

The script picks the agent. Always pass `--host <the agent you are>` — `claude`, `codex`,
`opencode`, or `pi` — so it never asks you to review your own work. Add `--agent <name>` only when
the user named one; that overrides everything, host included.

```bash
bash <skill-dir>/scripts/run-outsider.sh list --host claude
```

`list` prints what is installed and what would be selected, and spends nothing.

Default order is `codex claude opencode pi`, minus the host. A missing CLI is a skip, not a
failure: the script prints why and exits 0. Callers can treat this leg as droppable.

**No model or reasoning level is set by default** — the chosen agent runs on whatever it is already
configured to use. To pin one, or to change the preference order, edit
`~/.config/edloidas/outsider/config` (`OUTSIDER_AGENTS`, `OUTSIDER_MODEL_<AGENT>`,
`OUTSIDER_EFFORT_<AGENT>`, `OUTSIDER_ARGS_<AGENT>`); the same names work as environment variables
and override the file. `references/agents.md` has the full registry, the config keys with examples,
and how to add an agent.

## Ask Mode

1. **Prepare a focused question with context.** Extract only the relevant code or plan excerpt —
   don't dump the conversation. Keep it under 2000 words.

2. **Resolve the temp directory** (once per session):

   ```bash
   bash <skill-dir>/scripts/resolve-tmp.sh
   ```

   Use the output as `<TMP>`. Pick a run id `<ID>` once too — a session identifier the host already
   exposes, or the current `YYYYMMDD-HHMMSS` — and reuse the same literal string for every file in
   this run so concurrent runs don't overwrite each other.

3. **Write the question with a file-write tool**, not a Bash heredoc — heredocs with markdown
   headers trip some hosts' shell security heuristics. Write to `<TMP>/outsider-<ID>-question.md`:

   ```
   ## Question
   <clear, specific question>

   ## Context
   <relevant code, plan excerpt, or description>
   ```

4. **Run it:**

   ```bash
   bash <skill-dir>/scripts/run-outsider.sh ask --host claude <TMP>/outsider-<ID>-question.md
   ```

## Review Mode

Pick the scope first:

| Flag | When |
| ---- | ---- |
| `--uncommitted` | Staged, unstaged, or untracked changes exist (the default) |
| `--base <branch>` | On a feature branch, review against the base |
| `--commit <sha>` | Review one commit |

Review takes 3–10 minutes. Pass `540` so the script's own timer fires first and can print its
timeout message, and set the surrounding command timeout to its maximum (600000ms in Claude Code):

```bash
bash <skill-dir>/scripts/run-outsider.sh review --host claude --uncommitted 540
```

## Presenting Output

The first line of the output is `[outsider] agent: <name>`. **Always say which agent answered** —
the response is not interpretable without it.

- Lead with "Codex's take:", "From pi:", and so on, using the agent the script actually ran
- Don't blindly adopt the findings — evaluate them with your own context
- Highlight agreements; flag disagreements and explain which side you land on and why
- The responder only ever saw what you piped it. Discount findings that are really requests for
  context it could not see
- Empty output or an error line means it had nothing to offer — say so and move on

## Edge Cases

- **No agent installed, or only the host is** — the script says so and exits 0. Don't retry.
- **Timeout** — the script prints a timeout message. Note it and proceed without.
- **Large context** — keep ask mode under 2000 words. For large changes use review mode, which
  extracts the diff itself.

## Notes for Callers

This skill stays model-invocable on every host. The predecessor `claude` skill set
`disable-model-invocation: true` only because calling Claude from Claude was recursive; selection
now handles that structurally, so there is nothing left to suppress.

Other skills invoke this one as a skill, not by script path — a repo-relative path only resolves
inside one checkout.

`review/skills/consilium` still ships its own copy at
`review/skills/consilium/scripts/run-codex.sh`. The decision is to move it
onto this script; the script already accepts `--preamble <file>` to swap in a caller's own prompt,
and stdout can be redirected to consilium's output file. The port is tracked in issue #30, not done
here, because consilium's reviewer is a named board persona with its own prompt and session-keyed
temp files, and rewiring it is not a rename.
