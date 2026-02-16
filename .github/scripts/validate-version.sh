#!/usr/bin/env bash
set -euo pipefail

# Validate that all plugin.json and marketplace.json versions match the given tag version.
# Usage: validate-version.sh <version>
#   e.g. validate-version.sh 1.3.0

TAG_VERSION="${1:?Usage: validate-version.sh <version>}"
MARKETPLACE=".claude-plugin/marketplace.json"

echo "Tag version: $TAG_VERSION"

errors=0

# Check each marketplace plugin entry
plugin_count=$(jq '.plugins | length' "$MARKETPLACE")

for i in $(seq 0 $((plugin_count - 1))); do
  name=$(jq -r ".plugins[$i].name" "$MARKETPLACE")
  mp_version=$(jq -r ".plugins[$i].version" "$MARKETPLACE")

  echo "Marketplace '$name': $mp_version"

  if [ "$TAG_VERSION" != "$mp_version" ]; then
    echo "::error::Tag version ($TAG_VERSION) does not match marketplace.json plugin '$name' ($mp_version)"
    errors=1
  fi
done

# Check each plugin.json
for i in $(seq 0 $((plugin_count - 1))); do
  name=$(jq -r ".plugins[$i].name" "$MARKETPLACE")
  source=$(jq -r ".plugins[$i].source" "$MARKETPLACE" | sed 's|^\./||')
  plugin_json="$source/.claude-plugin/plugin.json"

  if [ ! -f "$plugin_json" ]; then
    echo "::error::Plugin '$name': $plugin_json not found"
    errors=1
    continue
  fi

  pj_version=$(jq -r '.version' "$plugin_json")
  echo "Plugin '$name' ($plugin_json): $pj_version"

  if [ "$TAG_VERSION" != "$pj_version" ]; then
    echo "::error::Tag version ($TAG_VERSION) does not match $plugin_json ($pj_version)"
    errors=1
  fi
done

if [ "$errors" -eq 1 ]; then
  exit 1
fi

echo "All versions match: $TAG_VERSION"
