#!/usr/bin/env bash
# resolve-side.sh — Phase 2's resolution of a trivial UU or AA conflict. It
# replaced a whole-file `git checkout --<side>`, which took one side's entire
# file and silently dropped the other side's hunks that git had merged cleanly.
# What matters is that only the conflict blocks pick a side.
#
# The classifier names the side by marker position: the block after `<<<<<<<`
# is ours, the block before `>>>>>>>` is theirs. That holds in a merge and in a
# rebase alike, even though which branch "ours" means flips between the two.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

RESOLVE="skills/resolve-conflicts/scripts/resolve-side.sh"

resolve() {
  run bash "$(script "$RESOLVE")" "$@"
}

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
  sed -n '/^<<<<<<< /,/^=======/p' shared.txt | sed '1d;$d' | sed '/^||||||| /,$d'
}

second_block() {
  sed -n '/^=======/,/^>>>>>>> /p' shared.txt | sed '1d;$d'
}

resolved_to() {
  resolve "$1" shared.txt
  cat shared.txt
}

# ----------------------------------------------------- marker position → side --

test_merge_first_marker_block_is_ours() {
  diverged_repo
  git checkout --quiet feature
  git merge --quiet main > /dev/null 2>&1 || true
  assert_eq feature "$(first_block)" "first block"
  assert_eq feature "$(resolved_to ours)" "resolved to ours"
}

test_merge_second_marker_block_is_theirs() {
  diverged_repo
  git checkout --quiet feature
  git merge --quiet main > /dev/null 2>&1 || true
  assert_eq main "$(second_block)" "second block"
  assert_eq main "$(resolved_to theirs)" "resolved to theirs"
}

test_rebase_first_marker_block_is_ours() {
  diverged_repo
  git checkout --quiet feature
  git rebase --quiet main > /dev/null 2>&1 || true
  assert_eq main "$(first_block)" "first block"
  assert_eq main "$(resolved_to ours)" "resolved to ours"
}

test_rebase_second_marker_block_is_theirs() {
  diverged_repo
  git checkout --quiet feature
  git rebase --quiet main > /dev/null 2>&1 || true
  assert_eq feature "$(second_block)" "second block"
  assert_eq feature "$(resolved_to theirs)" "resolved to theirs"
}

# ------------------------------------------------- clean hunks are preserved --

# feature adds a function at the top (merges cleanly); both sides change the
# last line (conflicts). The caller picks merge or rebase afterwards.
clean_plus_conflict_repo() {
  init_repo repo main
  cd repo
  printf 'a\nb\nc\nd\ne\nf\nlast\n' > code.txt
  git add code.txt
  git commit --quiet -m initial
  git checkout --quiet -b feature
  printf 'function added() {}\na\nb\nc\nd\ne\nf\nfeature-last\n' > code.txt
  git commit --quiet -am feature
  git checkout --quiet main
  printf 'a\nb\nc\nd\ne\nf\nmain-last\n' > code.txt
  git commit --quiet -am main
}

# In a merge into main, feature is theirs: resolving toward ours must still keep
# the function feature added, which the whole-file checkout threw away.
test_resolving_toward_ours_keeps_the_clean_addition_from_theirs() {
  clean_plus_conflict_repo
  git merge --quiet feature > /dev/null 2>&1 || true

  resolve ours code.txt
  assert_eq 0 "$STATUS" "exit status"
  assert_eq "$(printf 'function added() {}\na\nb\nc\nd\ne\nf\nmain-last')" "$(cat code.txt)" "code.txt"
  assert_eq "" "$(git diff --name-only --diff-filter=U)" "unmerged paths"
}

# In a rebase of feature onto main, feature is theirs and main is ours.
# Resolving toward main's line must keep feature's own clean addition.
test_rebase_resolving_toward_ours_keeps_the_replayed_clean_addition() {
  clean_plus_conflict_repo
  git checkout --quiet feature
  git rebase --quiet main > /dev/null 2>&1 || true

  resolve ours code.txt
  assert_eq 0 "$STATUS" "exit status"
  assert_eq "$(printf 'function added() {}\na\nb\nc\nd\ne\nf\nmain-last')" "$(cat code.txt)" "code.txt"
}

# Merging main into feature puts the addition on ours; resolving toward theirs
# must keep it.
test_resolving_toward_theirs_keeps_the_clean_addition_from_ours() {
  clean_plus_conflict_repo
  git checkout --quiet feature
  git merge --quiet main > /dev/null 2>&1 || true

  resolve theirs code.txt
  assert_eq 0 "$STATUS" "exit status"
  assert_eq "$(printf 'function added() {}\na\nb\nc\nd\ne\nf\nmain-last')" "$(cat code.txt)" "code.txt"
}

# Pins why the script exists: the whole-file checkout it replaced loses the
# clean hunk on exactly this fixture.
test_whole_file_checkout_loses_the_clean_addition() {
  clean_plus_conflict_repo
  git merge --quiet feature > /dev/null 2>&1 || true

  git checkout --quiet --ours code.txt
  assert_not_contains "$(cat code.txt)" "function added" "code.txt after checkout --ours"
}

# A both-added file has no base stage; the script stands in an empty one.
test_both_added_file_resolves_without_a_base() {
  init_repo repo main
  cd repo
  commit "initial"
  git checkout --quiet -b feature
  printf 'same\nfeature\n' > added.txt
  git add added.txt
  git commit --quiet -m "feature adds"
  git checkout --quiet main
  printf 'same\nmain\n' > added.txt
  git add added.txt
  git commit --quiet -m "main adds"
  git merge --quiet feature > /dev/null 2>&1 || true

  resolve theirs added.txt
  assert_eq 0 "$STATUS" "exit status"
  assert_not_contains "$(cat added.txt)" "<<<<<<<" "added.txt"
  assert_contains "$(cat added.txt)" "feature" "added.txt"
  assert_eq "" "$(git diff --name-only --diff-filter=U)" "unmerged paths"
}

test_path_with_a_space_is_resolved_from_a_subdirectory() {
  init_repo repo main
  cd repo
  commit "initial" "dir name/a file.txt" "base"
  git checkout --quiet -b feature
  printf 'feature\n' > "dir name/a file.txt"
  git commit --quiet -am feature
  git checkout --quiet main
  printf 'main\n' > "dir name/a file.txt"
  git commit --quiet -am main
  git merge --quiet feature > /dev/null 2>&1 || true

  cd "dir name"
  resolve ours "dir name/a file.txt"
  assert_eq 0 "$STATUS" "exit status"
  assert_eq main "$(cat "a file.txt")" "a file.txt"
}

# ------------------------------------------------------------ failure modes --

test_a_path_that_is_not_unmerged_exits_2() {
  diverged_repo
  resolve ours shared.txt
  assert_eq 2 "$STATUS" "exit status"
  assert_contains "$STDERR" "not unmerged" "error output"
}

test_a_delete_modify_conflict_exits_2_and_is_left_alone() {
  init_repo repo main
  cd repo
  commit "initial" shared.txt "original"
  git checkout --quiet -b feature
  commit "feature modifies" shared.txt "more"
  git checkout --quiet main
  git rm --quiet shared.txt
  git commit --quiet -m "main deletes"
  git merge --quiet feature > /dev/null 2>&1 || true

  resolve theirs shared.txt
  assert_eq 2 "$STATUS" "exit status"
  assert_contains "$(git status --porcelain)" "DU shared.txt" "still unresolved"
}

test_a_binary_conflict_exits_3_and_keeps_the_work_tree_file() {
  init_repo repo main
  cd repo
  printf 'base\0bin\n' > blob.bin
  git add blob.bin
  git commit --quiet -m initial
  git checkout --quiet -b feature
  printf 'feature\0bin\n' > blob.bin
  git commit --quiet -am feature
  git checkout --quiet main
  printf 'main\0bin\n' > blob.bin
  git commit --quiet -am main
  git merge --quiet feature > /dev/null 2>&1 || true
  local before
  before="$(od -c blob.bin)"

  resolve ours blob.bin
  assert_eq 3 "$STATUS" "exit status"
  assert_eq "$before" "$(od -c blob.bin)" "blob.bin"
  assert_contains "$(git status --porcelain)" "UU blob.bin" "still unresolved"
}

test_an_unknown_side_exits_1() {
  diverged_repo
  resolve both shared.txt
  assert_eq 1 "$STATUS" "exit status"
}

run_tests
