#!/bin/bash

# Release Preparation Script
# Validates git status and runs pre-release checks
# Optimized for agent interpretation

set -e  # Exit on error

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "ERROR: Not a git repository"
  exit 1
fi

# Check for package.json
if [ ! -f "package.json" ]; then
  echo "ERROR: No package.json found in $(pwd)"
  echo "This script must be run from a pnpm/bun/npm project root"
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
# Lockfile-driven detection. If a lockfile is present, the repo has opted into
# that manager — honor it and error if the tool is missing. Without a lockfile,
# fall back to availability in preference order: pnpm > bun > npm.
if [ -f "pnpm-lock.yaml" ]; then
  if ! command -v pnpm &> /dev/null; then
    echo "ERROR: pnpm-lock.yaml found but pnpm not installed"
    exit 1
  fi
  PKG_MANAGER="pnpm"
elif [ -f "bun.lock" ] || [ -f "bun.lockb" ]; then
  if ! command -v bun &> /dev/null; then
    echo "ERROR: bun.lock found but bun not installed"
    exit 1
  fi
  PKG_MANAGER="bun"
elif [ -f "package-lock.json" ]; then
  if ! command -v npm &> /dev/null; then
    echo "ERROR: package-lock.json found but npm not installed"
    exit 1
  fi
  PKG_MANAGER="npm"
elif command -v pnpm &> /dev/null; then
  PKG_MANAGER="pnpm"
elif command -v bun &> /dev/null; then
  PKG_MANAGER="bun"
elif command -v npm &> /dev/null; then
  PKG_MANAGER="npm"
else
  echo "ERROR: No supported package manager found (pnpm, bun, npm)"
  exit 1
fi

echo "Package manager: $PKG_MANAGER"

# Run dry-run release
echo "Running dry-run release..."

case "$PKG_MANAGER" in
  pnpm)
    if pnpm release:dry; then
      echo "SUCCESS: All pre-flight checks passed"
    else
      echo "ERROR: Release dry-run failed"
      exit 1
    fi
    ;;
  bun)
    if bun run release:dry; then
      echo "SUCCESS: All pre-flight checks passed"
    else
      echo "ERROR: Release dry-run failed"
      exit 1
    fi
    ;;
  npm)
    if npm publish --dry-run; then
      echo "SUCCESS: All pre-flight checks passed"
    else
      echo "ERROR: Release dry-run failed"
      exit 1
    fi
    ;;
esac
