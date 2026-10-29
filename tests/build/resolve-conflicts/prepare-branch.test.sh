#!/usr/bin/env bash
# prepare-branch.sh — moves the local PR branch to its remote tip before a
# rebase. It replaced a `reset --hard`, so what matters is what it refuses:
# a dirty tree and commits that exist only locally must survive every run.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

PREPARE="build/skills/resolve-conflicts/scripts/prepare-branch.sh"

prepare() {
  run bash "$(script "$PREPARE")" "$@"
}

value_of() {
  printf '%s\n' "$STDOUT" | sed -n "s/^$1=//p"
}

# main and a published `feature`; the work tree is left on main.
published_repo() {
  init_repo repo main
  cd repo
  commit "initial"
  git checkout --quiet -b feature
  commit "feature work" feature.txt "feature"
  add_remote main
  git checkout --quiet main
}

test_moves_a_behind_branch_to_the_remote_tip() {
  published_repo
  local old remote
  old="$(git rev-parse feature)"
  git checkout --quiet feature
  commit "pushed elsewhere" feature.txt "more"
  push_branch feature
  remote="$(git rev-parse origin/feature)"
  git reset --quiet --keep "$old"
  git checkout --quiet main

  prepare feature
  assert_eq 0 "$STATUS" "exit status"
  assert_eq "$old" "$(value_of recovery)" "recovery"
  assert_eq "$remote" "$(value_of before)" "before"
  assert_eq "$remote" "$(git rev-parse HEAD)" "HEAD"
  assert_eq feature "$(git symbolic-ref --short HEAD)" "checked-out branch"
}

test_creates_the_branch_when_none_exists_locally() {
  published_repo
  git branch --quiet -D feature

  prepare feature
  assert_eq 0 "$STATUS" "exit status"
  assert_eq none "$(value_of recovery)" "recovery"
  assert_eq "$(git rev-parse origin/feature)" "$(git rev-parse HEAD)" "HEAD"
}

test_refuses_local_only_commits_and_leaves_them_in_place() {
  published_repo
  git checkout --quiet feature
  commit "local only" feature.txt "unpushed"
  local tip
  tip="$(git rev-parse HEAD)"

  prepare feature
  assert_eq 3 "$STATUS" "exit status"
  assert_contains "$STDERR" "local only" "listed commits"
  assert_eq "$tip" "$(value_of recovery)" "recovery"
  assert_eq "$tip" "$(git rev-parse feature)" "feature tip"
}

test_refuses_a_dirty_tree_and_keeps_the_edit() {
  published_repo
  printf 'uncommitted\n' >> file.txt

  prepare feature
  assert_eq 2 "$STATUS" "exit status"
  assert_contains "$(cat file.txt)" "uncommitted" "file.txt"
  assert_eq main "$(git symbolic-ref --short HEAD)" "checked-out branch"
}

test_refuses_untracked_files() {
  published_repo
  printf 'new\n' > untracked.txt

  prepare feature
  assert_eq 2 "$STATUS" "exit status"
  assert_file untracked.txt
}

test_missing_remote_branch_exits_4() {
  published_repo
  prepare nope
  assert_eq 4 "$STATUS" "exit status"
  assert_contains "$STDERR" "origin/nope not found" "error output"
}

# `git switch` refuses a branch another worktree has checked out, so the script
# names that worktree instead of failing halfway.
test_branch_checked_out_in_another_worktree_exits_5() {
  published_repo
  git worktree add --quiet ../elsewhere feature
  git worktree add --quiet --detach ../work

  cd ../work
  prepare feature
  assert_eq 5 "$STATUS" "exit status"
  assert_contains "$STDOUT" "worktree=" "worktree line"
  assert_contains "$(value_of worktree)" "elsewhere" "reported worktree"
  assert_eq "" "$(git symbolic-ref -q --short HEAD || true)" "work stays detached"
}

test_branch_checked_out_in_this_worktree_is_moved() {
  published_repo
  git checkout --quiet feature

  prepare feature
  assert_eq 0 "$STATUS" "exit status"
  assert_eq "$(git rev-parse origin/feature)" "$(git rev-parse HEAD)" "HEAD"
}

# A fork PR's head lives on a remote other than origin.
test_named_remote_is_used_instead_of_origin() {
  published_repo
  git remote rename origin fork
  git branch --quiet -D feature

  prepare feature fork
  assert_eq 0 "$STATUS" "exit status"
  assert_eq "$(git rev-parse fork/feature)" "$(value_of before)" "before"
  assert_eq feature "$(git symbolic-ref --short HEAD)" "checked-out branch"
}

test_no_argument_exits_1() {
  published_repo
  prepare
  assert_eq 1 "$STATUS" "exit status"
}

run_tests
