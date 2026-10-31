#!/bin/bash

# Version Bump Script
# Bumps version in all plugin.json and marketplace.json files, commits, and tags
# Does NOT push — use separately after user confirmation
# Usage: release-bump.sh <version>

set -e

. "$(dirname "$0")/release-tag.sh"

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
  echo "ERROR: Tag $TAG_NAME already exists. Nothing was changed."
  echo "       Choose another version, or, if $TAG_NAME was never pushed, the user may delete it with:"
  echo "         git tag -d $TAG_NAME"
  exit 1
fi

MARKETPLACE_JSON=".claude-plugin/marketplace.json"
CODEX_CATALOG="scripts/codex/catalog.json"
PACKAGE_JSON="package.json"

if [[ ! -f "$MARKETPLACE_JSON" ]]; then
  echo "ERROR: $MARKETPLACE_JSON not found"
  exit 1
fi

if [[ ! -f "$CODEX_CATALOG" ]]; then
  echo "ERROR: $CODEX_CATALOG not found"
  exit 1
fi

if [[ ! -f "$PACKAGE_JSON" ]]; then
  echo "ERROR: $PACKAGE_JSON not found"
  exit 1
fi

PLUGIN_COUNT=$(jq '.plugins | length' "$MARKETPLACE_JSON")
FILES_TO_STAGE=("$MARKETPLACE_JSON" "$CODEX_CATALOG" "$PACKAGE_JSON")

echo "Bumping version to $VERSION..."

# Update all marketplace.json plugin entries
for i in $(seq 0 $((PLUGIN_COUNT - 1))); do
  jq --arg v "$VERSION" --argjson i "$i" '.plugins[$i].version = $v' "$MARKETPLACE_JSON" > "$MARKETPLACE_JSON.tmp" && mv "$MARKETPLACE_JSON.tmp" "$MARKETPLACE_JSON"
done
echo "Updated $MARKETPLACE_JSON ($PLUGIN_COUNT entries)"

# Update Codex catalog version
jq --arg v "$VERSION" '.version = $v' "$CODEX_CATALOG" > "$CODEX_CATALOG.tmp" && mv "$CODEX_CATALOG.tmp" "$CODEX_CATALOG"
echo "Updated $CODEX_CATALOG"

# Update the pi package manifest — pi reads the version from package.json
jq --arg v "$VERSION" '.version = $v' "$PACKAGE_JSON" > "$PACKAGE_JSON.tmp" && mv "$PACKAGE_JSON.tmp" "$PACKAGE_JSON"
echo "Updated $PACKAGE_JSON"

# Update each plugin.json
for i in $(seq 0 $((PLUGIN_COUNT - 1))); do
  name=$(jq -r ".plugins[$i].name" "$MARKETPLACE_JSON")
  source=$(jq -r ".plugins[$i].source" "$MARKETPLACE_JSON" | sed -e 's|^\./||' -e 's|/$||' -e 's|^$|.|')
  plugin_json="$source/.claude-plugin/plugin.json"

  if [[ ! -f "$plugin_json" ]]; then
    echo "ERROR: $plugin_json not found"
    exit 1
  fi

  jq --arg v "$VERSION" '.version = $v' "$plugin_json" > "$plugin_json.tmp" && mv "$plugin_json.tmp" "$plugin_json"
  echo "Updated $plugin_json"
  FILES_TO_STAGE+=("$plugin_json")
done

# Regenerate the Codex plugin manifest from the updated catalog
./scripts/skills-packaging.sh sync-repo
CODEX_PLUGIN_JSON=".codex-plugin/plugin.json"
FILES_TO_STAGE+=("$CODEX_PLUGIN_JSON")

# Verify all updates
for i in $(seq 0 $((PLUGIN_COUNT - 1))); do
  name=$(jq -r ".plugins[$i].name" "$MARKETPLACE_JSON")
  source=$(jq -r ".plugins[$i].source" "$MARKETPLACE_JSON" | sed -e 's|^\./||' -e 's|/$||' -e 's|^$|.|')
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

pkg_version=$(jq -r '.version' "$PACKAGE_JSON")
if [[ "$pkg_version" != "$VERSION" ]]; then
  echo "ERROR: $PACKAGE_JSON version mismatch (got $pkg_version)"
  exit 1
fi

pj_version=$(jq -r '.version' "$CODEX_PLUGIN_JSON")
if [[ "$pj_version" != "$VERSION" ]]; then
  echo "ERROR: $CODEX_PLUGIN_JSON version mismatch (got $pj_version)"
  exit 1
fi

echo "Verified: all files updated to $VERSION"

# Stage and commit
git add "${FILES_TO_STAGE[@]}"
git commit -m "Release $TAG_NAME"
echo "Committed: Release $TAG_NAME"

create_release_tag "$TAG_NAME"
verify_release_tag "$TAG_NAME"
echo "Tagged: $TAG_NAME (not pushed)"
