#!/usr/bin/env bash
# Extract active Biome rules via biome rage --linter
# Outputs JSON: { version, rules: [...], total }
set -euo pipefail

if ! command -v jq &>/dev/null; then
  echo >&2 "Error: jq is required"
  exit 1
fi

# Detect package manager
if [[ -f "pnpm-lock.yaml" ]]; then
  PM="pnpm exec"
elif [[ -f "yarn.lock" ]]; then
  PM="yarn"
elif [[ -f "bun.lockb" ]] || [[ -f "bun.lock" ]]; then
  PM="bunx"
else
  PM="npx"
fi

# Get Biome version
VERSION=$($PM biome --version 2>/dev/null | head -1 | sed 's/[^0-9.]//g')

# Run biome rage --linter and parse output
RAW=$($PM biome rage --linter 2>/dev/null)

# Biome 2.x format: rules listed under "Enabled rules:" section
# Each rule is indented like: "    category/ruleName"
RULES=$(echo "$RAW" | awk '
  /Enabled rules:/ { capture = 1; next }
  /Disabled rules:/ { capture = 0 }
  capture && /^[[:space:]]+[a-z]+\/[a-zA-Z]/ {
    gsub(/^[[:space:]]+/, "")
    gsub(/[[:space:]]+$/, "")
    if (length > 0) print
  }
')

# Fallback: try matching any category/ruleName pattern (older formats)
if [[ -z "$RULES" ]]; then
  RULES=$(echo "$RAW" | awk '
    /^[[:space:]]*[a-z]+\/[a-zA-Z]/ {
      gsub(/^[[:space:]]+/, "")
      split($0, parts, ":")
      rule = parts[1]
      gsub(/[[:space:]]+/, "", rule)
      # Strip "linter/" prefix if present
      sub(/^linter\//, "", rule)
      if (rule ~ /^[a-z]+\/[a-zA-Z]/) print rule
    }
  ')
fi

# Convert to JSON
echo "$RULES" | jq -R -s --arg version "$VERSION" '{
  version: $version,
  rules: [
    split("\n")[]
    | select(length > 0)
  ],
  total: null
} | .total = (.rules | length)'
