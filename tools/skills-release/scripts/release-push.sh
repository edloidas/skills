#!/bin/bash

# Release Push Script
# Pushes the release commit and its tag together, then confirms both landed.
# Refuses to push anything unless the tag exists, is annotated, points at HEAD,
# and is signed when signing is configured.
# Usage: release-push.sh <version>

set -e

. "$(dirname "$0")/release-tag.sh"

VERSION="$1"

if [[ -z "$VERSION" ]]; then
  echo "ERROR: Version argument required"
  echo "Usage: release-push.sh <version>"
  exit 1
fi

if ! echo "$VERSION" | grep -qE "^[0-9]+\.[0-9]+\.[0-9]+$"; then
  echo "ERROR: Invalid version format: $VERSION"
  echo "Expected: X.Y.Z (e.g., 1.1.0)"
  exit 1
fi

TAG_NAME="v$VERSION"
REMOTE="origin"

if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "ERROR: Not a git repository"
  exit 1
fi

BRANCH=$(git branch --show-current)
if [[ -z "$BRANCH" ]]; then
  echo "ERROR: Detached HEAD; check out the release branch first. Nothing was pushed."
  exit 1
fi

if ! git remote get-url "$REMOTE" > /dev/null 2>&1; then
  echo "ERROR: No '$REMOTE' remote configured. Nothing was pushed."
  exit 1
fi

if ! verify_release_tag "$TAG_NAME"; then
  echo "ERROR: Refusing to push $BRANCH without a valid $TAG_NAME. Nothing was pushed."
  exit 1
fi

# --atomic: the remote accepts both refs or neither, so the branch can never
# land without the tag that releases it.
echo "Pushing $BRANCH and $TAG_NAME to $REMOTE..."
if ! git push --atomic "$REMOTE" "refs/heads/$BRANCH:refs/heads/$BRANCH" "refs/tags/$TAG_NAME:refs/tags/$TAG_NAME"; then
  echo "ERROR: Push rejected; the remote applied neither $BRANCH nor $TAG_NAME"
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
