#!/usr/bin/env bash
# release-execute.sh — the irreversible half: it tags and pushes. Nothing here
# is allowed to reach a remote by accident, so every case either uses a local
# bare repo as `origin` or asserts the script refused before pushing.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

EXECUTE="ship/skills/npm-release/scripts/release-execute.sh"

execute() {
  run bash "$(script "$EXECUTE")"
}

# A repo whose package.json declares <version>, with `origin` pointing at a
# local bare repo. No signing key is configured, which is the machine state the
# signed-tag cases exercise.
pkg_repo() {
  local version="${1:-1.2.3}"
  init_repo repo main
  cd repo
  printf '{"name":"@demo/pkg","version":"%s"}\n' "$version" > package.json
  git add package.json
  git commit --quiet -m "initial"
  add_remote main
}

# The tag the script would create, made unsigned so the cases past tag creation
# are reachable without a GPG key.
pre_tag() {
  git tag -a "$1" -m "Release $1"
}

# ------------------------------------------------------------- preconditions --

test_outside_a_git_repository_exits_1() {
  mkdir -p empty
  cd empty
  printf '{"name":"demo","version":"1.0.0"}\n' > package.json
  execute
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Not a git repository" "output"
}

test_missing_jq_exits_1() {
  pkg_repo 1.2.3
  unstub jq
  execute
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "jq is required" "output"
}

test_package_json_without_a_version_exits_1() {
  init_repo repo main
  cd repo
  printf '{"name":"demo"}\n' > package.json
  git add package.json
  git commit --quiet -m "initial"
  add_remote main
  execute
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Could not read version" "output"
}

test_version_is_read_from_package_json() {
  pkg_repo 4.5.6
  pre_tag v4.5.6
  execute
  assert_contains "$STDOUT" "Version: 4.5.6" "output"
  assert_contains "$STDOUT" "Tag: v4.5.6" "output"
}

# ------------------------------------------------------------ tag and push ----

test_existing_tag_is_not_recreated() {
  pkg_repo 1.2.3
  pre_tag v1.2.3
  execute
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Tag v1.2.3 already exists locally" "output"
  assert_contains "$STDOUT" "Skipping tag creation" "output"
  assert_eq 1 "$(git tag -l 'v1.2.3' | wc -l | tr -d ' ')" "tag count"
}

test_commits_and_tag_reach_the_remote() {
  pkg_repo 1.2.3
  pre_tag v1.2.3
  local bare="$PWD/../origin.git"
  execute
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "SUCCESS: Commits and tag pushed" "output"
  assert_contains "$STDOUT" "Release v1.2.3 completed successfully" "output"
  assert_eq "v1.2.3" "$(git -C "$bare" tag -l)" "tags on the remote"
  assert_eq "$(git rev-parse HEAD)" "$(git -C "$bare" rev-parse refs/heads/main)" \
    "remote main tip"
}

# `--follow-tags` only pushes annotated tags, which is why the script signs. A
# lightweight tag left over from a previous release must not be mistaken for
# the annotated one and silently left behind.
test_a_lightweight_existing_tag_is_not_pushed() {
  pkg_repo 1.2.3
  git tag v1.2.3
  execute
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Skipping tag creation" "output"
  assert_eq "" "$(git -C "$PWD/../origin.git" tag -l)" "tags on the remote"
}

test_no_remote_exits_1() {
  init_repo repo main
  cd repo
  printf '{"name":"demo","version":"1.2.3"}\n' > package.json
  git add package.json
  git commit --quiet -m "initial"
  pre_tag v1.2.3
  execute
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "No git remote configured" "output"
}

# A rejected push must not be reported as a completed release.
test_a_rejected_push_exits_1() {
  pkg_repo 1.2.3
  pre_tag v1.2.3
  local bare="$PWD/../origin.git"
  # Move the remote ahead so a non-fast-forward push is rejected.
  git -C "$bare" symbolic-ref HEAD refs/heads/main
  git clone --quiet "$bare" ../other
  git -C ../other config user.email test@example.com
  git -C ../other config user.name Test
  printf 'remote work\n' > ../other/remote.txt
  git -C ../other add remote.txt
  git -C ../other commit --quiet -m "remote moves ahead"
  git -C ../other push --quiet origin main

  execute
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Failed to push" "output"
  assert_not_contains "$STDOUT" "completed successfully" "output"
}

# Tag creation is signed on purpose. On a machine with no signing key it has to
# fail rather than fall back to an unsigned tag, and it must not push.
test_signing_failure_stops_the_release() {
  pkg_repo 1.2.3
  git config --unset-all user.signingkey 2>/dev/null || true
  git config gpg.program /nonexistent-gpg
  local bare="$PWD/../origin.git"
  execute
  assert_ne 0 "$STATUS" "exit status"
  assert_not_contains "$STDOUT" "completed successfully" "output"
  assert_eq "" "$(git -C "$bare" tag -l)" "tags on the remote"
}

# The post-release block names the package and the releases page, and both come
# from data the script read rather than a hardcoded org.
test_post_release_links_use_the_real_package_and_remote() {
  pkg_repo 1.2.3
  pre_tag v1.2.3
  execute
  assert_contains "$STDOUT" "https://www.npmjs.com/package/@demo/pkg" "output"
  assert_contains "$STDOUT" "/releases" "output"
}

run_tests
