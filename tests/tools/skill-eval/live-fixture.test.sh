#!/usr/bin/env bash
# tools/skill-eval/fixtures/setup-ledger.sh and cases/live/check.sh — the live suite's scaffold
# builds the repo each case expects, and check.sh fails on the untouched scaffold, so a live
# run's PASS means the skill changed something. Needs node; no case calls a model.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

SETUP="tools/skill-eval/fixtures/setup-ledger.sh"
CHECK="tools/skill-eval/cases/live/check.sh"

setup() {
  command -v node >/dev/null 2>&1 || skip "node is not installed"
  mkdir ws && cd ws || exit 1
}

scaffold() {
  run bash "$(script "$SETUP")" "$1"
  assert_eq 0 "$STATUS" "setup-ledger.sh $1 exit status"
}

test_plain_is_three_commits_on_a_clean_main() {
  scaffold plain
  assert_eq 3 "$(git rev-list --count HEAD)" "commit count"
  assert_eq main "$(git branch --show-current)" "branch"
  assert_eq "" "$(git status --short)" "tree"
}

test_bug_variant_reproduces_and_fails_the_check() {
  scaffold bug
  assert_eq 42.60 "$(node bin/total.js examples/march.txt)" "buggy total"
  run bash "$(script "$CHECK")" bug .
  assert_eq 1 "$STATUS" "check.sh exit status"
  assert_contains "$STDOUT" "FAIL total-is-43.50" "check output"
  assert_contains "$STDOUT" "PASS calendar-unchanged" "check output"
}

test_review_variant_leaves_planted_defects_uncommitted() {
  scaffold review
  assert_contains "$(git status --short)" "bin/total.js" "dirty tree"
  run bash "$(script "$CHECK")" review-fix .
  assert_eq 1 "$STATUS" "check.sh exit status"
  assert_contains "$STDOUT" "FAIL empty-no-NaN" "check output"
}

test_issue_false_variant_adds_the_issue_file() {
  scaffold issue-false
  assert_file issue-17.md
  assert_contains "$(cat issue-17.md)" "readLedger" "issue text"
}

test_check_rejects_an_unknown_case() {
  scaffold plain
  run bash "$(script "$CHECK")" nope .
  assert_eq 2 "$STATUS" "check.sh exit status"
}

run_tests
