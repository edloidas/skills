#!/usr/bin/env bash
# Issue-reference parsing in the issue fetch wrapper.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

GET_ISSUE="skills/issue-writer/scripts/get-issue.sh"

test_each_reference_form_resolves_to_the_number() {
  init_repo repo main
  cd repo
  stub_recording gh

  local ref
  for ref in 42 '#42' 'o/r#42' 'https://github.com/o/r/issues/42'; do
    run bash "$(script "$GET_ISSUE")" "$ref"
    assert_eq 0 "$STATUS" "exit status for $ref"
  done
  assert_eq 4 "$(calls_of gh | grep -c 'issue view 42 ')" "every form fetched issue 42"
  assert_eq 2 "$(calls_of gh | grep -c -- '--repo o/r')" "the two repo-qualified forms name their repository"
}

test_unrecognised_reference_is_refused_before_gh() {
  init_repo repo main
  cd repo
  stub_recording gh

  run bash "$(script "$GET_ISSUE")" 'some issue'
  assert_ne 0 "$STATUS" "exit status"
  assert_contains "$STDOUT$STDERR" "Not an issue reference" "says why"
  assert_eq "" "$(calls_of gh)" "gh was not invoked"
}

test_missing_argument_prints_usage() {
  init_repo repo main
  cd repo
  stub_recording gh

  run bash "$(script "$GET_ISSUE")"
  assert_ne 0 "$STATUS" "exit status"
  assert_contains "$STDOUT$STDERR" "Usage" "prints usage"
}

run_tests
