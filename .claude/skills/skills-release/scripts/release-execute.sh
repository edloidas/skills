#!/bin/bash

# Release Execution Script
# Bumps version in all plugin.json and marketplace.json files, commits, tags, and pushes
# Usage: release-execute.sh <version>
# For use with the skills-release skill

set -e

VERSION="$1"

# Validate version argument
if [[ -z "$VERSION" ]]; then
  echo "ERROR: Version argument required"
  echo "Usage: release-execute.sh <version>"
  echo "Example: release-execute.sh 1.1.0"
  exit 1
fi

# Validate X.Y.Z format
if ! echo "$VERSION" | grep -qE "^[0-9]+\.[0-9]+\.[0-9]+$"; then
  echo "ERROR: Invalid version format: $VERSION"
  echo "Expected: X.Y.Z (e.g., 1.1.0)"
  exit 1
fi

TAG_NAME="v$VERSION"

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "ERROR: Not a git repository"
  exit 1
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
  echo "ERROR: jq is required but not installed"
  exit 1
fi

# Check if tag already exists
if git tag -l | grep -q "^$TAG_NAME$"; then
  echo "ERROR: Tag $TAG_NAME already exists"
  exit 1
fi

MARKETPLACE_JSON=".claude-plugin/marketplace.json"

# Verify marketplace.json exists
if [[ ! -f "$MARKETPLACE_JSON" ]]; then
  echo "ERROR: $MARKETPLACE_JSON not found"
  exit 1
fi

PLUGIN_COUNT=$(jq '.plugins | length' "$MARKETPLACE_JSON")
FILES_TO_STAGE=("$MARKETPLACE_JSON")

echo "Bumping version to $VERSION..."

# Update all marketplace.json plugin entries
for i in $(seq 0 $((PLUGIN_COUNT - 1))); do
  jq --arg v "$VERSION" --argjson i "$i" '.plugins[$i].version = $v' "$MARKETPLACE_JSON" > "$MARKETPLACE_JSON.tmp" && mv "$MARKETPLACE_JSON.tmp" "$MARKETPLACE_JSON"
done
echo "Updated $MARKETPLACE_JSON ($PLUGIN_COUNT entries)"

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

# Verify all updates
for i in $(seq 0 $((PLUGIN_COUNT - 1))); do
  name=$(jq -r ".plugins[$i].name" "$MARKETPLACE_JSON")
  source=$(jq -r ".plugins[$i].source" "$MARKETPLACE_JSON" | sed 's|^\./||')
  plugin_json="$source/.claude-plugin/plugin.json"

  mp_version=$(jq -r ".plugins[$i].version" "$MARKETPLACE_JSON")
  pj_version=$(jq -r '.version' "$plugin_json")

  if [[ "$mp_version" != "$VERSION" ]]; then
    echo "ERROR: marketplace.json plugin '$name' version mismatch after update (got $mp_version)"
    exit 1
  fi

  if [[ "$pj_version" != "$VERSION" ]]; then
    echo "ERROR: $plugin_json version mismatch after update (got $pj_version)"
    exit 1
  fi
done

echo "Verified: all files updated to $VERSION"
echo ""

# Stage and commit
git add "${FILES_TO_STAGE[@]}"
git commit -m "Release $TAG_NAME"
echo "SUCCESS: Committed version bump"

# Create tag
git tag "$TAG_NAME"
echo "SUCCESS: Tag $TAG_NAME created"

# Check if we have a remote
REMOTE=$(git remote | head -n 1)

if [[ -z "$REMOTE" ]]; then
  echo "ERROR: No git remote configured"
  exit 1
fi

echo "Remote: $REMOTE"

# Push commits and tags
echo "Pushing commits..."
if git push "$REMOTE" HEAD; then
  echo "SUCCESS: Commits pushed"
else
  echo "ERROR: Failed to push commits"
  exit 1
fi

echo "Pushing tags..."
if git push "$REMOTE" --tags; then
  echo "SUCCESS: Tags pushed"
else
  echo "ERROR: Failed to push tags"
  exit 1
fi

echo ""
echo "Release $TAG_NAME completed successfully"

# Get remote URL for reference
REMOTE_URL=$(git remote get-url "$REMOTE" | sed 's/\.git$//')

echo ""
echo "=== Post-Release ==="
echo "GitHub Releases: $REMOTE_URL/releases"
