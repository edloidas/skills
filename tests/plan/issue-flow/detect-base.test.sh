#!/usr/bin/env bash
# detect-base.sh — the script that feeds every squash, reset, rebase, and PR
# base in the issue pipeline.
#
# Two of these cases are regressions, not coverage. Both shipped, both passed
# every structural gate, and both needed an executed scenario to see:
#
#   epic_ahead_of_issue_branch   `merge-base --is-ancestor <epic-tip> HEAD`
#                                answers "is the epic contained in my branch",
#                                which goes false the moment the epic gains a
#                                commit, silently demoting the base.
#   fork_points_in_same_second   ranking candidate bases by commit timestamp
#                                ties whenever two commits land in the same
#                                second, and the tie discarded the right answer.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

DETECT_BASE="plan/skills/issue-flow/scripts/detect-base.sh"

# A repo on `main` with one commit, an `origin` bare remote, and `gh` answering
# `main` as the default branch. Leaves the shell inside the work tree.
base_repo() {
  local default="${1:-main}"
  init_repo repo "$default"
  cd repo
  commit "initial"
  add_remote "$default"
  stub_gh_default_branch "$default"
}

detect() {
  run bash "$(script "$DETECT_BASE")"
}

# ------------------------------------------------------- base-like branches --

test_current_branch_main_is_its_own_base() {
  base_repo main
  detect
  assert_eq 0 "$STATUS" "exit status"
  assert_eq main "$(last_line "$STDOUT")" "detected base"
}

test_current_branch_master_is_its_own_base() {
  base_repo master
  detect
  assert_eq 0 "$STATUS" "exit status"
  assert_eq master "$(last_line "$STDOUT")" "detected base"
}

test_current_branch_next_is_its_own_base() {
  base_repo main
  git checkout --quiet -b next
  detect
  assert_eq 0 "$STATUS" "exit status"
  assert_eq next "$(last_line "$STDOUT")" "detected base"
}

test_current_branch_epic_is_its_own_base() {
  base_repo main
  git checkout --quiet -b epic-6
  commit "epic work"
  detect
  assert_eq 0 "$STATUS" "exit status"
  assert_eq epic-6 "$(last_line "$STDOUT")" "detected base"
}

# --------------------------------------------------------- issue-* branches --

test_issue_branch_cut_from_unchanged_epic() {
  base_repo main
  git checkout --quiet -b epic-6
  commit "epic work"
  push_branch epic-6
  git checkout --quiet -b issue-35
  commit "issue work"
  detect
  assert_eq 0 "$STATUS" "exit status"
  assert_eq epic-6 "$(last_line "$STDOUT")" "detected base"
}

# Regression, #34. The epic gaining a commit after the issue branch was cut is
# the normal state of an active epic, and it used to flip the answer to `main`.
test_issue_branch_when_epic_moved_ahead() {
  base_repo main
  git checkout --quiet -b epic-6
  commit "epic work"
  push_branch epic-6
  git checkout --quiet -b issue-35
  commit "issue work"

  git checkout --quiet epic-6
  commit "epic moves on after the issue branch was cut"
  push_branch epic-6
  git checkout --quiet issue-35

  detect
  assert_eq 0 "$STATUS" "exit status"
  assert_eq epic-6 "$(last_line "$STDOUT")" "detected base"
}

test_issue_branch_cut_from_default_branch() {
  base_repo main
  # An epic exists, but this issue branch left `main` directly and after the
  # epic forked, so the epic's fork point is behind the floor.
  git checkout --quiet -b epic-6
  commit "epic work"
  push_branch epic-6
  git checkout --quiet main
  commit "main moves on"
  push_branch main
  git checkout --quiet -b issue-40
  commit "issue work"

  detect
  assert_eq 0 "$STATUS" "exit status"
  assert_eq main "$(last_line "$STDOUT")" "detected base"
}

test_issue_branch_cut_from_local_only_epic() {
  base_repo main
  git checkout --quiet -b epic-6
  commit "epic work"
  # deliberately never pushed
  git checkout --quiet -b issue-35
  commit "issue work"
  detect
  assert_eq 0 "$STATUS" "exit status"
  assert_eq epic-6 "$(last_line "$STDOUT")" "detected base"
}

# The documented contract: the last line is a branch NAME, never a rev. An epic
# that exists only on the remote must still come back bare, because callers feed
# it to `git checkout` and `gh pr create --base`.
test_remote_only_epic_is_reported_as_a_bare_name() {
  base_repo main
  git checkout --quiet -b epic-6
  commit "epic work"
  push_branch epic-6
  git checkout --quiet -b issue-35
  commit "issue work"
  git branch --quiet -D epic-6 2>/dev/null || true

  detect
  assert_eq 0 "$STATUS" "exit status"
  assert_eq epic-6 "$(last_line "$STDOUT")" "detected base"
  assert_not_contains "$(last_line "$STDOUT")" "origin/" "detected base"
}

test_issue_branch_with_no_epic_branches() {
  base_repo main
  git checkout --quiet -b issue-12
  commit "issue work"
  detect
  assert_eq 0 "$STATUS" "exit status"
  assert_eq main "$(last_line "$STDOUT")" "detected base"
}

# Regression. epic-1 and epic-2 fork points differ by ancestry but share a
# committer timestamp to the second; ordering by time ties and loses epic-2.
test_fork_points_in_same_second_are_ordered_by_ancestry() {
  base_repo main
  git checkout --quiet -b epic-1
  commit_same_second "epic-1 work"
  push_branch epic-1
  git checkout --quiet -b epic-2
  commit_same_second "epic-2 work"
  push_branch epic-2

  # Same second, so a timestamp comparison cannot separate them.
  assert_eq "$(git log -1 --format=%ct epic-1)" "$(git log -1 --format=%ct epic-2)" \
    "epic tip timestamps"

  git checkout --quiet -b issue-77
  commit "issue work"

  detect
  assert_eq 0 "$STATUS" "exit status"
  assert_eq epic-2 "$(last_line "$STDOUT")" "detected base"
}

# Documented limitation, pinned so a change in behavior is visible: when two
# epics share the exact fork point git cannot tell them apart, and the script
# takes the first enumerated rather than guessing or failing.
test_two_epics_sharing_a_fork_point_pick_one_deterministically() {
  base_repo main
  git checkout --quiet -b epic-a
  commit "shared history"
  push_branch epic-a
  # epic-b carries its own commit but left epic-a at the same point the issue
  # branch does, so both epics have the identical fork point.
  git checkout --quiet -b epic-b
  commit "epic-b work"
  push_branch epic-b
  git checkout --quiet epic-a
  git checkout --quiet -b issue-99
  commit "issue work"

  assert_eq "$(git merge-base epic-a HEAD)" "$(git merge-base epic-b HEAD)" \
    "fork points of the two epics"

  detect
  assert_eq 0 "$STATUS" "exit status"
  assert_one_of "$(last_line "$STDOUT")" epic-a epic-b

  # And the same input gives the same answer twice.
  local first="$(last_line "$STDOUT")"
  detect
  assert_eq "$first" "$(last_line "$STDOUT")" "detected base on a second run"
}

# ----------------------------------------------------------- failure modes ----

test_outside_a_git_repository_exits_1() {
  mkdir -p empty
  cd empty
  detect
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "Not inside a git repository" "error output"
}

test_no_remote_and_no_gh_exits_2() {
  init_repo repo main
  cd repo
  commit "initial"
  no_gh
  detect
  assert_eq 2 "$STATUS" "exit status"
  assert_contains "$STDERR" "Could not determine default branch" "error output"
}

# Without `gh`, the default branch has to come from refs/remotes/origin/HEAD.
test_default_branch_falls_back_to_remote_head_without_gh() {
  init_repo repo master
  cd repo
  commit "initial"
  add_remote master
  no_gh
  git checkout --quiet -b issue-3
  commit "issue work"
  detect
  assert_eq 0 "$STATUS" "exit status"
  assert_eq master "$(last_line "$STDOUT")" "detected base"
}

# Detached HEAD has no branch name, so neither shortcut applies and the answer
# must be the default branch rather than an empty string.
test_detached_head_falls_back_to_default_branch() {
  base_repo main
  commit "second"
  git checkout --quiet HEAD~1
  detect
  assert_eq 0 "$STATUS" "exit status"
  assert_eq main "$(last_line "$STDOUT")" "detected base"
}

run_tests
