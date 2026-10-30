# Where Each Host Keeps Its Transcripts

Read in Phase 2. `<encoded-cwd>` is the project's absolute path with every `/` replaced by `-`
(`/home/me/repo/app` → `-home-me-repo-app`). A session's date is its file's modification time, or
the first timestamp inside it when the file has none.

| Host | Location | One session is | Project filter |
| ---- | -------- | -------------- | -------------- |
| Claude Code | `~/.claude/projects/<encoded-cwd>/*.jsonl` | One `.jsonl` file. Its subagents' transcripts sit in `<session-id>/subagents/*.jsonl` beside it and belong to the same session | The directory name |
| Codex | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` | One `rollout-*.jsonl` file | `cwd` in the first line's `session_meta` payload |
| OpenCode | `~/.local/share/opencode/opencode.db`, a SQLite database; older versions keep JSON files under `~/.local/share/opencode/storage/` instead | One row in `session`, with its rows in `message` and `part` joined on `session_id`; the text is in each `data` JSON column | `session.directory` |
| pi | `~/.pi/agent/sessions/--<encoded-cwd>--/*.jsonl` (the path's leading `-` plus a `--` on each side) | One `.jsonl` file | The directory name |

Open the OpenCode database read-only (`file:<path>?mode=ro` as a URI) with whatever SQLite client
the machine has, or Python's `sqlite3` module. With neither, record OpenCode as not readable and
why.

A location that does not exist means that host was not used on this machine; record it as `none
found`, not as unreadable.

## How a skill use shows up

A skill name may appear bare (`do`) or namespaced by the plugin (`edloidas:do`); treat both as the
same skill.

| Host | Invoked by the user | Invoked by the model or another skill |
| ---- | ------------------- | ------------------------------------- |
| Claude Code | `<command-name>/<name></command-name>` in a user message | A `Skill` tool call whose input names the skill |
| Codex | `$<name>` in a user message | A read of `.../skills/<name>/SKILL.md` |
| OpenCode | `/<name>` in a user message | A `skill` tool part naming it, or a read of its `SKILL.md` |
| pi | `/skill:<name>` in a user message | A read of `.../skills/<name>/SKILL.md` |

A `/do` run that routes onward shows as the `do` use followed by a second use of the target skill,
or by `do`'s `Route:` line naming a playbook.

## Interruption and error markers

| Host | Interrupted by the user | Errored |
| ---- | ----------------------- | ------- |
| Claude Code | `[Request interrupted by user` in a user message | A tool result with `is_error: true` |
| Codex | A `turn_aborted` event | A failed tool call output |
| OpenCode | An aborted assistant message | An `error` field on a message |
| pi | `"stopReason":"aborted"` | `"stopReason":"error"` |

Where a host's marker is not found in a transcript that plainly stopped mid-run, record the stop
from what the transcript shows — a user turn that cancels or restarts the request — rather than
skipping it.
