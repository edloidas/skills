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
allowed-tools: Bash(bash *outsider/scripts/run-outsider.sh *) Bash(bash *outsider/scripts/resolve-tmp.sh) Write(*/outsider-*)
argument-hint: "[review] [agent], or empty for ask mode"
metadata:
  author: edloidas
---

# Outsider — Quick Opinion From Another Agent

## Purpose

Get a fast opinion from an agent CLI running outside this session. One reviewer, no synthesis step
— a sanity check, not an exhaustive review. Use `review:consilium` when you want a board.

Ask mode writes the question to one temp file, which is left in place. The script captures the
agent's stdout and stderr in two more temp files — three for codex, which writes its answer to its
own — and deletes them when the agent exits. The responder is launched in the current working
directory with read-only tool grants — a sandbox for codex, an allowlist for the others — listed
with their known gaps in `references/agents.md`; `OUTSIDER_ARGS_<AGENT>` can widen them. It can read
any file there, not only what you send.

The question or diff, and any file the responder reads, goes to that agent's vendor service — it
leaves the machine. Keep secrets and credentials out of the question, and out of an uncommitted
review, which sends untracked files whole.

The value is structural: the responder shares none of this conversation's context and runs in its
own process, usually on a different model family. Which vendor answers is incidental, which is why
this skill resolves the agent instead of naming one.

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
configured to use, except claude, which skips its settings files and runs its built-in default. To pin one, or to change the preference order, edit
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
   `Asking codex (ask mode, up to 5 min).`

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

Review takes 3–10 minutes. Print one line before it starts, naming the agent, the scope, and the
wait — `Asking codex to review 6 uncommitted files (up to 9 min).` Pass `540` so the script's own
timer fires first and can print its timeout message, and set the surrounding command timeout to
the highest value the host allows:

```bash
bash <skill-dir>/scripts/run-outsider.sh review --host claude --uncommitted 540
```

## Custom Preamble

Both modes prepend a prompt file to whatever you pipe them — `references/prompt.md` for ask,
`references/review-prompt.md` for review. A caller with its own prompt for the responder passes
`--preamble <file>` to swap it, in either mode:

```bash
bash <skill-dir>/scripts/run-outsider.sh ask --host claude \
  --preamble <caller-skill-dir>/references/its-own-prompt.md <TMP>/outsider-<ID>-question.md
```

The preamble replaces the default entirely, so it has to carry the responder's whole brief —
including its output shape.

## Presenting Output

The first line of the output is `[outsider] agent: <name>`. Name that agent in your report — the
response is not interpretable without knowing who gave it.

- Lead with "Codex's take:", "From pi:", and so on, using the agent the script actually ran
- Evaluate the findings against your own context rather than adopting them
- Highlight agreements; flag disagreements and explain which side you land on and why
- The responder saw what you piped it and whatever it chose to read in the working directory —
  never this conversation. Discount findings that are really requests for context it did not have
- Empty output means it had nothing to offer — say so and move on

```text
Codex's take: it agrees the cache key is wrong and would key on tenant + URL,
same as the fix on the branch.

One disagreement: it wants `resolveTenant()` awaited at the call site. It did
not open `src/router.ts`, where the await already happens — discounting that one.

One thing it caught that I had not: the seeded test passes against the buggy
key, so the case as written would not have failed before the fix.
```

Then stop. Do not run a second agent, and do not re-ask the same question with more context — one
outside opinion is the whole deliverable.

## Edge Cases

- **No agent installed, or only the host is** — the script says so and exits 0. Don't retry.
- **Timeout** — the script prints a timeout message. Note it and proceed without.
- **`--base` or `--commit` does not resolve** — the script exits 2 and sends nothing. Correct the
  ref; never re-run as `--uncommitted`, which reviews a different change. An empty `--base` or
  uncommitted diff prints `Nothing to review:` and exits 0.
- **Agent failed** — the script prints the exit code and the last 20 lines of the agent's stderr.
  Quote the reason in one line, so a dropped outside opinion is never silent, and proceed without.

## Calling from Another Skill

Invoke this skill by name, never its script by path — a repo-relative path resolves only inside one
checkout. The caller supplies its preamble, its question, and its timeout; everything else about the
call is owned here, in place of **Presenting Output** and its stop sentence, which are for direct use:

- **`--host <the agent you are>`** on every call, so selection never picks the caller's own agent.
- **The preamble path** — `--preamble <caller-skill-dir>/references/<its-prompt>.md`, where
  `<caller-skill-dir>` is the directory the caller's `SKILL.md` was loaded from. Check it resolves
  before dispatch: skills are reachable through several symlink trees, and the script refuses a
  preamble it cannot find rather than send the question unbriefed.
- **The timeout** — pass the caller's value as the trailing number, so the script's own timer fires
  first and prints its message, and set the surrounding command timeout to the highest value the
  host allows. An answer that stopped at the mode default — 300s ask, 600s review — never received
  the argument.
- **The leg is droppable.** Exit 2 is the exception: a `--base` or `--commit` that does not resolve
  is the caller's error to surface, not a skip. A skip, a timeout, or a failure is not retried; the caller continues and
  its report says which happened. So does a host without this skill installed — it ships in the
  assist bundle.
- **Name the agent** from the first output line, `[outsider] agent: <name>`. Without that line no
  agent ran — a skip, a preamble refusal, or a failure: quote the script's message and drop the leg.
- **Detect an unbriefed answer.** The caller's preamble fixes an output shape — marker lines, a
  closed vocabulary. An answer missing it ran unbriefed or was truncated: rerun once, and if the
  second answer is missing it too, discard it rather than map it, drop the leg, and say so. An
  unbriefed answer looks like a result and is not one.
