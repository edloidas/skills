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

# Verify config files exist
PLUGIN_JSON=".claude-plugin/plugin.json"
MARKETPLACE_JSON=".claude-plugin/marketplace.json"

if [[ ! -f "$PLUGIN_JSON" ]]; then
  echo "ERROR: $PLUGIN_JSON not found"
  exit 1
fi

if [[ ! -f "$MARKETPLACE_JSON" ]]; then
  echo "ERROR: $MARKETPLACE_JSON not found"
  exit 1
fi

# Read versions from both files
PLUGIN_VERSION=$(jq -r '.version' "$PLUGIN_JSON" 2>/dev/null)
MARKETPLACE_VERSION=$(jq -r '.plugins[0].version' "$MARKETPLACE_JSON" 2>/dev/null)

if [[ -z "$PLUGIN_VERSION" ]] || [[ "$PLUGIN_VERSION" == "null" ]]; then
  echo "ERROR: Could not read version from $PLUGIN_JSON"
  exit 1
fi

if [[ -z "$MARKETPLACE_VERSION" ]] || [[ "$MARKETPLACE_VERSION" == "null" ]]; then
  echo "ERROR: Could not read version from $MARKETPLACE_JSON"
  exit 1
fi

echo "Version (plugin.json): $PLUGIN_VERSION"
echo "Version (marketplace.json): $MARKETPLACE_VERSION"

# Warn if versions mismatch
if [[ "$PLUGIN_VERSION" != "$MARKETPLACE_VERSION" ]]; then
  echo "WARNING: Version mismatch between config files"
  echo "  plugin.json: $PLUGIN_VERSION"
  echo "  marketplace.json: $MARKETPLACE_VERSION"
fi

echo ""
echo "SUCCESS: All pre-flight checks passed"
