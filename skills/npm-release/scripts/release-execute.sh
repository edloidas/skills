#!/bin/bash

# Release Execution Script
# Creates or verifies the release tag, then pushes the branch and the tag in one
# atomic push and confirms both on the remote.
# Usage: release-execute.sh [--branch <name>]
# Pass the same --branch given to release-prepare.sh, if any.
# Optimized for agent interpretation

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

RELEASE_BRANCH=""
if [[ "$1" == "--branch" ]]; then
  RELEASE_BRANCH="$2"
  if [[ -z "$RELEASE_BRANCH" ]]; then
    echo "ERROR: --branch needs a branch name"
    exit 1
  fi
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

BRANCH=$(git branch --show-current)
if [[ -z "$BRANCH" ]]; then
  echo "ERROR: Detached HEAD; check out the release branch first. Nothing was pushed."
  exit 1
fi

# The remote the branch tracks, else origin. The first listed remote may be a
# fork or a mirror, and a release pushed there publishes nothing.
REMOTE=$(git config --get "branch.$BRANCH.remote" 2>/dev/null || true)
if [[ -z "$REMOTE" ]] || [[ "$REMOTE" == "." ]]; then
  REMOTE="origin"
fi
if ! git remote get-url "$REMOTE" > /dev/null 2>&1; then
  echo "ERROR: No git remote configured: $BRANCH has no upstream and there is no 'origin'. Nothing was pushed."
  exit 1
fi

echo "Remote: $REMOTE"

signing_configured() {
  [[ -n "$(git config --get user.signingkey 2>/dev/null)" ]] ||
    [[ "$(git config --bool --get tag.gpgSign 2>/dev/null)" == "true" ]]
}

# The tag exists, is annotated, points at HEAD, and carries a signature whenever
# signing is configured.
verify_release_tag() {
  local tag="$1" head tag_commit

  if [[ "$(git cat-file -t "refs/tags/$tag" 2>/dev/null)" != "tag" ]]; then
    echo "ERROR: Tag $tag is lightweight; a release tag must be annotated. Nothing was pushed."
    return 1
  fi

  head=$(git rev-parse HEAD)
  tag_commit=$(git rev-parse "refs/tags/$tag^{commit}")
  if [[ "$tag_commit" != "$head" ]]; then
    echo "ERROR: Tag $tag points at ${tag_commit:0:12}, not HEAD (${head:0:12}). Nothing was pushed."
    return 1
  fi

  if signing_configured &&
    ! git cat-file tag "$tag" | grep -q -e '^-----BEGIN PGP SIGNATURE-----' -e '^-----BEGIN SSH SIGNATURE-----' -e '^-----BEGIN SIGNED MESSAGE-----'; then
    echo "ERROR: Signing is configured but tag $tag carries no signature. Nothing was pushed."
    return 1
  fi

  echo "Verified: tag $tag is annotated and points at HEAD"
}

# Re-checked here, not trusted from release-prepare.sh: the approval gate sits
# between the two, and the branch or the tree can change while it waits. Only the
# local tag step below separates these checks from the push.
if [[ -n "$RELEASE_BRANCH" ]]; then
  if [[ "$BRANCH" != "$RELEASE_BRANCH" ]]; then
    echo "ERROR: On $BRANCH, but the named release branch is $RELEASE_BRANCH. Nothing was pushed."
    exit 1
  fi
else
  DEFAULT_BRANCH=$(git symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null | sed "s|^$REMOTE/||" || true)
  if [[ -z "$DEFAULT_BRANCH" ]] && command -v gh &> /dev/null; then
    DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || true)
  fi
  if [[ -z "$DEFAULT_BRANCH" ]]; then
    echo "ERROR: Could not detect the default branch (no $REMOTE/HEAD, no gh). Nothing was pushed."
    echo "       Run 'git remote set-head $REMOTE --auto', or pass --branch <name>"
    exit 1
  fi
  if [[ "$BRANCH" != "$DEFAULT_BRANCH" ]]; then
    echo "ERROR: On $BRANCH, not the default branch $DEFAULT_BRANCH. Nothing was pushed."
    exit 1
  fi
fi

if [[ -n $(git status --porcelain) ]]; then
  echo "ERROR: Uncommitted changes detected. Nothing was pushed."
  git status --short
  exit 1
fi

if git rev-parse -q --verify "refs/tags/$TAG_NAME" > /dev/null; then
  echo "INFO: Tag $TAG_NAME already exists locally; verifying it before reuse"
else
  # -s implies -a
  if ! git tag -s "$TAG_NAME" -m "Release $TAG_NAME"; then
    echo "ERROR: Could not create signed tag $TAG_NAME. Nothing was pushed."
    exit 1
  fi
  echo "SUCCESS: Tag $TAG_NAME created"
fi

verify_release_tag "$TAG_NAME"

# --atomic: the remote accepts both refs or neither, so the branch can never
# land without the tag that releases it.
echo "Pushing $BRANCH and $TAG_NAME to $REMOTE..."
if ! git push --atomic "$REMOTE" "refs/heads/$BRANCH:refs/heads/$BRANCH" "refs/tags/$TAG_NAME:refs/tags/$TAG_NAME"; then
  echo "ERROR: Failed to push; the remote applied neither $BRANCH nor $TAG_NAME"
  exit 1
fi

HEAD_SHA=$(git rev-parse HEAD)
REMOTE_TAG_SHA=$(git ls-remote --tags "$REMOTE" "refs/tags/$TAG_NAME^{}" | awk '{print $1}')
REMOTE_BRANCH_SHA=$(git ls-remote --heads "$REMOTE" "refs/heads/$BRANCH" | awk '{print $1}')

if [[ "$REMOTE_TAG_SHA" != "$HEAD_SHA" ]]; then
  echo "ERROR: $TAG_NAME is not on $REMOTE at HEAD after the push (remote: ${REMOTE_TAG_SHA:-missing})"
  exit 1
fi

if [[ "$REMOTE_BRANCH_SHA" != "$HEAD_SHA" ]]; then
  echo "ERROR: $REMOTE/$BRANCH is not at HEAD after the push (remote: ${REMOTE_BRANCH_SHA:-missing})"
  exit 1
fi

echo "SUCCESS: $REMOTE has $BRANCH and $TAG_NAME at ${HEAD_SHA:0:12}"

echo ""
echo "Release $TAG_NAME completed successfully"

# Get remote URL for reference
REMOTE_URL=$(git remote get-url "$REMOTE" | sed 's/\.git$//')

echo ""
echo "=== Post-Release Verification ==="
echo "Package: https://www.npmjs.com/package/$PACKAGE_NAME"
echo "GitHub: $REMOTE_URL/releases"
