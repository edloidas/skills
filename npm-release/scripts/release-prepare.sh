#!/bin/bash

# Release Preparation Script
# Validates git status and runs pre-release checks
# Optimized for Claude Code interpretation

set -e  # Exit on error

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

# Detect package manager
if command -v pnpm &> /dev/null; then
  PKG_MANAGER="pnpm"
elif command -v npm &> /dev/null; then
  PKG_MANAGER="npm"
else
  echo "ERROR: Neither pnpm nor npm found"
  exit 1
fi

echo "Package manager: $PKG_MANAGER"

# Run dry-run release
echo "Running dry-run release..."

if [ "$PKG_MANAGER" = "pnpm" ]; then
  if pnpm release:dry; then
    echo "SUCCESS: All pre-flight checks passed"
  else
    echo "ERROR: Release dry-run failed"
    exit 1
  fi
else
  if npm publish --dry-run; then
    echo "SUCCESS: All pre-flight checks passed"
  else
    echo "ERROR: Release dry-run failed"
    exit 1
  fi
fi
