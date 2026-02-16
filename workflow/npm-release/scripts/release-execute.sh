#!/bin/bash

# Release Execution Script
# Creates git tag and pushes to remote
# Optimized for Claude Code interpretation

set -e  # Exit on error

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

# Get version and package name from package.json
VERSION=$(jq -r '.version' ./package.json 2>/dev/null)
PACKAGE_NAME=$(jq -r '.name' ./package.json 2>/dev/null)

if [[ -z "$VERSION" ]] || [[ "$VERSION" == "null" ]]; then
  echo "ERROR: Could not read version from package.json"
  exit 1
fi

TAG_NAME="v$VERSION"

echo "Version: $VERSION"
echo "Tag: $TAG_NAME"

# Check if tag already exists locally
if git tag -l | grep -q "^$TAG_NAME$"; then
  echo "WARNING: Tag $TAG_NAME already exists locally"
  echo "INFO: Skipping tag creation"
else
  # Create the tag
  git tag "$TAG_NAME"
  echo "SUCCESS: Tag $TAG_NAME created"
fi

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
echo "=== Post-Release Verification ==="
echo "Package: https://www.npmjs.com/package/$PACKAGE_NAME"
echo "GitHub: $REMOTE_URL/releases"
