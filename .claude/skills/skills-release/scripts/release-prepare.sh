#!/bin/bash

# Release Preparation Script
# Validates git status, branch, config files, and version consistency
# For use with the skills-release skill

set -e

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "ERROR: Not a git repository"
  exit 1
fi

# Get current branch
CURRENT_BRANCH=$(git branch --show-current)
echo "Branch: $CURRENT_BRANCH"

# Check if we're on master or main
if [[ "$CURRENT_BRANCH" != "master" ]] && [[ "$CURRENT_BRANCH" != "main" ]]; then
  echo "ERROR: Not on master or main branch"
  exit 1
fi

# Check for uncommitted changes
if [[ -n $(git status --porcelain) ]]; then
  echo "ERROR: Uncommitted changes detected"
  git status --short
  exit 1
fi

# Check jq is available
if ! command -v jq &> /dev/null; then
  echo "ERROR: jq is required but not installed"
  exit 1
fi

# Verify marketplace.json exists
MARKETPLACE_JSON=".claude-plugin/marketplace.json"

if [[ ! -f "$MARKETPLACE_JSON" ]]; then
  echo "ERROR: $MARKETPLACE_JSON not found"
  exit 1
fi

# Discover plugins from marketplace.json
PLUGIN_COUNT=$(jq '.plugins | length' "$MARKETPLACE_JSON")

if [[ "$PLUGIN_COUNT" -eq 0 ]]; then
  echo "ERROR: No plugins found in $MARKETPLACE_JSON"
  exit 1
fi

echo "Plugins: $PLUGIN_COUNT"

# Collect all versions and check consistency
VERSIONS=()

for i in $(seq 0 $((PLUGIN_COUNT - 1))); do
  name=$(jq -r ".plugins[$i].name" "$MARKETPLACE_JSON")
  source=$(jq -r ".plugins[$i].source" "$MARKETPLACE_JSON" | sed 's|^\./||')
  mp_version=$(jq -r ".plugins[$i].version" "$MARKETPLACE_JSON")
  plugin_json="$source/.claude-plugin/plugin.json"

  if [[ ! -f "$plugin_json" ]]; then
    echo "ERROR: $plugin_json not found"
    exit 1
  fi

  pj_version=$(jq -r '.version' "$plugin_json")

  echo "Plugin '$name': marketplace=$mp_version, plugin.json=$pj_version"
  VERSIONS+=("$mp_version" "$pj_version")
done

# Check all versions match
FIRST="${VERSIONS[0]}"
for v in "${VERSIONS[@]}"; do
  if [[ "$v" != "$FIRST" ]]; then
    echo "WARNING: Version mismatch detected across config files"
    exit 1
  fi
done

echo ""
echo "Version: $FIRST"
echo ""
echo "SUCCESS: All pre-flight checks passed"
