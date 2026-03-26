#!/usr/bin/env bash
# Run Codex CLI for quick external opinions.
# Usage:
#   bash review/codex/scripts/run-codex.sh ask [timeout]        # reads question from stdin
#   bash review/codex/scripts/run-codex.sh review [flags] [timeout]
#     flags: --uncommitted | --base BRANCH | --commit SHA
# Always exits 0. Errors reported to stdout.
set -euo pipefail

MODE="${1:-ask}"
shift || true

if ! command -v codex &>/dev/null; then
  echo "Codex CLI not installed — skipping."
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_FLAGS=(-m gpt-5.4 --enable fast_mode --ephemeral -c model_reasoning_effort=xhigh -c web_search=live)

run_codex() {
  local exit_code=0
  "$@" || exit_code=$?
  if [[ $exit_code -eq 124 ]]; then
    echo "Codex timed out."
  elif [[ $exit_code -ne 0 ]]; then
    echo "Codex failed (exit code $exit_code)."
  fi
  return 0
}

case "$MODE" in
  ask)
    TIMEOUT="${1:-300}"
    PROMPT_FILE="$SCRIPT_DIR/../references/prompt.md"
    PROMPT=""
    if [[ -f "$PROMPT_FILE" ]]; then
      PROMPT="$(cat "$PROMPT_FILE")"
    fi
    PROMPT+="$(cat -)"
    echo "$PROMPT" | run_codex timeout "${TIMEOUT}s" codex exec "${COMMON_FLAGS[@]}" -s read-only - 2>/dev/null
    ;;
  review)
    TIMEOUT=600
    DIFF=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --uncommitted) DIFF="$(git diff HEAD 2>/dev/null; git diff --cached 2>/dev/null)"; shift ;;
        --base)        DIFF="$(git diff "$2"...HEAD 2>/dev/null)"; shift 2 ;;
        --commit)      DIFF="$(git show "$2" 2>/dev/null)"; shift 2 ;;
        [0-9]*)        TIMEOUT="$1"; shift ;;
        *)             shift ;;
      esac
    done
    if [[ -z "$DIFF" ]]; then
      # Default: uncommitted changes
      DIFF="$(git diff HEAD 2>/dev/null; git diff --cached 2>/dev/null)"
    fi
    if [[ -z "$DIFF" ]]; then
      echo "No changes to review."
      exit 0
    fi
    REVIEW_PROMPT_FILE="$SCRIPT_DIR/../references/review-prompt.md"
    PROMPT=""
    if [[ -f "$REVIEW_PROMPT_FILE" ]]; then
      PROMPT="$(cat "$REVIEW_PROMPT_FILE")"
    fi
    PROMPT+="$DIFF"
    echo "$PROMPT" | run_codex timeout "${TIMEOUT}s" codex exec "${COMMON_FLAGS[@]}" -s read-only - 2>/dev/null
    ;;
  *)
    echo "Unknown mode: $MODE. Use 'ask' or 'review'." >&2
    exit 0
    ;;
esac
