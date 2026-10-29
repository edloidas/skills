#!/usr/bin/env bash
# release-bump.sh, release-push.sh, release-execute.sh — the half of the skills
# release that cannot be recalled. The case that matters: a tag that could not
# be created or verified must stop the run before anything reaches the remote.
# A real v5.18.0 run lost its tag to a GPG failure hidden behind `| tail` and
# pushed master anyway.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

BUMP="tools/skills-release/scripts/release-bump.sh"
PUSH="tools/skills-release/scripts/release-push.sh"
EXECUTE="tools/skills-release/scripts/release-execute.sh"

# A two-plugin repo shaped like this one at version 1.0.0, pushed to a bare
# origin. skills-packaging.sh is replaced by a stand-in that does only what
# release-bump.sh relies on: copy the catalog version into the Codex wrappers.
skills_repo() {
  init_repo repo master
  cd repo
  mkdir -p .claude-plugin scripts/codex plan/.claude-plugin build/.claude-plugin \
    plugins/edloidas-plan/.codex-plugin
  printf '{"plugins":[{"name":"plan","source":"./plan","version":"1.0.0"},{"name":"build","source":"./build","version":"1.0.0"}]}\n' \
    > .claude-plugin/marketplace.json
  printf '{"version":"1.0.0"}\n' > plan/.claude-plugin/plugin.json
  printf '{"version":"1.0.0"}\n' > build/.claude-plugin/plugin.json
  printf '{"version":"1.0.0","plugins":[{"name":"edloidas-plan"}]}\n' > scripts/codex/catalog.json
  printf '{"version":"1.0.0"}\n' > plugins/edloidas-plan/.codex-plugin/plugin.json
  printf '{"private":true,"version":"1.0.0"}\n' > package.json
  cat > scripts/skills-packaging.sh <<'EOF'
#!/bin/bash
v=$(jq -r '.version' scripts/codex/catalog.json)
for f in plugins/*/.codex-plugin/plugin.json; do
  jq --arg v "$v" '.version = $v' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done
EOF
  chmod +x scripts/skills-packaging.sh
  git add -A
  git commit --quiet -m "chore: initial"
  add_remote master
}

# Signing configured, with gpg.program pointing at a stub. `ok` emits an
# armored block and the status line git waits for; `fail` exits 2 the way gpg
# does with no usable secret key.
use_gpg() {
  local mode="$1" gpg="$SANDBOX/fake-gpg"
  if [ "$mode" = ok ]; then
    cat > "$gpg" <<'EOF'
#!/bin/bash
cat > /dev/null
echo '[GNUPG:] SIG_CREATED D 1 8 00 1700000000 ABC' >&2
printf -- '-----BEGIN PGP SIGNATURE-----\n\nZmFrZQ==\n-----END PGP SIGNATURE-----\n'
EOF
  else
    cat > "$gpg" <<'EOF'
#!/bin/bash
cat > /dev/null
echo 'gpg: signing failed: No secret key' >&2
exit 2
EOF
  fi
  chmod +x "$gpg"
  git config user.signingkey ABC
  git config gpg.program "$gpg"
}

remote_ref() {
  git ls-remote origin "$1" | awk '{print $1}'
}

# --------------------------------------------------------------- bump -------

test_signing_failure_exits_nonzero_and_leaves_no_tag() {
  skills_repo
  use_gpg fail
  run bash "$(script "$BUMP")" 1.1.0
  assert_ne 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Could not create tag v1.1.0" "output"
  assert_contains "$STDOUT" "Nothing was pushed" "output"
  assert_eq "" "$(git tag -l v1.1.0)" "local tag"
}

test_bump_creates_a_signed_tag_at_head_when_signing_is_configured() {
  skills_repo
  use_gpg ok
  run bash "$(script "$BUMP")" 1.1.0
  assert_eq 0 "$STATUS" "exit status"
  assert_eq "$(git rev-parse HEAD)" "$(git rev-parse 'v1.1.0^{commit}')" "tag target"
  assert_contains "$(git cat-file tag v1.1.0)" "BEGIN PGP SIGNATURE" "tag object"
  assert_contains "$STDOUT" "annotated, signed, and points at HEAD" "output"
}

test_bump_without_signing_creates_an_annotated_tag_and_says_so() {
  skills_repo
  run bash "$(script "$BUMP")" 1.1.0
  assert_eq 0 "$STATUS" "exit status"
  assert_eq tag "$(git cat-file -t refs/tags/v1.1.0)" "tag type"
  assert_contains "$STDOUT" "creating an unsigned annotated tag" "output"
}

# --------------------------------------------------------------- push -------

test_push_without_the_tag_pushes_nothing() {
  skills_repo
  before="$(remote_ref refs/heads/master)"
  commit "Release v1.1.0"
  run bash "$(script "$PUSH")" 1.1.0
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Tag v1.1.0 does not exist locally" "output"
  assert_contains "$STDOUT" "Nothing was pushed" "output"
  assert_eq "$before" "$(remote_ref refs/heads/master)" "remote master"
}

test_push_refuses_a_tag_that_is_not_at_head() {
  skills_repo
  git tag -a v1.1.0 -m "Release v1.1.0"
  commit "later"
  run bash "$(script "$PUSH")" 1.1.0
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "not HEAD" "output"
  assert_eq "" "$(remote_ref refs/tags/v1.1.0)" "remote tag"
}

test_push_refuses_a_lightweight_tag() {
  skills_repo
  git tag v1.1.0
  run bash "$(script "$PUSH")" 1.1.0
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "lightweight" "output"
}

test_push_refuses_an_unsigned_tag_when_signing_is_configured() {
  skills_repo
  git tag -a v1.1.0 -m "Release v1.1.0"
  use_gpg ok
  run bash "$(script "$PUSH")" 1.1.0
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "carries no signature" "output"
  assert_eq "" "$(remote_ref refs/tags/v1.1.0)" "remote tag"
}

test_bump_then_push_lands_commit_and_tag_on_the_remote() {
  skills_repo
  use_gpg ok
  run bash "$(script "$BUMP")" 1.1.0
  assert_eq 0 "$STATUS" "bump exit status"
  run bash "$(script "$PUSH")" 1.1.0
  assert_eq 0 "$STATUS" "push exit status"
  head="$(git rev-parse HEAD)"
  assert_eq "$head" "$(remote_ref refs/heads/master)" "remote master"
  assert_eq "$head" "$(remote_ref 'refs/tags/v1.1.0^{}')" "remote tag target"
  assert_contains "$STDOUT" "SUCCESS: origin has master and v1.1.0" "output"
}

# ------------------------------------------------------------- execute ------

test_execute_with_a_signing_failure_pushes_nothing() {
  skills_repo
  use_gpg fail
  before="$(remote_ref refs/heads/master)"
  run bash "$(script "$EXECUTE")" 1.1.0
  assert_ne 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "nothing was pushed" "output"
  assert_eq "$before" "$(remote_ref refs/heads/master)" "remote master"
  assert_eq "" "$(remote_ref refs/tags/v1.1.0)" "remote tag"
}

test_execute_lands_commit_and_tag_on_the_remote() {
  skills_repo
  run bash "$(script "$EXECUTE")" 1.1.0
  assert_eq 0 "$STATUS" "exit status"
  head="$(git rev-parse HEAD)"
  assert_eq "$head" "$(remote_ref refs/heads/master)" "remote master"
  assert_eq "$head" "$(remote_ref 'refs/tags/v1.1.0^{}')" "remote tag target"
  assert_eq 1.1.0 "$(git show HEAD:package.json | jq -r .version)" "package.json version"
}

run_tests
