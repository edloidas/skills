#!/usr/bin/env bash
# Run Claude Code CLI for quick external opinions.
# Usage:
#   bash assist/skills/claude/scripts/run-claude.sh ask [file] [timeout]   # stdin if no file
#   bash assist/skills/claude/scripts/run-claude.sh review [flags] [timeout]
#     flags: --uncommitted | --base BRANCH | --commit SHA
# Always exits 0. Errors reported to stdout.
set -euo pipefail

MODE="${1:-ask}"
shift || true

if ! command -v claude &>/dev/null; then
  echo "Claude Code CLI not installed — skipping."
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_FLAGS=(
  -p --model fable --effort high --permission-mode auto
  --allowed-tools "Read,Grep,Glob,Bash(git:*)"
  --disallowed-tools "Edit,Write,NotebookEdit"
)

run_claude() {
  local exit_code=0
  "$@" || exit_code=$?
  if [[ $exit_code -eq 124 ]]; then
    echo "Claude timed out."
  elif [[ $exit_code -ne 0 ]]; then
    echo "Claude failed (exit code $exit_code)."
  fi
  return 0
}

# `git diff HEAD` already covers staged hunks, so never add `--cached` on top of it.
# Untracked files are diffed against /dev/null so new files reach the reviewer without
# touching the index.
collect_uncommitted() {
  git diff HEAD 2>/dev/null || true
  git ls-files --others --exclude-standard -z 2>/dev/null |
    while IFS= read -r -d '' f; do
      git diff --no-index -- /dev/null "$f" 2>/dev/null || true
    done
}

case "$MODE" in
  ask)
    INPUT_FILE=""
    TIMEOUT=300
    while [[ $# -gt 0 ]]; do
      if [[ -f "$1" ]]; then
        INPUT_FILE="$1"
      elif [[ "$1" =~ ^[0-9]+$ ]]; then
        TIMEOUT="$1"
      else
        # Looks like a path but is not a file — fail loudly rather than silently
        # sending an empty question.
        echo "Question file not found: $1"
        exit 0
      fi
      shift
    done

    PROMPT_FILE="$SCRIPT_DIR/../references/prompt.md"
    PROMPT=""
    if [[ -f "$PROMPT_FILE" ]]; then
      PROMPT="$(cat "$PROMPT_FILE")"$'\n'
    fi
    if [[ -n "$INPUT_FILE" ]]; then
      PROMPT+="$(cat "$INPUT_FILE")"
    else
      PROMPT+="$(cat -)"
    fi
    echo "$PROMPT" | run_claude timeout "${TIMEOUT}s" claude "${COMMON_FLAGS[@]}" 2>/dev/null
    ;;
  review)
    TIMEOUT=600
    DIFF=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --uncommitted) DIFF="$(collect_uncommitted)"; shift ;;
        --base)        DIFF="$(git diff "$2"...HEAD 2>/dev/null || true)"; shift 2 ;;
        --commit)      DIFF="$(git show "$2" 2>/dev/null || true)"; shift 2 ;;
        [0-9]*)        TIMEOUT="$1"; shift ;;
        *)             shift ;;
      esac
    done
    if [[ -z "$DIFF" ]]; then
      DIFF="$(collect_uncommitted)"
    fi
    if [[ -z "$DIFF" ]]; then
      echo "No changes to review."
      exit 0
    fi
    REVIEW_PROMPT_FILE="$SCRIPT_DIR/../references/review-prompt.md"
    PROMPT=""
    if [[ -f "$REVIEW_PROMPT_FILE" ]]; then
      PROMPT="$(cat "$REVIEW_PROMPT_FILE")"$'\n'
    fi
    PROMPT+="$DIFF"
    echo "$PROMPT" | run_claude timeout "${TIMEOUT}s" claude "${COMMON_FLAGS[@]}" 2>/dev/null
    ;;
  *)
    echo "Unknown mode: $MODE. Use 'ask' or 'review'." >&2
    exit 0
    ;;
esac
