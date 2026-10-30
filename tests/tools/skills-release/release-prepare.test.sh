#!/usr/bin/env bash
# tools/skills-release/scripts/release-prepare.sh — the comparison with origin.
# A branch behind origin used to fail only at the push, after the release
# commit and tag existed; one ahead shipped unpushed commits unannounced.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

PREPARE="tools/skills-release/scripts/release-prepare.sh"

# A one-plugin repo at 1.0.0 pushed to a bare origin, shaped like this one: the
# plugin is the repo root, so its marketplace source is "./". The validators and
# sync-repo are stand-ins; sync-repo records that it ran, since it is the first
# step that writes to the tree.
skills_repo() {
  init_repo repo master
  cd repo
  mkdir -p .claude-plugin .github/scripts scripts/codex plugins/edloidas/.codex-plugin
  printf '{"plugins":[{"name":"edloidas","source":"./","version":"1.0.0"}]}\n' \
    > .claude-plugin/marketplace.json
  printf '{"version":"1.0.0"}\n' > .claude-plugin/plugin.json
  printf '{"version":"1.0.0","plugins":[{"name":"edloidas"}]}\n' > scripts/codex/catalog.json
  printf '{"version":"1.0.0"}\n' > plugins/edloidas/.codex-plugin/plugin.json
  printf '{"private":true,"version":"1.0.0"}\n' > package.json
  printf '#!/bin/bash\nexit 0\n' > .github/scripts/validate-skills.sh
  printf '#!/bin/bash\nexit 0\n' > scripts/validate-codex.sh
  printf '#!/bin/bash\ntouch "$SANDBOX/sync-ran"\n' > scripts/skills-packaging.sh
  chmod +x scripts/validate-codex.sh scripts/skills-packaging.sh
  git add -A
  git commit --quiet -m "chore: initial"
  add_remote master
}

# Advances origin/master by one commit from a second clone.
advance_origin() {
  git clone --quiet "$SANDBOX/origin.git" "$SANDBOX/other"
  (
    cd "$SANDBOX/other"
    git config user.name Test
    git config user.email test@example.com
    git config commit.gpgsign false
    commit "fix: pushed elsewhere"
    git push --quiet origin master
  )
}

test_in_sync_with_origin_passes() {
  skills_repo
  run bash "$(script "$PREPARE")"
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "SUCCESS: All pre-flight checks passed" "output"
}

test_behind_origin_refuses_before_any_write() {
  skills_repo
  advance_origin
  run bash "$(script "$PREPARE")"
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "1 commit(s) behind origin/master" "output"
  assert_contains "$STDOUT" "fix: pushed elsewhere" "output"
  assert_no_file "$SANDBOX/sync-ran"
}

test_ahead_of_origin_lists_the_commits_and_stops() {
  skills_repo
  commit "feat: local only"
  run bash "$(script "$PREPARE")"
  assert_eq 2 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Local-only commits (1)" "output"
  assert_contains "$STDOUT" "feat: local only" "output"
  assert_contains "$STDOUT" "STOP:" "output"
  assert_no_file "$SANDBOX/sync-ran"
}

test_ahead_with_allow_unpushed_continues() {
  skills_repo
  commit "feat: local only"
  run bash "$(script "$PREPARE")" --allow-unpushed
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "feat: local only" "output"
  assert_contains "$STDOUT" "SUCCESS: All pre-flight checks passed" "output"
}

test_unknown_argument_exits_1_before_any_write() {
  skills_repo
  run bash "$(script "$PREPARE")" --allow-unpushd
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Unknown argument: --allow-unpushd" "output"
  assert_no_file "$SANDBOX/sync-ran"
}

test_unreachable_origin_exits_1() {
  skills_repo
  git remote set-url origin "$SANDBOX/missing.git"
  run bash "$(script "$PREPARE")"
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Could not fetch origin/master" "output"
  assert_no_file "$SANDBOX/sync-ran"
}

run_tests
