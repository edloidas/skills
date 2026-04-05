#!/usr/bin/env bash
# Extract active ESLint rules via --print-config
# Outputs JSON: { file, rules: [{ name, severity, options }], total }
set -euo pipefail

# Auto-detect a representative source file
find_source_file() {
  local candidates=(
    "src/index.tsx"
    "src/index.ts"
    "src/App.tsx"
    "src/main.tsx"
    "src/main.ts"
  )

  for f in "${candidates[@]}"; do
    if [[ -f "$f" ]]; then
      echo "$f"
      return
    fi
  done

  # Fallback: find first .tsx in src/
  local tsx
  tsx=$(find src -name '*.tsx' -type f 2>/dev/null | head -1)
  if [[ -n "$tsx" ]]; then
    echo "$tsx"
    return
  fi

  # Fallback: find first .ts in src/
  local ts
  ts=$(find src -name '*.ts' -type f 2>/dev/null | head -1)
  if [[ -n "$ts" ]]; then
    echo "$ts"
    return
  fi

  echo >&2 "Error: No .ts or .tsx file found in src/"
  exit 1
}

TARGET_FILE="${1:-$(find_source_file)}"

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

# Run eslint --print-config and extract active rules
RAW=$($PM eslint --print-config "$TARGET_FILE" 2>/dev/null)

echo "$RAW" | jq --arg file "$TARGET_FILE" '{
  file: $file,
  rules: [
    to_entries[]
    | select(.key == "rules")
    | .value
    | to_entries[]
    | {
        name: .key,
        config: .value
      }
    | .severity = (
        if (.config | type) == "array" then
          .config[0]
        else
          .config
        end
      )
    | .options = (
        if (.config | type) == "array" and (.config | length) > 1 then
          .config[1:]
        else
          []
        end
      )
    | select(
        .severity != 0
        and .severity != "off"
      )
    | {name, severity, options}
  ],
  total: null
} | .total = (.rules | length)'
