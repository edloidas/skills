---
name: outsider
description: >
  Quick opinion from an agent CLI outside this session — ask a specific question with context,
  or review code changes. Picks an installed agent that is not the one running this skill, so
  the answer comes from a different model in a different process. Lighter and faster than a
  full review board.
when_to_use: >
  On "ask codex", "ask claude", "outside opinion", "second opinion", or "review with another
  agent", and when a fast independent perspective would settle something.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash(bash:*) Write(*/outsider-*)
argument-hint: "[review] [agent], or empty for ask mode"
metadata:
  author: edloidas
---

# Outsider — Quick Opinion From Another Agent

## Purpose

Get a fast opinion from an agent CLI running outside this session. One reviewer, no synthesis step
— a sanity check, not an exhaustive review. Use `review:consilium` when you want a board.

This skill writes one temp file per run — the question — and nothing else. The responder is
launched read-only: it reports, and it does not edit the repo.

The value is structural: the responder shares none of this conversation's context and runs in its
own process, usually on a different model family. Which vendor answers is incidental, which is why
this skill resolves the agent instead of naming one.

## When to Use

- "ask codex", "ask claude", "what would another agent say", "get an outside opinion"
- `/outsider`, `/outsider review`, `/outsider codex review`
- A quick external sanity check on an approach or decision
- An independent review of the current code changes

## Requirements

`timeout` or `gtimeout` must be on PATH — both ship with GNU coreutils. Stock macOS has
neither; `brew install coreutils` provides `gtimeout`. Without one the script skips instead
of running an agent CLI unbounded, because a hung agent would hang the caller's turn.
`run-outsider.sh list` reports it when it is missing.

## Agent Selection

The script picks the agent. Pass `--host <the agent you are>` on every invocation — `claude`,
`codex`, `opencode`, or `pi` — so it never asks you to review your own work. Add `--agent <name>` only when
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
   don't dump the conversation. Keep it under 2000 words; past that, use review mode, which
   extracts the diff itself.

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

4. **Run it**, after printing one line naming the agent that will answer and the wait —
   `Asking codex (ask mode, up to 2 min).`

   ```bash
   bash <skill-dir>/scripts/run-outsider.sh ask --host claude <TMP>/outsider-<ID>-question.md
   ```

### Custom preamble

Both modes prepend a prompt file to whatever you pipe them — `references/prompt.md` for ask,
`references/review-prompt.md` for review. A caller with its own prompt for the responder passes
`--preamble <file>` to swap it:

```bash
bash <skill-dir>/scripts/run-outsider.sh ask --host claude \
  --preamble <caller-skill-dir>/references/its-own-prompt.md <TMP>/outsider-<ID>-question.md
```

The preamble replaces the default entirely, so it has to carry the responder's whole brief —
including its output shape. `review:consilium` uses this for its outside board seat.

## Review Mode

Pick the scope first:

| Flag | When |
| ---- | ---- |
| `--uncommitted` | Staged, unstaged, or untracked changes exist (the default) |
| `--base <branch>` | On a feature branch, review against the base |
| `--commit <sha>` | Review one commit |

Review takes 3–10 minutes. Print one line before it starts, naming the agent, the scope, and the
wait — `Asking codex to review 6 uncommitted files (up to 9 min).` Pass `540` so the script's own
timer fires first and can print its timeout message, and set the surrounding command timeout to
the highest value the host allows:

```bash
bash <skill-dir>/scripts/run-outsider.sh review --host claude --uncommitted 540
```

## Presenting Output

The first line of the output is `[outsider] agent: <name>`. Name that agent in your report — the
response is not interpretable without knowing who gave it.

- Lead with "Codex's take:", "From pi:", and so on, using the agent the script actually ran
- Evaluate the findings against your own context rather than adopting them
- Highlight agreements; flag disagreements and explain which side you land on and why
- The responder only ever saw what you piped it. Discount findings that are really requests for
  context it could not see
- Empty output or an error line means it had nothing to offer — say so and move on

```text
Codex's take: it agrees the cache key is wrong and would key on tenant + URL,
same as the fix on the branch.

One disagreement: it wants `resolveTenant()` awaited at the call site. It could
not see `src/router.ts`, where the await already happens — discounting that one.

One thing it caught that I had not: the seeded test passes against the buggy
key, so the case as written would not have failed before the fix.
```

Then stop. Do not run a second agent, and do not re-ask the same question with more context — one
outside opinion is the whole deliverable.

## Edge Cases

- **No agent installed, or only the host is** — the script says so and exits 0. Don't retry.
- **Timeout** — the script prints a timeout message. Note it and proceed without.
- **No `timeout` binary** — the script skips and says which tool is missing, per
  **Requirements**. Report that and proceed without an outside opinion; do not retry.

## Notes for Callers

This skill stays model-invocable on every host. The predecessor `claude` skill set
`disable-model-invocation: true` only because calling Claude from Claude was recursive; selection
now handles that structurally, so there is nothing left to suppress.

Other skills invoke this one as a skill, not by script path — a repo-relative path only resolves
inside one checkout.

`review:consilium` runs its outside board seat through this skill, and `review:doubt` runs its
outside verification seat the same way — both pass their own seat prompt as the preamble. That was
the last duplicate runner in the collection; there is now one implementation of "call an agent CLI
that is not the host".
