#!/usr/bin/env bash
# run-react-doctor.sh — Run react-doctor on a project directory
# Usage: run-react-doctor.sh <project-dir> <output-file>
#
# Creates a temporary config if the project lacks one.
# Falls back to npx if pnpm is unavailable.
# Writes results to <output-file> for the caller to consume.

set -euo pipefail

PROJECT_DIR="${1:-.}"
OUTPUT_FILE="${2:-/dev/stdout}"
TIMEOUT_SECONDS=120
TEMP_CONFIG=""

cleanup() {
  if [[ -n "$TEMP_CONFIG" && -f "$TEMP_CONFIG" ]]; then
    rm -f "$TEMP_CONFIG"
  fi
}
trap cleanup EXIT

# Resolve absolute path
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

# Check for existing config
CONFIG_FILE="$PROJECT_DIR/react-doctor.config.json"
if [[ ! -f "$CONFIG_FILE" ]]; then
  TEMP_CONFIG="$PROJECT_DIR/react-doctor.config.json"
  cat > "$TEMP_CONFIG" <<'CONF'
{
  "include": ["src/**/*.tsx", "src/**/*.ts", "app/**/*.tsx", "app/**/*.ts"],
  "exclude": ["**/*.stories.ts", "**/*.stories.tsx", "**/*.test.ts", "**/*.test.tsx", "**/*.spec.ts", "**/*.spec.tsx", "**/node_modules/**"]
}
CONF
fi

# Determine package runner
if command -v pnpm &>/dev/null; then
  RUNNER="pnpm dlx"
elif command -v npx &>/dev/null; then
  RUNNER="npx"
else
  echo "ERROR: Neither pnpm nor npx found. Install Node.js first." > "$OUTPUT_FILE"
  exit 1
fi

# Run react-doctor with timeout
echo "Running react-doctor via $RUNNER..." >&2
if timeout "$TIMEOUT_SECONDS" $RUNNER react-doctor --no-dead-code --verbose --no-ami -y "$PROJECT_DIR" > "$OUTPUT_FILE" 2>&1; then
  echo "react-doctor completed successfully." >&2
else
  EXIT_CODE=$?
  if [[ $EXIT_CODE -eq 124 ]]; then
    echo "" >> "$OUTPUT_FILE"
    echo "WARNING: react-doctor timed out after ${TIMEOUT_SECONDS}s" >> "$OUTPUT_FILE"
  fi
  # Non-zero exit is normal when issues are found — don't fail the script
  echo "react-doctor exited with code $EXIT_CODE" >&2
fi
