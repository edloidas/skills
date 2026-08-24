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

# Read current version from first plugin in marketplace.json
MARKETPLACE_JSON=".claude-plugin/marketplace.json"
CURRENT_VERSION=$(jq -r '.plugins[0].version' "$MARKETPLACE_JSON" 2>/dev/null || echo "unknown")
echo "Current version: $CURRENT_VERSION"

# Get the last version tag
# `--match` restricts the baseline to version tags. Without it,
# `git describe --tags --abbrev=0` returns the nearest reachable tag of ANY kind,
# so a scratch tag or a vendor marker becomes the release baseline and every
# count, stat, and recommendation below is measured from the wrong place.
LAST_TAG=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || echo "")

if [[ -z "$LAST_TAG" ]]; then
  # `describe` only reports tags reachable from HEAD. Version tags that exist but
  # are not ancestors mean this branch forked before the last release, which is a
  # completely different bump decision from a first release — and announcing
  # "first release" on a v4.x repo is a confidently wrong answer a human acts on.
  if [[ -n "$(git tag --list 'v[0-9]*')" ]]; then
    NEWEST_TAG=$(git tag --list 'v[0-9]*' --sort=-v:refname 2>/dev/null | head -n 1)
    echo "ERROR: version tags exist, but none is reachable from HEAD"
    echo "       Newest overall: ${NEWEST_TAG:-unknown}"
    echo "       This branch forked before the last release. Analyze from a branch"
    echo "       that includes it, or rebase onto the release line first."
    exit 1
  fi
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

# A skill that existed at the last tag and does not exist now is a breaking change
# for anyone who installed it, whatever the commit subject called it.
#
# This exists because v5.0.0 deleted 17 skills and renamed 2 across plugin groups,
# and every one of those commits was a `refactor:` or a `chore:`. Nobody wrote
# `!:` or a BREAKING CHANGE trailer, so the counters above reported Breaking: 0
# and this script recommended MINOR for the most breaking release the repo has had.
# Commit subjects are a claim about intent; the tree is the fact.
#
# Comparing path sets rather than parsing `--diff-filter=R` catches deletions and
# renames with one rule: a rename removes the old path, which is exactly the thing
# that breaks a user's `/slash` command.
skill_paths_at() {
  git ls-tree -r --name-only "$1" 2>/dev/null |
    grep -E '^[a-z][a-z-]*/skills/[a-z0-9-]+/SKILL\.md$' || true
}

REMOVED_SKILLS=$(comm -23 \
  <(skill_paths_at "$LAST_TAG" | sort) \
  <(skill_paths_at HEAD | sort) |
  sed -E 's#^([a-z-]+)/skills/([a-z0-9-]+)/SKILL\.md$#\2 (\1)#')

if [[ -n "$REMOVED_SKILLS" ]]; then
  REMOVED_SKILL_COUNT=$(printf '%s\n' "$REMOVED_SKILLS" | grep -c .)
else
  REMOVED_SKILL_COUNT=0
fi

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
echo "Skills gone:  $REMOVED_SKILL_COUNT"
echo ""

# Listed, not just counted: these names are what the release notes have to map for
# a user upgrading, and reconstructing them by hand after the fact is the slow way.
if [[ $REMOVED_SKILL_COUNT -gt 0 ]]; then
  echo "=== Skills Removed or Renamed Since $LAST_TAG ==="
  printf '%s\n' "$REMOVED_SKILLS"
  echo ""
  echo "Each is a breaking change for anyone who installed it. Map old -> new in the"
  echo "release notes; a rename is invisible to a user whose slash command stopped working."
  echo ""
fi

# Show file change stats
echo "=== File Changes ==="
git diff "$LAST_TAG"..HEAD --stat
echo ""

# Recommendation
echo "=== Recommendation ==="
if [[ $BREAKING_COUNT -gt 0 ]]; then
  echo "MAJOR bump (breaking changes detected)"
elif [[ $REMOVED_SKILL_COUNT -gt 0 ]]; then
  echo "MAJOR bump ($REMOVED_SKILL_COUNT skill(s) removed or renamed since $LAST_TAG)"
elif [[ $FEAT_COUNT -gt 0 ]]; then
  echo "MINOR bump (new features added)"
elif [[ $FIX_COUNT -gt 0 ]] || [[ $REFACTOR_COUNT -gt 0 ]]; then
  echo "PATCH bump (fixes or refactoring)"
elif [[ $DOCS_COUNT -gt 0 ]] || [[ $CHORE_COUNT -gt 0 ]] || [[ $STYLE_COUNT -gt 0 ]] || [[ $CI_COUNT -gt 0 ]] || [[ $TEST_COUNT -gt 0 ]]; then
  echo "PATCH bump (maintenance changes)"
else
  echo "MANUAL review needed (no conventional commits found)"
fi
