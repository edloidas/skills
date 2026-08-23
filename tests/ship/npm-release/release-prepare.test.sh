#!/usr/bin/env bash
# release-prepare.sh — the gate in front of a publish. Every one of its checks
# exists to stop a release, so the cases that matter are the refusals: a wrong
# branch, a dirty tree, a lockfile whose package manager is not installed.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

PREPARE="ship/skills/npm-release/scripts/release-prepare.sh"

prepare() {
  run bash "$(script "$PREPARE")"
}

# A clean package repo on `main`, with PATH isolated so no real package manager
# leaks in.
pkg_repo() {
  local branch="${1:-main}"
  stub_path > /dev/null
  init_repo repo "$branch"
  cd repo
  printf '{"name":"demo","version":"1.2.3"}\n' > package.json
  commit "initial" package.json '{"name":"demo","version":"1.2.3"}'
  # `commit` appends, so rewrite the file it just committed.
  printf '{"name":"demo","version":"1.2.3"}\n' > package.json
  git add package.json
  git commit --quiet --amend --no-edit
}

# A package manager that reports the dry-run outcome the case wants.
stub_pm() {
  local name="$1" code="${2:-0}"
  stub "$name" <<EOF
printf 'dry-run invoked: %s\\n' "\$*"
exit $code
EOF
}

# --------------------------------------------------------------- preconditions --

test_outside_a_git_repository_exits_1() {
  mkdir -p empty
  cd empty
  printf '{"name":"demo","version":"1.0.0"}\n' > package.json
  prepare
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Not a git repository" "output"
}

test_missing_package_json_exits_1() {
  stub_path > /dev/null
  init_repo repo main
  cd repo
  commit "initial"
  prepare
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "No package.json found" "output"
}

test_wrong_branch_exits_1() {
  pkg_repo main
  git checkout --quiet -b feature
  stub_pm pnpm 0
  prepare
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Not on master or main branch" "output"
  assert_not_contains "$STDOUT" "dry-run invoked" "output"
}

test_master_is_accepted() {
  pkg_repo master
  stub_pm pnpm 0
  prepare
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Branch: master" "output"
}

# Detached HEAD has no branch name, so the branch check must refuse rather than
# treat an empty name as acceptable.
test_detached_head_exits_1() {
  pkg_repo main
  commit "second"
  git checkout --quiet HEAD~1
  stub_pm pnpm 0
  prepare
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Not on master or main branch" "output"
}

test_uncommitted_changes_exit_1() {
  pkg_repo main
  printf 'dirty\n' >> file.txt
  stub_pm pnpm 0
  prepare
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Uncommitted changes detected" "output"
  assert_not_contains "$STDOUT" "dry-run invoked" "output"
}

# An untracked file is a change too — releasing with one is releasing something
# that is not in the tag.
test_untracked_files_exit_1() {
  pkg_repo main
  printf 'new\n' > untracked.txt
  stub_pm pnpm 0
  prepare
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Uncommitted changes detected" "output"
}

# --------------------------------------------------- package manager detection --
# A lockfile means the repo has opted into that manager. Honoring it and failing
# loudly when the tool is missing is the point — silently falling through to a
# different manager would resolve a different dependency tree.

test_pnpm_lockfile_selects_pnpm() {
  pkg_repo main
  : > pnpm-lock.yaml
  git add pnpm-lock.yaml && git commit --quiet -m "lockfile"
  stub_pm pnpm 0
  stub_pm npm 0
  prepare
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Package manager: pnpm" "output"
  assert_contains "$STDOUT" "dry-run invoked: release:dry" "output"
}

test_pnpm_lockfile_without_pnpm_exits_1() {
  pkg_repo main
  : > pnpm-lock.yaml
  git add pnpm-lock.yaml && git commit --quiet -m "lockfile"
  stub_pm npm 0
  prepare
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "pnpm-lock.yaml found but pnpm not installed" "output"
  assert_not_contains "$STDOUT" "dry-run invoked" "output"
}

test_bun_lockfile_selects_bun() {
  pkg_repo main
  : > bun.lock
  git add bun.lock && git commit --quiet -m "lockfile"
  stub_pm bun 0
  stub_pm npm 0
  prepare
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Package manager: bun" "output"
  assert_contains "$STDOUT" "dry-run invoked: run release:dry" "output"
}

test_binary_bun_lockfile_selects_bun() {
  pkg_repo main
  : > bun.lockb
  git add bun.lockb && git commit --quiet -m "lockfile"
  stub_pm bun 0
  prepare
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Package manager: bun" "output"
}

test_npm_lockfile_selects_npm() {
  pkg_repo main
  : > package-lock.json
  git add package-lock.json && git commit --quiet -m "lockfile"
  stub_pm npm 0
  stub_pm pnpm 0
  prepare
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Package manager: npm" "output"
  assert_contains "$STDOUT" "dry-run invoked: publish --dry-run" "output"
}

# Without a lockfile there is nothing to honor, so availability decides in
# preference order: pnpm, then bun, then npm.
test_no_lockfile_prefers_pnpm() {
  pkg_repo main
  stub_pm pnpm 0
  stub_pm bun 0
  stub_pm npm 0
  prepare
  assert_contains "$STDOUT" "Package manager: pnpm" "output"
}

test_no_lockfile_falls_back_to_bun_then_npm() {
  pkg_repo main
  stub_pm bun 0
  stub_pm npm 0
  prepare
  assert_contains "$STDOUT" "Package manager: bun" "output"
}

test_no_lockfile_and_only_npm_selects_npm() {
  pkg_repo main
  stub_pm npm 0
  prepare
  assert_contains "$STDOUT" "Package manager: npm" "output"
}

test_no_package_manager_at_all_exits_1() {
  pkg_repo main
  prepare
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "No supported package manager found" "output"
}

# -------------------------------------------------------------------- dry run --

test_failing_dry_run_exits_1() {
  pkg_repo main
  : > pnpm-lock.yaml
  git add pnpm-lock.yaml && git commit --quiet -m "lockfile"
  stub_pm pnpm 1
  prepare
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Release dry-run failed" "output"
  assert_not_contains "$STDOUT" "All pre-flight checks passed" "output"
}

test_passing_dry_run_reports_success() {
  pkg_repo main
  : > pnpm-lock.yaml
  git add pnpm-lock.yaml && git commit --quiet -m "lockfile"
  stub_pm pnpm 0
  prepare
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "SUCCESS: All pre-flight checks passed" "output"
}

run_tests
