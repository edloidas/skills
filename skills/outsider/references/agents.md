# Agent Registry

`scripts/run-outsider.sh` is the executable registry — one `case` arm per agent in `build_cmd`.
This file records what each arm does, which arms are verified, and how to configure or extend them.

## Implemented agents

Every invocation is non-interactive, launched with read-only tool grants, and takes the prompt on
**stdin**. Only codex's is an OS sandbox; the others are tool allowlists, with the gaps noted below,
and `OUTSIDER_ARGS_<AGENT>` is appended after them, so it can widen any of them. None of them pins
a model or a reasoning level: unset means the agent's own current default — for claude, its built-in
default, since its settings files are not read.

| Agent | Binary | Invocation | Status |
| --- | --- | --- | --- |
| `codex` | `codex` | `codex exec --ephemeral --skip-git-repo-check -s read-only -o <file> -` | Verified |
| `claude` | `claude` | `claude -p --setting-sources "" --permission-mode dontAsk --tools "Read,Grep,Glob,Bash" --allowed-tools "Read,Grep,Glob,Bash(git diff:*),Bash(git log:*),Bash(git show:*)"` | Verified (2.1.312) |
| `opencode` | `opencode` | `opencode run --agent plan` | Verified |
| `pi` | `pi` | `pi --print --no-session -t read,grep,find,ls` | From pi's documented read-only mode; not re-run |

Notes on the non-obvious flags:

- **codex** writes to `-o <file>` because `codex exec` otherwise echoes the entire prompt back as
  part of its transcript — on a review that returns the whole diff to the caller. It also passes
  `--skip-git-repo-check`, since `codex exec` otherwise refuses to start outside a git repository.
- **opencode** uses its built-in `plan` agent, which is read-only. It emits ANSI colour and a
  `> plan · <model>` banner; the runner strips the escape codes.
- **claude** runs in `dontAsk`, which denies every call not on `--allowed-tools`, and `--tools` removes
  every other built-in. `--setting-sources ""` stops the user's own allow rules from widening that
  set — and with them any default model in settings, so pin one with `OUTSIDER_MODEL_CLAUDE`. A
  `touch` probe under these flags was refused while `git log` ran. `--output=<file>` on `git diff`,
  `log` or `show` is a write the allowed subset may still permit; this was not probed.
- **pi** uses the `-t` allowlist of its four read-only built-ins. The earlier `-xt edit,write`
  denylist left `bash` enabled, which can write; extension tools are now off too, since nothing
  says they are read-only.

Default preference order is `codex claude opencode pi`. The host agent is dropped from it, so
running under Claude Code picks `codex` and running under Codex picks `claude`.

## Adding an agent

No other harness is supported yet, and none is listed here speculatively — a row appears in the
table above only after a real run succeeds.

To add one: append it to `KNOWN_AGENTS` and `DEFAULT_ORDER` in the script, add a `case` arm in
`build_cmd` with the agent's non-interactive, read-only invocation, verify it end to end with
`ask`, then add its row above and its model/effort flags to the table below.

## Configuration

Nothing is required. Without config, the selected agent runs on whatever model and reasoning level
it is already configured to use — which is the point: the outside opinion should reflect that
agent's normal behaviour, not a setting frozen into this repo.

Config file, read if present:

```
~/.config/edloidas/outsider/config
```

(`$XDG_CONFIG_HOME` is honoured; `$OUTSIDER_CONFIG` overrides the path outright.)

It is **parsed, not sourced** — only `OUTSIDER_*` `KEY=VALUE` lines are read, quotes are stripped,
everything else is ignored, so the file cannot run commands. Environment variables win over the
file, which makes a one-off override a prefix on the command rather than an edit.

| Key | Effect | Example |
| --- | --- | --- |
| `OUTSIDER_AGENTS` | Preference order, space-separated | `"codex claude pi"` |
| `OUTSIDER_HOST` | Current harness, when the caller passes no `--host` | `"claude"` |
| `OUTSIDER_MODEL_<AGENT>` | Model for that agent | `OUTSIDER_MODEL_CODEX="gpt-5.6-sol"` |
| `OUTSIDER_EFFORT_<AGENT>` | Reasoning level for that agent | `OUTSIDER_EFFORT_CLAUDE="high"` |
| `OUTSIDER_ARGS_<AGENT>` | Extra raw flags, appended verbatim | `OUTSIDER_ARGS_CODEX="--enable fast_mode -c web_search=live"` |

`<AGENT>` is the agent name upper-cased, with `-` replaced by `_`.

Each agent takes its model and effort through a different flag, which the registry already knows:

| Agent | Model flag | Effort flag |
| --- | --- | --- |
| `codex` | `-m` | `-c model_reasoning_effort=` |
| `claude` | `--model` | `--effort` |
| `opencode` | `-m` (`provider/model`) | `--variant` |
| `pi` | `--model` | `--thinking` |

Example config:

```sh
# ~/.config/edloidas/outsider/config
OUTSIDER_AGENTS="codex claude opencode pi"

OUTSIDER_MODEL_CODEX="gpt-5.6-sol"
OUTSIDER_EFFORT_CODEX="high"
OUTSIDER_ARGS_CODEX="--enable fast_mode -c web_search=live"

OUTSIDER_MODEL_CLAUDE="fable"
OUTSIDER_EFFORT_CLAUDE="high"
```

Check what a given configuration resolves to without spending a request:

```bash
bash <skill-dir>/scripts/run-outsider.sh list --host <host>
```

## Host detection

The caller should always pass `--host <its own agent name>`. Sniffing is a fallback and only
partially reliable:

| Host | Marker | Reliable |
| --- | --- | --- |
| `claude` | `CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT` | Yes |
| `codex` | `CODEX_SANDBOX`, `CODEX_SANDBOX_NETWORK_DISABLED` | Only when sandboxed |
| `opencode` | `OPENCODE`, `OPENCODE_BIN_PATH` | Unverified |
| `pi` | — | No marker known |

Where sniffing fails, `OUTSIDER_HOST` in the config file settles it permanently. Getting it wrong
is not dangerous — the worst case is an agent asking itself, which wastes a call but returns a
valid answer.
