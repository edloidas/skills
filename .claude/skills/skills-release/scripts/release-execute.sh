#!/bin/bash

# Release Execution Script
# Bumps version in config files, commits, tags, and pushes
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

PLUGIN_JSON=".claude-plugin/plugin.json"
MARKETPLACE_JSON=".claude-plugin/marketplace.json"

# Verify config files exist
if [[ ! -f "$PLUGIN_JSON" ]]; then
  echo "ERROR: $PLUGIN_JSON not found"
  exit 1
fi

if [[ ! -f "$MARKETPLACE_JSON" ]]; then
  echo "ERROR: $MARKETPLACE_JSON not found"
  exit 1
fi

echo "Bumping version to $VERSION..."

# Update plugin.json
jq --arg v "$VERSION" '.version = $v' "$PLUGIN_JSON" > "$PLUGIN_JSON.tmp" && mv "$PLUGIN_JSON.tmp" "$PLUGIN_JSON"
echo "Updated $PLUGIN_JSON"

# Update marketplace.json
jq --arg v "$VERSION" '.plugins[0].version = $v' "$MARKETPLACE_JSON" > "$MARKETPLACE_JSON.tmp" && mv "$MARKETPLACE_JSON.tmp" "$MARKETPLACE_JSON"
echo "Updated $MARKETPLACE_JSON"

# Verify updates
PLUGIN_VERSION=$(jq -r '.version' "$PLUGIN_JSON")
MARKETPLACE_VERSION=$(jq -r '.plugins[0].version' "$MARKETPLACE_JSON")

if [[ "$PLUGIN_VERSION" != "$VERSION" ]]; then
  echo "ERROR: plugin.json version mismatch after update (got $PLUGIN_VERSION)"
  exit 1
fi

if [[ "$MARKETPLACE_VERSION" != "$VERSION" ]]; then
  echo "ERROR: marketplace.json version mismatch after update (got $MARKETPLACE_VERSION)"
  exit 1
fi

echo "Verified: both files updated to $VERSION"
echo ""

# Stage and commit
git add "$PLUGIN_JSON" "$MARKETPLACE_JSON"
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
