#!/bin/bash

# Version Bump Script
# Bumps version in all plugin.json and marketplace.json files, commits, and tags
# Does NOT push — use separately after user confirmation
# Usage: release-bump.sh <version>

set -e

VERSION="$1"

if [[ -z "$VERSION" ]]; then
  echo "ERROR: Version argument required"
  echo "Usage: release-bump.sh <version>"
  exit 1
fi

if ! echo "$VERSION" | grep -qE "^[0-9]+\.[0-9]+\.[0-9]+$"; then
  echo "ERROR: Invalid version format: $VERSION"
  echo "Expected: X.Y.Z (e.g., 1.1.0)"
  exit 1
fi

TAG_NAME="v$VERSION"

if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "ERROR: Not a git repository"
  exit 1
fi

if ! command -v jq &> /dev/null; then
  echo "ERROR: jq is required but not installed"
  exit 1
fi

if git tag -l | grep -q "^$TAG_NAME$"; then
  echo "ERROR: Tag $TAG_NAME already exists"
  exit 1
fi

MARKETPLACE_JSON=".claude-plugin/marketplace.json"
CODEX_CATALOG="scripts/codex/catalog.json"

if [[ ! -f "$MARKETPLACE_JSON" ]]; then
  echo "ERROR: $MARKETPLACE_JSON not found"
  exit 1
fi

if [[ ! -f "$CODEX_CATALOG" ]]; then
  echo "ERROR: $CODEX_CATALOG not found"
  exit 1
fi

PLUGIN_COUNT=$(jq '.plugins | length' "$MARKETPLACE_JSON")
FILES_TO_STAGE=("$MARKETPLACE_JSON" "$CODEX_CATALOG")

echo "Bumping version to $VERSION..."

# Update all marketplace.json plugin entries
for i in $(seq 0 $((PLUGIN_COUNT - 1))); do
  jq --arg v "$VERSION" --argjson i "$i" '.plugins[$i].version = $v' "$MARKETPLACE_JSON" > "$MARKETPLACE_JSON.tmp" && mv "$MARKETPLACE_JSON.tmp" "$MARKETPLACE_JSON"
done
echo "Updated $MARKETPLACE_JSON ($PLUGIN_COUNT entries)"

# Update Codex catalog version
jq --arg v "$VERSION" '.version = $v' "$CODEX_CATALOG" > "$CODEX_CATALOG.tmp" && mv "$CODEX_CATALOG.tmp" "$CODEX_CATALOG"
echo "Updated $CODEX_CATALOG"

# Update each plugin.json
for i in $(seq 0 $((PLUGIN_COUNT - 1))); do
  name=$(jq -r ".plugins[$i].name" "$MARKETPLACE_JSON")
  source=$(jq -r ".plugins[$i].source" "$MARKETPLACE_JSON" | sed 's|^\./||')
  plugin_json="$source/.claude-plugin/plugin.json"

  if [[ ! -f "$plugin_json" ]]; then
    echo "ERROR: $plugin_json not found"
    exit 1
  fi

  jq --arg v "$VERSION" '.version = $v' "$plugin_json" > "$plugin_json.tmp" && mv "$plugin_json.tmp" "$plugin_json"
  echo "Updated $plugin_json"
  FILES_TO_STAGE+=("$plugin_json")
done

# Regenerate Codex wrapper plugin manifests from the updated catalog
./scripts/codex-packaging.sh sync-repo

while IFS= read -r plugin_name; do
  [[ -n "$plugin_name" ]] || continue
  FILES_TO_STAGE+=("plugins/$plugin_name/.codex-plugin/plugin.json")
done <<EOF
$(jq -r '.plugins[].name' "$CODEX_CATALOG")
EOF

# Verify all updates
for i in $(seq 0 $((PLUGIN_COUNT - 1))); do
  name=$(jq -r ".plugins[$i].name" "$MARKETPLACE_JSON")
  source=$(jq -r ".plugins[$i].source" "$MARKETPLACE_JSON" | sed 's|^\./||')
  plugin_json="$source/.claude-plugin/plugin.json"

  mp_version=$(jq -r ".plugins[$i].version" "$MARKETPLACE_JSON")
  pj_version=$(jq -r '.version' "$plugin_json")

  if [[ "$mp_version" != "$VERSION" ]]; then
    echo "ERROR: marketplace.json plugin '$name' version mismatch (got $mp_version)"
    exit 1
  fi

  if [[ "$pj_version" != "$VERSION" ]]; then
    echo "ERROR: $plugin_json version mismatch (got $pj_version)"
    exit 1
  fi
done

catalog_version=$(jq -r '.version' "$CODEX_CATALOG")
if [[ "$catalog_version" != "$VERSION" ]]; then
  echo "ERROR: $CODEX_CATALOG version mismatch (got $catalog_version)"
  exit 1
fi

while IFS= read -r plugin_name; do
  [[ -n "$plugin_name" ]] || continue
  plugin_json="plugins/$plugin_name/.codex-plugin/plugin.json"
  pj_version=$(jq -r '.version' "$plugin_json")

  if [[ "$pj_version" != "$VERSION" ]]; then
    echo "ERROR: $plugin_json version mismatch (got $pj_version)"
    exit 1
  fi
done <<EOF
$(jq -r '.plugins[].name' "$CODEX_CATALOG")
EOF

echo "Verified: all files updated to $VERSION"

# Stage and commit
git add "${FILES_TO_STAGE[@]}"
git commit -m "Release $TAG_NAME"
echo "Committed: Release $TAG_NAME"

# Create tag
git tag "$TAG_NAME"
echo "Tagged: $TAG_NAME"
