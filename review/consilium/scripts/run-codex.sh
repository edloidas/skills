#!/usr/bin/env bash
# Run Codex CLI as an independent reviewer for consilium.
# Usage: bash review/consilium/scripts/run-codex.sh <context-file> <output-file>
set -euo pipefail

CONTEXT_FILE="${1:-}"
OUTPUT_FILE="${2:-}"

if [[ -z "$CONTEXT_FILE" || -z "$OUTPUT_FILE" ]]; then
  echo "Usage: bash review/consilium/scripts/run-codex.sh <context-file> <output-file>" >&2
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
if timeout 120s codex exec -C "$PWD" -s read-only -o "$OUTPUT_FILE" "$PROMPT" > /dev/null 2>&1; then
  exit 0
else
  EXIT_CODE=$?
  if [[ $EXIT_CODE -eq 124 ]]; then
    echo "Codex reviewer timed out after 120s." > "$OUTPUT_FILE"
  else
    echo "Codex reviewer failed (exit code $EXIT_CODE)." > "$OUTPUT_FILE"
  fi
  exit 0
fi
