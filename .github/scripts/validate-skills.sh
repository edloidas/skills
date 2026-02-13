#!/usr/bin/env bash
set -euo pipefail

# Validate that all skill directories are listed in marketplace.json and vice versa.

MARKETPLACE=".claude-plugin/marketplace.json"

if [ ! -f "$MARKETPLACE" ]; then
  echo "::error::$MARKETPLACE not found"
  exit 1
fi

# Skill directories: top-level dirs containing SKILL.md (exclude .claude/)
dir_skills=$(find . -maxdepth 2 -name SKILL.md -not -path './.claude/*' \
  | sed 's|^\./||; s|/SKILL.md$||' | sort)

# Skills listed in marketplace.json (strip leading ./)
json_skills=$(jq -r '.plugins[0].skills[]' "$MARKETPLACE" \
  | sed 's|^\./||' | sort)

missing_from_json=$(comm -23 <(echo "$dir_skills") <(echo "$json_skills"))
missing_from_dirs=$(comm -13 <(echo "$dir_skills") <(echo "$json_skills"))

errors=0

if [ -n "$missing_from_json" ]; then
  echo "Skills missing from $MARKETPLACE:"
  while IFS= read -r skill; do
    echo "  ::error::$skill has SKILL.md but is not in marketplace.json"
  done <<< "$missing_from_json"
  errors=1
fi

if [ -n "$missing_from_dirs" ]; then
  echo "Stale entries in $MARKETPLACE:"
  while IFS= read -r skill; do
    echo "  ::error::$skill is in marketplace.json but has no SKILL.md"
  done <<< "$missing_from_dirs"
  errors=1
fi

if [ "$errors" -eq 1 ]; then
  exit 1
fi

echo "All skills are in sync with $MARKETPLACE"
