#!/usr/bin/env bash
# existing-work.sh — the check that stops solve-issue from re-implementing an
# issue someone already has a branch or a pull request for.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

EXISTING_WORK="workflow/skills/solve-issue/scripts/existing-work.sh"

# gh answers `pr list` from two files the case writes, already in the unit-separated
# shape the script's --jq projection produces: open.tsv and merged.tsv.
stub_gh_prs() {
  stub gh <<EOF
if [ "\$1" = "pr" ] && [ "\$2" = "list" ]; then
  case "\$*" in
    *"--state open"*) cat "$SANDBOX/open.tsv" 2>/dev/null; exit 0 ;;
    *"--state merged"*) cat "$SANDBOX/merged.tsv" 2>/dev/null; exit 0 ;;
  esac
fi
echo "stub gh: unexpected invocation: \$*" >&2
exit 1
EOF
}

tsv() {
  local IFS
  IFS=$(printf '\037')
  printf '%s\n' "$*"
}

base_repo() {
  init_repo repo main
  cd repo
  commit "initial"
  add_remote main
  stub_gh_prs
}

check() {
  run bash "$(script "$EXISTING_WORK")" "$@"
}

test_no_argument_is_a_usage_error() {
  base_repo
  check
  assert_eq 2 "$STATUS" "exit status"
}

test_non_numeric_argument_is_a_usage_error() {
  base_repo
  check 42a
  assert_eq 2 "$STATUS" "exit status"
}

test_nothing_found_is_clear() {
  base_repo
  check 42
  assert_eq 0 "$STATUS" "exit status"
  assert_eq "VERDICT=clear" "$(last_line "$STDOUT")" "verdict"
}

test_on_the_issue_branch_is_own_branch() {
  base_repo
  git checkout --quiet -b issue-42
  commit "work"
  tsv 7 someone issue-42 42 > "$SANDBOX/open.tsv"
  check 42
  assert_eq "VERDICT=own-branch" "$(last_line "$STDOUT")" "verdict"
}

test_on_the_head_of_a_closing_pr_is_own_branch() {
  base_repo
  git checkout --quiet -b tooltip-fix
  tsv 7 me tooltip-fix 42 > "$SANDBOX/open.tsv"
  check 42
  assert_contains "$STDOUT" "OPEN_PR=7 me tooltip-fix" "pr reported"
  assert_eq "VERDICT=own-branch" "$(last_line "$STDOUT")" "verdict"
}

test_someone_elses_open_pr_is_in_progress() {
  base_repo
  tsv 9 alice alice/tooltip 42 > "$SANDBOX/open.tsv"
  check 42
  assert_contains "$STDOUT" "OPEN_PR=9 alice alice/tooltip" "pr reported"
  assert_eq "VERDICT=in-progress" "$(last_line "$STDOUT")" "verdict"
}

test_open_pr_named_after_the_issue_without_closing_ref_is_in_progress() {
  base_repo
  tsv 9 alice issue-42 "" > "$SANDBOX/open.tsv"
  check 42
  assert_eq "VERDICT=in-progress" "$(last_line "$STDOUT")" "verdict"
}

test_remote_issue_branch_with_commits_is_in_progress() {
  base_repo
  git checkout --quiet -b issue-42
  commit "half done"
  push_branch issue-42
  git checkout --quiet main
  git branch --quiet -D issue-42
  check 42
  assert_contains "$STDOUT" "BRANCH=origin/issue-42 1" "branch reported"
  assert_eq "VERDICT=in-progress" "$(last_line "$STDOUT")" "verdict"
}

test_local_and_remote_twin_is_reported_once() {
  base_repo
  git checkout --quiet -b issue-42
  commit "half done"
  push_branch issue-42
  git checkout --quiet main
  check 42
  assert_contains "$STDOUT" "BRANCH=issue-42 1" "local branch reported"
  assert_not_contains "$STDOUT" "BRANCH=origin/issue-42" "remote twin"
}

test_issue_branch_with_no_new_commits_is_clear() {
  base_repo
  git branch issue-42
  check 42
  assert_eq "VERDICT=clear" "$(last_line "$STDOUT")" "verdict"
}

test_longer_number_does_not_match() {
  base_repo
  git checkout --quiet -b issue-420
  commit "other issue"
  git checkout --quiet main
  tsv 9 alice 420-thing 420 > "$SANDBOX/open.tsv"
  check 42
  assert_eq "VERDICT=clear" "$(last_line "$STDOUT")" "verdict"
}

test_merged_closing_pr_is_merged() {
  base_repo
  tsv 12 issue-42 42 > "$SANDBOX/merged.tsv"
  check 42
  assert_contains "$STDOUT" "MERGED_PR=12 issue-42" "merged pr reported"
  assert_eq "VERDICT=merged" "$(last_line "$STDOUT")" "verdict"
}

test_merged_pr_that_only_mentions_the_number_is_ignored() {
  base_repo
  tsv 12 other-work 7 > "$SANDBOX/merged.tsv"
  check 42
  assert_eq "VERDICT=clear" "$(last_line "$STDOUT")" "verdict"
}

test_own_branch_wins_over_merged() {
  base_repo
  git checkout --quiet -b issue-42
  tsv 12 issue-42-first-pass 42 > "$SANDBOX/merged.tsv"
  check 42
  assert_eq "VERDICT=own-branch" "$(last_line "$STDOUT")" "verdict"
}

test_stale_branch_of_a_merged_pr_is_merged() {
  base_repo
  git checkout --quiet -b issue-42
  tsv 12 issue-42 42 > "$SANDBOX/merged.tsv"
  check 42
  assert_contains "$STDOUT" "MERGED_PR=12 issue-42" "merged pr reported"
  assert_eq "VERDICT=merged" "$(last_line "$STDOUT")" "verdict"
}

test_reopened_work_with_an_open_pr_on_the_branch_is_own_branch() {
  base_repo
  git checkout --quiet -b issue-42
  tsv 12 issue-42 42 > "$SANDBOX/merged.tsv"
  tsv 15 me issue-42 42 > "$SANDBOX/open.tsv"
  check 42
  assert_eq "VERDICT=own-branch" "$(last_line "$STDOUT")" "verdict"
}

test_issue_url_is_accepted() {
  base_repo
  tsv 9 alice alice/tooltip 42 > "$SANDBOX/open.tsv"
  check https://github.com/acme/widgets/issues/42
  assert_eq 0 "$STATUS" "exit status"
  assert_eq "VERDICT=in-progress" "$(last_line "$STDOUT")" "verdict"
}

test_empty_author_does_not_shift_fields() {
  base_repo
  tsv 9 "" ghost-branch 42 > "$SANDBOX/open.tsv"
  check 42
  assert_contains "$STDOUT" "OPEN_PR=9  ghost-branch" "fields kept in place"
  assert_eq "VERDICT=in-progress" "$(last_line "$STDOUT")" "verdict"
}

test_gh_failure_still_checks_branches() {
  base_repo
  stub gh <<'EOF'
exit 1
EOF
  git checkout --quiet -b fix/42-tooltip
  commit "half done"
  git checkout --quiet main
  check 42
  assert_contains "$STDOUT" "GH=unavailable" "gh failure named"
  assert_contains "$STDOUT" "BRANCH=fix/42-tooltip 1" "branch reported"
  assert_eq "VERDICT=in-progress" "$(last_line "$STDOUT")" "verdict"
}

test_outside_a_repo_exits_1() {
  stub_gh_prs
  check 42
  assert_eq 1 "$STATUS" "exit status"
}

run_tests
