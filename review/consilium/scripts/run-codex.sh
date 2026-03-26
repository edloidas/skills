#!/usr/bin/env bash
# Run Codex CLI as an independent reviewer for consilium.
# Usage: bash review/consilium/scripts/run-codex.sh <context-file> <output-file> [timeout-seconds]
set -euo pipefail

CONTEXT_FILE="${1:-}"
OUTPUT_FILE="${2:-}"
TIMEOUT="${3:-600}"

if [[ -z "$CONTEXT_FILE" || -z "$OUTPUT_FILE" ]]; then
  echo "Usage: bash review/consilium/scripts/run-codex.sh <context-file> <output-file> [timeout-seconds]" >&2
  exit 1
fi

if ! command -v codex &>/dev/null; then
  echo "Codex CLI not installed — skipping Codex reviewer." > "$OUTPUT_FILE"
  exit 0
fi

if [[ ! -f "$CONTEXT_FILE" ]]; then
  echo "Context file not found: $CONTEXT_FILE" > "$OUTPUT_FILE"
  exit 0
fi

# Locate the prompt template relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROMPT_FILE="$SCRIPT_DIR/../references/codex-prompt.md"

if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "Codex prompt template not found: $PROMPT_FILE" > "$OUTPUT_FILE"
  exit 0
fi

# Build the full prompt: template + context content
PROMPT="$(cat "$PROMPT_FILE")
$(cat "$CONTEXT_FILE")"

# Run codex with a timeout. read-only sandbox, output to file.
if echo "$PROMPT" | timeout "${TIMEOUT}s" codex exec -m gpt-5.4 --enable fast_mode -C "$PWD" -s read-only --ephemeral -c model_reasoning_effort=xhigh -c web_search=live -o "$OUTPUT_FILE" - > /dev/null 2>&1; then
  exit 0
else
  EXIT_CODE=$?
  if [[ $EXIT_CODE -eq 124 ]]; then
    echo "Codex reviewer timed out after ${TIMEOUT}s." > "$OUTPUT_FILE"
  else
    echo "Codex reviewer failed (exit code $EXIT_CODE)." > "$OUTPUT_FILE"
  fi
  exit 0
fi
