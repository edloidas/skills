#!/usr/bin/env bash
# Run an agent CLI from another harness for an outside opinion.
#
# Usage:
#   run-outsider.sh ask    [--host H] [--agent A] [--preamble FILE] [--attach FILE]...
#                          [--confirm-uncommitted] [FILE] [TIMEOUT]
#   run-outsider.sh review [--host H] [--agent A] [--uncommitted|--base B|--commit SHA]
#                          [--confirm-uncommitted] [TIMEOUT]
#   run-outsider.sh list   [--host H]
#
#   --host    the harness invoking this script; it is excluded from selection
#   --agent   force one agent, host or not
#   --attach  append a working-tree file to an ask payload, whole
#   --confirm-uncommitted  the user approved sending uncommitted or untracked content
#
# Selection: an explicit --agent wins; otherwise the first installed agent in
# $OUTSIDER_AGENTS that is not the host. Model and effort are never set unless
# configured — see references/agents.md.
#
# Exits 0, with errors and skips reported on stdout — except exit 2 when a
# review's --base or --commit does not resolve, so a wrong scope is never reviewed,
# and exit 3 when the payload holds uncommitted or untracked content and
# --confirm-uncommitted was not passed. Exit 3 sends nothing and prints an
# `[outsider] uncommitted payload:` line plus the file list, for the caller to put to the user.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_ROOT="${TMPDIR:-/tmp}"

# GNU coreutils `timeout` is not on stock macOS; with Homebrew coreutils it is
# `gtimeout`. Resolve it once. Unlike run-react-doctor.sh, which falls back to an
# unbounded run, a missing timeout here is a skip: this script drives interactive
# agent CLIs, and a hung `codex exec` would hang the caller's whole turn. The
# caller continues either way, so skipping loudly costs an opinion, not a session.
TIMEOUT_BIN=""
if command -v timeout &>/dev/null; then
  TIMEOUT_BIN="timeout"
elif command -v gtimeout &>/dev/null; then
  TIMEOUT_BIN="gtimeout"
fi
KNOWN_AGENTS="codex claude opencode pi"
DEFAULT_ORDER="codex claude opencode pi"

# ---------------------------------------------------------------- config ----
# ~/.config/edloidas/outsider/config, parsed rather than sourced: only
# OUTSIDER_* KEY=VALUE lines are read, so the file cannot run commands.
# Anything already set in the environment wins over the file.
CONFIG_FILE="${OUTSIDER_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/edloidas/outsider/config}"
if [[ -f "$CONFIG_FILE" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*(OUTSIDER_[A-Z0-9_]+)[[:space:]]*=[[:space:]]*(.*)$ ]] || continue
    cfg_key="${BASH_REMATCH[1]}"
    cfg_val="${BASH_REMATCH[2]}"
    cfg_val="${cfg_val%\"}"; cfg_val="${cfg_val#\"}"
    cfg_val="${cfg_val%\'}"; cfg_val="${cfg_val#\'}"
    if [[ -z "$(eval "printf '%s' \"\${$cfg_key:-}\"")" ]]; then
      eval "$cfg_key=\$cfg_val"
      export "$cfg_key"
    fi
  done < "$CONFIG_FILE"
fi

AGENTS_ORDER="${OUTSIDER_AGENTS:-$DEFAULT_ORDER}"

# cfg_for MODEL codex -> $OUTSIDER_MODEL_CODEX
cfg_for() {
  local key
  key="OUTSIDER_$1_$(printf '%s' "$2" | tr '[:lower:]-' '[:upper:]_')"
  eval "printf '%s' \"\${$key:-}\""
}

# -------------------------------------------------------------- registry ----
# One entry per agent. Adding an agent means adding a case arm here and a row
# in references/agents.md — nothing else.
CMD=()
OUT_FILE=""

build_cmd() {
  local agent="$1" model effort extra_raw
  model="$(cfg_for MODEL "$agent")"
  effort="$(cfg_for EFFORT "$agent")"
  extra_raw="$(cfg_for ARGS "$agent")"
  local extra=()
  if [[ -n "$extra_raw" ]]; then
    read -ra extra <<< "$extra_raw"
  fi
  CMD=()
  OUT_FILE=""
  case "$agent" in
    codex)
      # -o keeps the answer out of the echoed transcript, which would
      # otherwise return the whole prompt back to the caller. Callers often
      # run from a directory that is not a repo, where codex refuses to start.
      OUT_FILE="$TMP_ROOT/outsider-codex-$$.out"
      CMD=(codex exec --ephemeral --skip-git-repo-check -s read-only)
      if [[ -n "$model" ]]; then CMD+=(-m "$model"); fi
      if [[ -n "$effort" ]]; then CMD+=(-c "model_reasoning_effort=$effort"); fi
      if [[ ${#extra[@]} -gt 0 ]]; then CMD+=("${extra[@]}"); fi
      CMD+=(-o "$OUT_FILE" -)
      ;;
    claude)
      # dontAsk denies anything not allowed here; no setting sources, so a
      # user's own allow rules cannot widen it.
      CMD=(claude -p --setting-sources "" --permission-mode dontAsk
        --tools "Read,Grep,Glob,Bash"
        --allowed-tools "Read,Grep,Glob,Bash(git diff:*),Bash(git log:*),Bash(git show:*)")
      if [[ -n "$model" ]]; then CMD+=(--model "$model"); fi
      if [[ -n "$effort" ]]; then CMD+=(--effort "$effort"); fi
      if [[ ${#extra[@]} -gt 0 ]]; then CMD+=("${extra[@]}"); fi
      ;;
    opencode)
      # `plan` is opencode's built-in read-only agent.
      CMD=(opencode run --agent plan)
      if [[ -n "$model" ]]; then CMD+=(-m "$model"); fi
      if [[ -n "$effort" ]]; then CMD+=(--variant "$effort"); fi
      if [[ ${#extra[@]} -gt 0 ]]; then CMD+=("${extra[@]}"); fi
      ;;
    pi)
      CMD=(pi --print --no-session -t read,grep,find,ls)
      if [[ -n "$model" ]]; then CMD+=(--model "$model"); fi
      if [[ -n "$effort" ]]; then CMD+=(--thinking "$effort"); fi
      if [[ ${#extra[@]} -gt 0 ]]; then CMD+=("${extra[@]}"); fi
      ;;
    *)
      return 1
      ;;
  esac
  SELECTED_MODEL="$model"
  return 0
}

is_known() {
  case " $KNOWN_AGENTS " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

is_installed() {
  command -v "$1" &>/dev/null
}

# ------------------------------------------------------------- selection ----
# Best-effort only: the caller is expected to pass --host. CLAUDECODE is the one
# marker verified on this machine; export OUTSIDER_HOST where sniffing fails.
detect_host() {
  if [[ -n "${OUTSIDER_HOST:-}" ]]; then printf '%s' "$OUTSIDER_HOST"; return; fi
  if [[ -n "${CLAUDECODE:-}${CLAUDE_CODE_ENTRYPOINT:-}" ]]; then printf 'claude'; return; fi
  if [[ -n "${CODEX_SANDBOX:-}${CODEX_SANDBOX_NETWORK_DISABLED:-}" ]]; then printf 'codex'; return; fi
  if [[ -n "${OPENCODE:-}${OPENCODE_BIN_PATH:-}" ]]; then printf 'opencode'; return; fi
  printf ''
}

# Sets SELECTED_AGENT on success, SELECT_MSG on skip. Returns 1 when nothing
# runnable was found, so callers never mistake a skip message for an agent name.
SELECTED_AGENT=""
SELECT_MSG=""
select_agent() {
  local host="$1" want="$2" a
  SELECTED_AGENT=""
  SELECT_MSG=""
  if [[ -n "$want" ]]; then
    if ! is_known "$want"; then
      SELECT_MSG="Unknown agent '$want'. Known agents: $KNOWN_AGENTS."
      return 1
    fi
    if ! is_installed "$want"; then
      SELECT_MSG="Agent '$want' is not installed — skipping."
      return 1
    fi
    SELECTED_AGENT="$want"
    return 0
  fi
  for a in $AGENTS_ORDER; do
    if [[ "$a" == "$host" ]]; then continue; fi
    if is_known "$a" && is_installed "$a"; then
      SELECTED_AGENT="$a"
      return 0
    fi
  done
  SELECT_MSG="No external agent CLI available (host: ${host:-unknown}, tried: $AGENTS_ORDER) — skipping."
  return 1
}

# ----------------------------------------------------------------- input ----
# `git diff HEAD` already covers staged hunks, so never add `--cached` on top of
# it. Untracked files are diffed against /dev/null so new files reach the
# reviewer without touching the index.
collect_uncommitted() {
  git diff HEAD 2>/dev/null || true
  git ls-files --others --exclude-standard -z 2>/dev/null |
    while IFS= read -r -d '' f; do
      git diff --no-index -- /dev/null "$f" 2>/dev/null || true
    done
}

# Counts NUL-terminated names on stdin.
count_nul() {
  local n
  n="$(tr -cd '\000' | wc -c)"
  printf '%s' "$((n))"
}

# Sets GATE_FILES, GATE_UNTRACKED, GATE_BYTES and GATE_NAMES (one path per
# element, untracked ones suffixed) for the uncommitted part of the payload;
# GATE_FILES=0 means the payload is committed-only.
GATE_FILES=0
GATE_UNTRACKED=0
GATE_BYTES=0
GATE_NAMES=()
measure_uncommitted() {
  local f st n
  if [[ "$MODE" == "review" ]]; then
    [[ "$SCOPE" == "uncommitted" ]] || return 0
    # Untracked first: new files are where secrets turn up, so they must not be
    # the ones cut off by the 20-path cap.
    while IFS= read -r -d '' f; do
      GATE_NAMES+=("$f (untracked)")
      GATE_UNTRACKED=$((GATE_UNTRACKED + 1))
    done < <(git ls-files --others --exclude-standard -z 2>/dev/null)
    while IFS= read -r -d '' f; do
      GATE_NAMES+=("$f")
    done < <(git diff HEAD --name-only -z 2>/dev/null)
    GATE_FILES=${#GATE_NAMES[@]}
    n="$(printf '%s' "$DIFF" | wc -c)"
    GATE_BYTES=$((n))
    return 0
  fi
  # An attachment counts unless git reports it tracked and clean. Ignored files
  # count as untracked, and so does a file git cannot place in this repo.
  if [[ ${#ATTACH[@]} -eq 0 ]]; then return 0; fi
  for f in "${ATTACH[@]}"; do
    if st="$(git status --porcelain --ignored --untracked-files=all -- "$f" 2>/dev/null)"; then
      [[ -n "$st" ]] || continue
      case "$st" in
        '??'*|'!!'*) GATE_UNTRACKED=$((GATE_UNTRACKED + 1)); GATE_NAMES+=("$f (untracked)") ;;
        *) GATE_NAMES+=("$f") ;;
      esac
    else
      GATE_UNTRACKED=$((GATE_UNTRACKED + 1))
      GATE_NAMES+=("$f (untracked)")
    fi
    GATE_FILES=$((GATE_FILES + 1))
    n="$(wc -c < "$f")"
    GATE_BYTES=$((GATE_BYTES + n))
  done
}

# --------------------------------------------------------------- execute ----
strip_ansi() {
  sed -e 's/'$'\033''\[[0-9;?]*[a-zA-Z]//g'
}

# An explicit --preamble that does not resolve is a caller bug, and the expensive
# kind: the agent would run with no brief and return something that reads like a
# real answer. A missing default prompt file is only a degraded prompt, so it
# stays a warning.
check_preamble() {
  local file="$1"
  if [[ -f "$file" ]]; then return 0; fi
  if [[ -n "$PREAMBLE" ]]; then
    echo "Preamble file not found: $file"
    echo "The preamble carries the responder's whole brief, including its output shape."
    echo "Running without it would return an unbriefed answer, so this is a hard stop."
    echo "Pass a path that resolves from the current directory ($PWD), or omit --preamble"
    echo "to use the default prompt."
    return 1
  fi
  echo "[outsider] default prompt file missing ($file) — sending the input unframed."
  return 0
}

run_agent() {
  local agent="$1" timeout_s="$2" raw err rc=0
  # Reported before the agent name, so the message never reads as the agent's
  # fault — which is exactly how a bare exit 127 from a missing `timeout` read.
  if [[ -z "$TIMEOUT_BIN" ]]; then
    echo "Cannot run $agent: neither 'timeout' nor 'gtimeout' is on PATH."
    echo "Both ship with GNU coreutils — on macOS, 'brew install coreutils'."
    echo "Running an agent CLI unbounded could hang this turn, so this is a skip."
    return 0
  fi
  raw="$TMP_ROOT/outsider-$agent-$$.raw"
  err="$TMP_ROOT/outsider-$agent-$$.err"
  echo "[outsider] agent: $agent${SELECTED_MODEL:+ (model: $SELECTED_MODEL)}"
  "$TIMEOUT_BIN" "${timeout_s}s" "${CMD[@]}" >"$raw" 2>"$err" || rc=$?
  local src=""
  if [[ -n "$OUT_FILE" && -s "$OUT_FILE" ]]; then src="$OUT_FILE"
  elif [[ -s "$raw" ]]; then src="$raw"; fi
  if [[ -n "$src" ]]; then
    strip_ansi <"$src"
    # `$(tail -c1)` drops a trailing newline, so a non-empty result means the
    # agent did not end with one and the next line would run into its answer.
    if [[ -n "$(tail -c1 "$src")" ]]; then echo; fi
  fi
  if [[ $rc -eq 124 ]]; then
    echo "$agent timed out after ${timeout_s}s."
  elif [[ $rc -ne 0 ]]; then
    echo "$agent failed (exit code $rc)."
    if [[ -s "$err" ]]; then
      echo "$agent stderr (last 20 lines):"
      tail -n 20 "$err" | strip_ansi
      if [[ -n "$(tail -c1 "$err")" ]]; then echo; fi
    fi
  fi
  rm -f "$raw" "$err" ${OUT_FILE:+"$OUT_FILE"}
  return 0
}

# ------------------------------------------------------------------ main ----
MODE="${1:-ask}"
shift || true

case "$MODE" in
  ask|review|list) ;;
  *) echo "Unknown mode: $MODE. Use 'ask', 'review', or 'list'."; exit 0 ;;
esac

HOST_ARG=""
AGENT_ARG=""
PREAMBLE=""
ATTACH=()
CONFIRM_UNCOMMITTED=""
INPUT_FILE=""
DIFF=""
SCOPE="uncommitted"
SCOPE_REF=""
TIMEOUT=""
SELECTED_MODEL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)        HOST_ARG="${2:-}"; shift; shift 2>/dev/null || true ;;
    --agent)       AGENT_ARG="${2:-}"; shift; shift 2>/dev/null || true ;;
    --preamble)    PREAMBLE="${2:-}"; shift; shift 2>/dev/null || true ;;
    --attach)
      if [[ ! -f "${2:-}" ]]; then
        echo "Attached file not found: ${2:-}"
        exit 0
      fi
      ATTACH+=("$2"); shift 2 ;;
    --confirm-uncommitted) CONFIRM_UNCOMMITTED=1; shift ;;
    --uncommitted) SCOPE="uncommitted"; shift ;;
    --base)        SCOPE="base"; SCOPE_REF="${2:-}"; shift; shift 2>/dev/null || true ;;
    --commit)      SCOPE="commit"; SCOPE_REF="${2:-}"; shift; shift 2>/dev/null || true ;;
    [0-9]*)        TIMEOUT="$1"; shift ;;
    *)
      if [[ -f "$1" ]]; then
        INPUT_FILE="$1"
      elif [[ "$MODE" == "ask" ]]; then
        # Looks like a path but is not a file — fail loudly rather than
        # silently sending an empty question.
        echo "Question file not found: $1"
        exit 0
      fi
      shift
      ;;
  esac
done

if [[ "$HOST_ARG" == "auto" ]]; then HOST_ARG=""; fi
HOST="${HOST_ARG:-$(detect_host)}"

if [[ "$MODE" == "list" ]]; then
  printf '%-10s %-10s %s\n' agent binary status
  for a in $KNOWN_AGENTS; do
    if [[ "$a" == "$HOST" ]]; then s="host (skipped)"
    elif is_installed "$a"; then s="installed"
    else s="not installed"; fi
    printf '%-10s %-10s %s\n' "$a" "$a" "$s"
  done
  echo
  echo "host: ${HOST:-unknown}   order: $AGENTS_ORDER"
  if [[ -z "$TIMEOUT_BIN" ]]; then
    echo "timeout: MISSING — no agent can run until 'timeout' or 'gtimeout' is on PATH"
  fi
  if select_agent "$HOST" "$AGENT_ARG"; then
    echo "would select: $SELECTED_AGENT"
  else
    echo "would select: none — $SELECT_MSG"
  fi
  exit 0
fi

# Resolved before an agent is chosen: a ref that does not resolve is an error,
# never a fallback to another scope.
if [[ "$MODE" == "review" ]]; then
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Cannot review: $PWD is not inside a git work tree. Nothing was sent."
    exit 2
  fi
  if ! git rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
    echo "Cannot review: HEAD has no commit yet (unborn branch). Commit once, or use ask mode with --attach. Nothing was sent."
    exit 2
  fi
  if [[ "$SCOPE" != "uncommitted" ]] &&
     ! git rev-parse --verify --quiet "${SCOPE_REF:-}^{commit}" >/dev/null 2>&1; then
    echo "Cannot review --$SCOPE '${SCOPE_REF}': not a commit in this repository. Nothing was sent."
    exit 2
  fi
  case "$SCOPE" in
    base)
      if ! DIFF="$(git diff "$SCOPE_REF"...HEAD 2>/dev/null)"; then
        echo "Cannot review --base '$SCOPE_REF': it shares no merge base with HEAD. Nothing was sent."
        exit 2
      fi
      ;;
    commit) DIFF="$(git show "$SCOPE_REF")" ;;
    *)      DIFF="$(collect_uncommitted)" ;;
  esac
  if [[ -z "$DIFF" ]]; then
    if [[ "$SCOPE" == "uncommitted" ]]; then
      echo "Nothing to review: no uncommitted changes."
    else
      echo "Nothing to review: --$SCOPE '$SCOPE_REF' has an empty diff."
    fi
    exit 0
  fi
fi

if ! select_agent "$HOST" "$AGENT_ARG"; then
  echo "$SELECT_MSG"
  exit 0
fi
AGENT="$SELECTED_AGENT"
if ! build_cmd "$AGENT"; then
  echo "No invocation defined for agent '$AGENT' — skipping."
  exit 0
fi

if [[ "$MODE" == "ask" ]]; then
  PROMPT_FILE="${PREAMBLE:-$SCRIPT_DIR/../references/prompt.md}"
else
  PROMPT_FILE="${PREAMBLE:-$SCRIPT_DIR/../references/review-prompt.md}"
fi
if ! check_preamble "$PROMPT_FILE"; then exit 0; fi
PROMPT=""
if [[ -f "$PROMPT_FILE" ]]; then
  PROMPT="$(cat "$PROMPT_FILE")"$'\n'
fi
if [[ "$MODE" == "review" ]]; then
  PROMPT+="$DIFF"
else
  if [[ -n "$INPUT_FILE" ]]; then
    PROMPT+="$(cat "$INPUT_FILE")"
  else
    PROMPT+="$(cat -)"
  fi
  if [[ ${#ATTACH[@]} -gt 0 ]]; then
    for f in "${ATTACH[@]}"; do
      PROMPT+=$'\n\n'"----- begin $f -----"$'\n'"$(cat "$f")"$'\n'"----- end $f -----"
    done
  fi
fi

# Checked last, so the user is asked only when an agent would really run.
measure_uncommitted
if [[ $GATE_FILES -gt 0 && -z "$CONFIRM_UNCOMMITTED" && -n "$TIMEOUT_BIN" ]]; then
  echo "[outsider] uncommitted payload: $GATE_FILES files ($GATE_UNTRACKED untracked), $GATE_BYTES bytes, would go to $AGENT. Nothing was sent; re-run with --confirm-uncommitted to send."
  GATE_SHOWN=20
  i=0
  while [[ $i -lt ${#GATE_NAMES[@]} && $i -lt $GATE_SHOWN ]]; do
    # Control characters stripped, so a crafted name cannot forge or hide a line.
    printf '  %s\n' "$(printf '%s' "${GATE_NAMES[$i]}" | tr -d '[:cntrl:]')"
    i=$((i + 1))
  done
  if [[ ${#GATE_NAMES[@]} -gt $GATE_SHOWN ]]; then
    echo "  +$(( ${#GATE_NAMES[@]} - GATE_SHOWN )) more"
  fi
  exit 3
fi

if [[ "$MODE" == "ask" ]]; then
  echo "$PROMPT" | run_agent "$AGENT" "${TIMEOUT:-300}"
else
  echo "$PROMPT" | run_agent "$AGENT" "${TIMEOUT:-600}"
fi
