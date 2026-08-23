#!/usr/bin/env bash
# Run an agent CLI from another harness for an outside opinion.
#
# Usage:
#   run-outsider.sh ask    [--host H] [--agent A] [--preamble FILE] [FILE] [TIMEOUT]
#   run-outsider.sh review [--host H] [--agent A] [--uncommitted|--base B|--commit SHA] [TIMEOUT]
#   run-outsider.sh list   [--host H]
#
#   --host   the harness invoking this script; it is excluded from selection
#   --agent  force one agent, host or not
#
# Selection: an explicit --agent wins; otherwise the first installed agent in
# $OUTSIDER_AGENTS that is not the host. Model and effort are never set unless
# configured — see references/agents.md.
#
# Always exits 0. Errors and skips are reported on stdout.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_ROOT="${TMPDIR:-/tmp}"
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
      # otherwise return the whole prompt back to the caller.
      OUT_FILE="$TMP_ROOT/outsider-codex-$$.out"
      CMD=(codex exec --ephemeral -s read-only)
      if [[ -n "$model" ]]; then CMD+=(-m "$model"); fi
      if [[ -n "$effort" ]]; then CMD+=(-c "model_reasoning_effort=$effort"); fi
      if [[ ${#extra[@]} -gt 0 ]]; then CMD+=("${extra[@]}"); fi
      CMD+=(-o "$OUT_FILE" -)
      ;;
    claude)
      CMD=(claude -p --permission-mode auto
        --allowed-tools "Read,Grep,Glob,Bash(git:*)"
        --disallowed-tools "Edit,Write,NotebookEdit")
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
      CMD=(pi --print --no-session -xt edit,write)
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
  local agent="$1" timeout_s="$2" raw rc=0
  raw="$TMP_ROOT/outsider-$agent-$$.raw"
  echo "[outsider] agent: $agent${SELECTED_MODEL:+ (model: $SELECTED_MODEL)}"
  timeout "${timeout_s}s" "${CMD[@]}" >"$raw" 2>/dev/null || rc=$?
  local src=""
  if [[ -n "$OUT_FILE" && -s "$OUT_FILE" ]]; then src="$OUT_FILE"
  elif [[ -s "$raw" ]]; then src="$raw"; fi
  if [[ -n "$src" ]]; then
    strip_ansi <"$src"
    # `$(tail -c1)` drops a trailing newline, so a non-empty result means the
    # agent did not end with one and the next line would run into its answer.
    if [[ -n "$(tail -c1 "$src")" ]]; then echo; fi
  fi
  rm -f "$raw" ${OUT_FILE:+"$OUT_FILE"}
  if [[ $rc -eq 124 ]]; then
    echo "$agent timed out after ${timeout_s}s."
  elif [[ $rc -ne 0 ]]; then
    echo "$agent failed (exit code $rc)."
  fi
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
INPUT_FILE=""
DIFF=""
TIMEOUT=""
SELECTED_MODEL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)        HOST_ARG="${2:-}"; shift; shift 2>/dev/null || true ;;
    --agent)       AGENT_ARG="${2:-}"; shift; shift 2>/dev/null || true ;;
    --preamble)    PREAMBLE="${2:-}"; shift; shift 2>/dev/null || true ;;
    --uncommitted) DIFF="$(collect_uncommitted)"; shift ;;
    --base)        DIFF="$(git diff "${2:-}"...HEAD 2>/dev/null || true)"; shift; shift 2>/dev/null || true ;;
    --commit)      DIFF="$(git show "${2:-}" 2>/dev/null || true)"; shift; shift 2>/dev/null || true ;;
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
  if select_agent "$HOST" "$AGENT_ARG"; then
    echo "would select: $SELECTED_AGENT"
  else
    echo "would select: none — $SELECT_MSG"
  fi
  exit 0
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

case "$MODE" in
  ask)
    PROMPT_FILE="${PREAMBLE:-$SCRIPT_DIR/../references/prompt.md}"
    if ! check_preamble "$PROMPT_FILE"; then exit 0; fi
    PROMPT=""
    if [[ -f "$PROMPT_FILE" ]]; then
      PROMPT="$(cat "$PROMPT_FILE")"$'\n'
    fi
    if [[ -n "$INPUT_FILE" ]]; then
      PROMPT+="$(cat "$INPUT_FILE")"
    else
      PROMPT+="$(cat -)"
    fi
    echo "$PROMPT" | run_agent "$AGENT" "${TIMEOUT:-300}"
    ;;
  review)
    if [[ -z "$DIFF" ]]; then
      DIFF="$(collect_uncommitted)"
    fi
    if [[ -z "$DIFF" ]]; then
      echo "No changes to review."
      exit 0
    fi
    PROMPT_FILE="${PREAMBLE:-$SCRIPT_DIR/../references/review-prompt.md}"
    if ! check_preamble "$PROMPT_FILE"; then exit 0; fi
    PROMPT=""
    if [[ -f "$PROMPT_FILE" ]]; then
      PROMPT="$(cat "$PROMPT_FILE")"$'\n'
    fi
    PROMPT+="$DIFF"
    echo "$PROMPT" | run_agent "$AGENT" "${TIMEOUT:-600}"
    ;;
esac
