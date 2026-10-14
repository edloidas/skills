#!/usr/bin/env bash
# stack-sync.sh — keeps a stacked branch on its parent, so Consolidate never
# squashes the parent's commits into the child and a merged parent hands the
# child to the default branch cleanly.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

STACK_SYNC="plan/skills/issue-flow/scripts/stack-sync.sh"

# main <- issue-41 (pushed) <- issue-42 with the record Step 2 writes.
# Leaves the shell on issue-42 inside the work tree.
stacked_repo() {
  init_repo repo main
  cd repo
  commit "initial"
  add_remote main
  stub_gh_merged 1
  git checkout --quiet -b issue-41
  commit "parent work" parent.txt
  push_branch issue-41
  git checkout --quiet -b issue-42
  commit "child work" child.txt
  git config branch.issue-42.issueFlowBase issue-41
  git config branch.issue-42.issueFlowBaseTip "$(git rev-parse origin/issue-41)"
}

# stub_gh_merged <count> — gh answers the default branch, and how many merged
# PRs have the parent as their head.
stub_gh_merged() {
  stub gh <<EOF
case "\$1 \$2" in
  "repo view") echo main; exit 0 ;;
  "pr list") echo "$1"; exit 0 ;;
esac
echo "stub gh: unexpected invocation: \$*" >&2
exit 1
EOF
}

sync() {
  run bash "$(script "$STACK_SYNC")"
}

own_commits() {
  git log --format=%s "$1"..HEAD
}

test_outside_a_git_repository_exits_1() {
  mkdir plain && cd plain
  sync
  assert_eq 1 "$STATUS" "exit status"
}

test_branch_without_a_record_is_none() {
  init_repo repo main
  cd repo
  commit "initial"
  add_remote main
  git checkout --quiet -b issue-7
  sync
  assert_eq 0 "$STATUS" "exit status"
  assert_eq "STACK=none" "$(last_line "$STDOUT")" "verdict"
}

test_unchanged_parent_is_kept() {
  stacked_repo
  before=$(git rev-parse HEAD)
  sync
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "BASE=issue-41" "base"
  assert_contains "$STDOUT" "FORK=$(git rev-parse origin/issue-41)" "fork is the recorded tip"
  assert_eq "STACK=kept" "$(last_line "$STDOUT")" "verdict"
  assert_eq "$before" "$(git rev-parse HEAD)" "nothing moved"
}

test_parent_that_only_gained_commits_is_kept() {
  stacked_repo
  tip=$(git rev-parse origin/issue-41)
  git checkout --quiet issue-41
  commit "more parent work" parent.txt
  push_branch issue-41
  git checkout --quiet issue-42
  sync
  assert_eq "STACK=kept" "$(last_line "$STDOUT")" "verdict"
  assert_contains "$STDOUT" "FORK=$tip" "fork stays where the child sits"
  assert_eq "child work" "$(own_commits "$tip")" "only the child's commit"
}

test_rewritten_parent_moves_the_child_onto_its_new_tip() {
  stacked_repo
  old=$(git rev-parse origin/issue-41)
  git checkout --quiet issue-41
  git commit --quiet --amend -m "parent work, amended"
  git push --quiet --force origin issue-41
  git fetch --quiet origin
  git checkout --quiet issue-42
  sync
  assert_eq 0 "$STATUS" "exit status"
  assert_eq "STACK=rebased" "$(last_line "$STDOUT")" "verdict"
  new=$(git rev-parse origin/issue-41)
  assert_contains "$STDOUT" "FORK=$new" "fork is the new tip"
  assert_eq "$new" "$(git config branch.issue-42.issueFlowBaseTip)" "new tip recorded"
  assert_eq "child work" "$(own_commits "$new")" "one commit on top of the new parent"
  if git merge-base --is-ancestor "$old" HEAD; then
    fail "the old parent commit is still in the child's history"
  fi
}

test_merged_parent_lands_the_child_on_the_default_branch() {
  stacked_repo
  git checkout --quiet main
  git cherry-pick --quiet origin/issue-41 > /dev/null
  push_branch main
  git push --quiet origin --delete issue-41
  git checkout --quiet issue-42
  sync
  assert_eq 0 "$STATUS" "exit status"
  assert_eq "STACK=landed" "$(last_line "$STDOUT")" "verdict"
  assert_contains "$STDOUT" "BASE=main" "base"
  assert_eq "child work" "$(own_commits origin/main)" "one commit on top of main"
  assert_eq "" "$(git config --get branch.issue-42.issueFlowBase || true)" "record forgotten"
  assert_eq "" "$(git config --get branch.issue-42.issueFlowBaseTip || true)" "tip forgotten"
}

test_parent_closed_unmerged_exits_5() {
  stacked_repo
  stub_gh_merged 0
  git push --quiet origin --delete issue-41
  before=$(git rev-parse HEAD)
  sync
  assert_eq 5 "$STATUS" "exit status"
  assert_eq "$before" "$(git rev-parse HEAD)" "nothing moved"
  assert_eq issue-41 "$(git config branch.issue-42.issueFlowBase)" "record kept"
}

test_recorded_tip_missing_from_the_branch_exits_1() {
  stacked_repo
  git checkout --quiet issue-41
  commit "parent commit the child never had" other.txt
  git checkout --quiet issue-42
  git config branch.issue-42.issueFlowBaseTip "$(git rev-parse issue-41)"
  sync
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "no longer in issue-42" "says why"
}

test_needed_rebase_with_a_dirty_tree_exits_4() {
  stacked_repo
  git checkout --quiet issue-41
  git commit --quiet --amend -m "parent work, amended"
  git push --quiet --force origin issue-41
  git checkout --quiet issue-42
  printf 'unsaved\n' >> child.txt
  before=$(git rev-parse HEAD)
  sync
  assert_eq 4 "$STATUS" "exit status"
  assert_eq "$before" "$(git rev-parse HEAD)" "nothing moved"
  assert_eq issue-41 "$(git config branch.issue-42.issueFlowBase)" "record kept"
}

test_conflicting_rebase_is_aborted_and_exits_3() {
  stacked_repo
  git checkout --quiet issue-41
  printf 'rewritten\n' > child.txt
  git add child.txt
  git commit --quiet --amend -m "parent work, now touching child.txt"
  git push --quiet --force origin issue-41
  git checkout --quiet issue-42
  before=$(git rev-parse HEAD)
  sync
  assert_eq 3 "$STATUS" "exit status"
  assert_eq "$before" "$(git rev-parse HEAD)" "nothing moved"
  assert_no_file .git/rebase-merge
  assert_no_file .git/rebase-apply
}

test_unreachable_origin_exits_1_and_keeps_the_record() {
  stacked_repo
  git remote set-url origin "$SANDBOX/nowhere.git"
  sync
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "cannot reach origin" "says why"
  assert_eq issue-41 "$(git config branch.issue-42.issueFlowBase)" "record kept"
}

test_record_without_a_tip_uses_the_merge_base() {
  stacked_repo
  git config --unset branch.issue-42.issueFlowBaseTip
  sync
  assert_eq "STACK=kept" "$(last_line "$STDOUT")" "verdict"
  assert_contains "$STDOUT" "FORK=$(git rev-parse origin/issue-41)" "fork from the merge-base"
}

run_tests
