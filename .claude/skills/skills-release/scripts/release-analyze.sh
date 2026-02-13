#!/bin/bash

# Release Analysis Script
# Analyzes commits since last tag and recommends version bump
# Uses conventional commit parsing with anchored regex
# For use with the skills-release skill

set -e

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

# Read current version from plugin.json
PLUGIN_JSON=".claude-plugin/plugin.json"
CURRENT_VERSION=$(jq -r '.version' "$PLUGIN_JSON" 2>/dev/null || echo "unknown")
echo "Current version: $CURRENT_VERSION"

# Get the last version tag
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

if [[ -z "$LAST_TAG" ]]; then
  echo "INFO: No previous release tags found (first release)"
  echo ""
  echo "Recent commits (last 20):"
  git log --oneline -20
  echo ""
  echo "=== Recommendation ==="
  echo "MINOR bump (first release)"
  exit 0
fi

echo "Last release tag: $LAST_TAG"

# Count commits since last tag
COMMIT_COUNT=$(git rev-list "$LAST_TAG"..HEAD --count)

if [[ $COMMIT_COUNT -eq 0 ]]; then
  echo "INFO: No new commits since last release"
  exit 0
fi

echo "Commits since last release: $COMMIT_COUNT"
echo ""

# Show commits
echo "=== Commit History ==="
git log "$LAST_TAG"..HEAD --oneline
echo ""

# Analyze commit types using anchored regex on subject lines
FEAT_COUNT=$(git log "$LAST_TAG"..HEAD --format="%s" | grep -c -E "^feat(\(.*\))?!?:" || true)
FIX_COUNT=$(git log "$LAST_TAG"..HEAD --format="%s" | grep -c -E "^fix(\(.*\))?!?:" || true)
REFACTOR_COUNT=$(git log "$LAST_TAG"..HEAD --format="%s" | grep -c -E "^refactor(\(.*\))?!?:" || true)
DOCS_COUNT=$(git log "$LAST_TAG"..HEAD --format="%s" | grep -c -E "^docs(\(.*\))?!?:" || true)
CHORE_COUNT=$(git log "$LAST_TAG"..HEAD --format="%s" | grep -c -E "^chore(\(.*\))?!?:" || true)
STYLE_COUNT=$(git log "$LAST_TAG"..HEAD --format="%s" | grep -c -E "^style(\(.*\))?!?:" || true)
CI_COUNT=$(git log "$LAST_TAG"..HEAD --format="%s" | grep -c -E "^ci(\(.*\))?!?:" || true)
TEST_COUNT=$(git log "$LAST_TAG"..HEAD --format="%s" | grep -c -E "^test(\(.*\))?!?:" || true)

# Detect breaking changes: "type!:" suffix or "BREAKING CHANGE" in commit body
BREAKING_SUFFIX=$(git log "$LAST_TAG"..HEAD --format="%s" | grep -c -E "^[a-z]+(\(.*\))?!:" || true)
BREAKING_BODY=$(git log "$LAST_TAG"..HEAD --format="%b" | grep -c -E "^BREAKING CHANGE:" || true)
BREAKING_COUNT=$((BREAKING_SUFFIX + BREAKING_BODY))

# Count unclassified commits
CLASSIFIED=$((FEAT_COUNT + FIX_COUNT + REFACTOR_COUNT + DOCS_COUNT + CHORE_COUNT + STYLE_COUNT + CI_COUNT + TEST_COUNT))
OTHER_COUNT=$((COMMIT_COUNT - CLASSIFIED))

echo "=== Change Summary ==="
echo "Features:     $FEAT_COUNT"
echo "Fixes:        $FIX_COUNT"
echo "Refactoring:  $REFACTOR_COUNT"
echo "Documentation:$DOCS_COUNT"
echo "Chore:        $CHORE_COUNT"
echo "Style:        $STYLE_COUNT"
echo "CI:           $CI_COUNT"
echo "Tests:        $TEST_COUNT"
echo "Other:        $OTHER_COUNT"
echo "Breaking:     $BREAKING_COUNT"
echo ""

# Show file change stats
echo "=== File Changes ==="
git diff "$LAST_TAG"..HEAD --stat
echo ""

# Recommendation
echo "=== Recommendation ==="
if [[ $BREAKING_COUNT -gt 0 ]]; then
  echo "MAJOR bump (breaking changes detected)"
elif [[ $FEAT_COUNT -gt 0 ]]; then
  echo "MINOR bump (new features added)"
elif [[ $FIX_COUNT -gt 0 ]] || [[ $REFACTOR_COUNT -gt 0 ]]; then
  echo "PATCH bump (fixes or refactoring)"
elif [[ $DOCS_COUNT -gt 0 ]] || [[ $CHORE_COUNT -gt 0 ]] || [[ $STYLE_COUNT -gt 0 ]] || [[ $CI_COUNT -gt 0 ]] || [[ $TEST_COUNT -gt 0 ]]; then
  echo "PATCH bump (maintenance changes)"
else
  echo "MANUAL review needed (no conventional commits found)"
fi
