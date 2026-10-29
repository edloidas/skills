#!/usr/bin/env bash
# Phase 2 resolves a trivial conflict with `git checkout --<side>`, where the
# classifier names the side by marker position: the block after `<<<<<<<` is
# ours, the block before `>>>>>>>` is theirs. That holds in a merge and in a
# rebase alike, even though which branch "ours" means flips between the two —
# a fixed `--theirs` kept the feature branch in a rebase and threw it away in a
# merge. These cases pin the mapping the prose relies on.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

# main and feature both change shared.txt; the caller picks merge or rebase.
diverged_repo() {
  init_repo repo main
  cd repo
  printf 'original\n' > shared.txt
  git add shared.txt
  git commit --quiet -m initial
  git checkout --quiet -b feature
  printf 'feature\n' > shared.txt
  git commit --quiet -am feature
  git checkout --quiet main
  printf 'main\n' > shared.txt
  git commit --quiet -am main
}

first_block() {
  sed -n '/^<<<<<<< /,/^=======/p' shared.txt | sed '1d;$d'
}

second_block() {
  sed -n '/^=======/,/^>>>>>>> /p' shared.txt | sed '1d;$d'
}

checkout_side() {
  git checkout --quiet "--$1" -- shared.txt
  cat shared.txt
}

test_merge_first_marker_block_is_ours() {
  diverged_repo
  git checkout --quiet feature
  git merge --quiet main > /dev/null 2>&1 || true
  assert_eq feature "$(first_block)" "first block"
  assert_eq feature "$(checkout_side ours)" "--ours"
}

test_merge_second_marker_block_is_theirs() {
  diverged_repo
  git checkout --quiet feature
  git merge --quiet main > /dev/null 2>&1 || true
  assert_eq main "$(second_block)" "second block"
  assert_eq main "$(checkout_side theirs)" "--theirs"
}

test_rebase_first_marker_block_is_ours() {
  diverged_repo
  git checkout --quiet feature
  git rebase --quiet main > /dev/null 2>&1 || true
  assert_eq main "$(first_block)" "first block"
  assert_eq main "$(checkout_side ours)" "--ours"
}

test_rebase_second_marker_block_is_theirs() {
  diverged_repo
  git checkout --quiet feature
  git rebase --quiet main > /dev/null 2>&1 || true
  assert_eq feature "$(second_block)" "second block"
  assert_eq feature "$(checkout_side theirs)" "--theirs"
}

run_tests
