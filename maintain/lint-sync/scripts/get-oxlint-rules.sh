#!/usr/bin/env bash
# Extract active Oxlint rules via oxlint --rules
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

# Get Oxlint version
VERSION=$($PM oxlint --version 2>/dev/null | head -1 | sed 's/[^0-9.]//g')

# Run oxlint --rules to list all active rules
# Output format: "plugin/rule-name : severity - description"
RAW=$($PM oxlint --rules 2>/dev/null)

# Parse rules: extract "plugin/rule-name" from lines matching the pattern
RULES=$(echo "$RAW" | awk '
  /^[[:space:]]*[a-z][-a-z]*\/[a-z][-a-z]/ {
    gsub(/^[[:space:]]+/, "")
    split($0, parts, " ")
    rule = parts[1]
    gsub(/[[:space:]]+/, "", rule)
    if (rule ~ /^[a-z][-a-z]*\/[a-z][-a-z]/) print rule
  }
')

# Fallback: try parsing config-based output
if [[ -z "$RULES" ]]; then
  # Try oxlint --print-config (if available in newer versions)
  CONFIG=$($PM oxlint --print-config 2>/dev/null || true)
  if [[ -n "$CONFIG" ]]; then
    RULES=$(echo "$CONFIG" | jq -r '
      .rules // {} | to_entries[]
      | select(.value != "off" and .value != "allow" and .value != 0)
      | .key
    ' 2>/dev/null || true)
  fi
fi

# Fallback: parse .oxlintrc.json directly
if [[ -z "$RULES" ]]; then
  for config in ".oxlintrc.json" ".oxlintrc.jsonc" "oxlint.config.json"; do
    if [[ -f "$config" ]]; then
      # Extract enabled rules and active categories
      RULES=$(jq -r '
        (.rules // {}) | to_entries[]
        | select(
            .value != "off" and .value != "allow" and .value != 0
            and (if (.value | type) == "array" then .value[0] != "off" and .value[0] != "allow" and .value[0] != 0 else true end)
          )
        | .key
      ' "$config" 2>/dev/null || true)
      break
    fi
  done
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
