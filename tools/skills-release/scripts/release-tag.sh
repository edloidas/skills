#!/bin/bash

# Release tag helpers, sourced by release-bump.sh and release-push.sh.
# A release commit without its tag must never reach the remote, so the tag is
# created and checked here, and checked again immediately before every push.

# Signing is configured when git would know which key to use, or was told to
# sign every tag. Without either, `git tag -s` can only fail.
signing_configured() {
  [[ -n "$(git config --get user.signingkey 2>/dev/null)" ]] ||
    [[ "$(git config --bool --get tag.gpgSign 2>/dev/null)" == "true" ]]
}

# create_release_tag <tag>
create_release_tag() {
  local tag="$1"
  local mode="-a"
  if signing_configured; then
    mode="-s"
  else
    echo "WARNING: No signing key configured (user.signingkey, tag.gpgSign); creating an unsigned annotated tag"
  fi

  if ! git tag "$mode" "$tag" -m "Release $tag"; then
    echo "ERROR: Could not create tag $tag — signing failed or git refused the tag"
    echo "       The release commit exists locally without its tag. Nothing was pushed."
    echo "       Fix signing, then tag it:   git tag $mode $tag -m \"Release $tag\""
    echo "       Or drop the commit:         git reset --hard HEAD~1"
    return 1
  fi
}

# verify_release_tag <tag>
# The tag exists, is annotated, points at HEAD, and carries a signature
# whenever signing is configured.
verify_release_tag() {
  local tag="$1"
  local head tag_commit

  if [[ "$(git cat-file -t "refs/tags/$tag" 2>/dev/null)" != "tag" ]]; then
    if git rev-parse -q --verify "refs/tags/$tag" > /dev/null; then
      echo "ERROR: Tag $tag is lightweight; a release tag must be annotated"
    else
      echo "ERROR: Tag $tag does not exist locally"
    fi
    return 1
  fi

  head=$(git rev-parse HEAD)
  tag_commit=$(git rev-parse "refs/tags/$tag^{commit}")
  if [[ "$tag_commit" != "$head" ]]; then
    echo "ERROR: Tag $tag points at ${tag_commit:0:12}, not HEAD (${head:0:12})"
    return 1
  fi

  if signing_configured &&
    ! git cat-file tag "$tag" | grep -q -e '^-----BEGIN PGP SIGNATURE-----' -e '^-----BEGIN SSH SIGNATURE-----' -e '^-----BEGIN SIGNED MESSAGE-----'; then
    echo "ERROR: Signing is configured but tag $tag carries no signature"
    return 1
  fi

  if signing_configured; then
    echo "Verified: tag $tag is annotated, signed, and points at HEAD"
  else
    echo "Verified: tag $tag is annotated and points at HEAD (unsigned)"
  fi
}
