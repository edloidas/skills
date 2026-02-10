#!/bin/bash

# Release Analysis Script
# Shows commits and changes since last release to help decide version bump
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

# Get the last version tag
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

if [[ -z "$LAST_TAG" ]]; then
  echo "INFO: No previous release tags found (first release)"
  CURRENT_VERSION=$(jq -r '.version' ./package.json 2>/dev/null || echo "unknown")
  echo "Current version: $CURRENT_VERSION"
  echo ""
  echo "Recent commits (last 10):"
  git log --oneline -10
  exit 0
fi

# Get current version from package.json
CURRENT_VERSION=$(jq -r '.version' ./package.json 2>/dev/null || echo "unknown")

echo "Current version: $CURRENT_VERSION"
echo "Last release tag: $LAST_TAG"

# Count commits since last tag
COMMIT_COUNT=$(git rev-list $LAST_TAG..HEAD --count)

if [[ $COMMIT_COUNT -eq 0 ]]; then
  echo "INFO: No new commits since last release"
  exit 0
fi

echo "Commits since last release: $COMMIT_COUNT"
echo ""

# Show commits
echo "=== Commit History ==="
git log $LAST_TAG..HEAD --oneline
echo ""

# Show file statistics
echo "=== File Changes ==="
git diff $LAST_TAG..HEAD --stat
echo ""

# Analyze commit types
FEAT_COUNT=$(git log $LAST_TAG..HEAD --oneline | grep -i -E "(feat|feature|add)" | wc -l | tr -d ' ')
FIX_COUNT=$(git log $LAST_TAG..HEAD --oneline | grep -i -E "(fix|bug)" | wc -l | tr -d ' ')
REFACTOR_COUNT=$(git log $LAST_TAG..HEAD --oneline | grep -i -E "(refactor|refact)" | wc -l | tr -d ' ')
DOCS_COUNT=$(git log $LAST_TAG..HEAD --oneline | grep -i -E "(doc|docs)" | wc -l | tr -d ' ')
BREAKING_COUNT=$(git log $LAST_TAG..HEAD --oneline | grep -i -E "(breaking|break)" | wc -l | tr -d ' ')

echo "=== Change Summary ==="
echo "Features: $FEAT_COUNT"
echo "Fixes: $FIX_COUNT"
echo "Refactoring: $REFACTOR_COUNT"
echo "Documentation: $DOCS_COUNT"
echo "Breaking: $BREAKING_COUNT"
echo ""

# Recommendation
echo "=== Recommendation ==="
if [[ $BREAKING_COUNT -gt 0 ]] || [[ $FEAT_COUNT -gt 0 ]]; then
  echo "MINOR bump (new features or breaking changes)"
elif [[ $FIX_COUNT -gt 0 ]] || [[ $REFACTOR_COUNT -gt 0 ]]; then
  echo "PATCH bump (fixes or refactoring)"
elif [[ $DOCS_COUNT -gt 0 ]]; then
  echo "PATCH bump (documentation only)"
else
  echo "MANUAL review needed"
fi
