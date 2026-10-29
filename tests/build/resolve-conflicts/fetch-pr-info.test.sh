#!/usr/bin/env bash
# fetch-pr-info.sh — the parsing and refusals around `gh pr view`, not gh itself.
# A closed PR must stop the skill before it rebases anything, and a fork PR must
# name the repository its branch lives in, or the fetch and the force-push go to
# origin, where that branch does not exist.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

FETCH="build/skills/resolve-conflicts/scripts/fetch-pr-info.sh"

value_of() {
  printf '%s\n' "$STDOUT" | sed -n "s/^$1=//p"
}

# gh stub: authenticated, and `pr view` answers with the JSON in pr.json.
stub_gh_with() {
  printf '%s\n' "$1" > "$PWD/pr.json"
  stub gh <<EOF
case "\$1 \$2" in
  "auth status") exit 0 ;;
  "pr view") cat "$PWD/pr.json" ;;
  *) exit 1 ;;
esac
EOF
}

fetch() {
  run bash "$(script "$FETCH")" "$@"
}

pr_json() {
  # state, mergeable, owner, cross
  printf '{"number":7,"title":"Fix it","headRefName":"fix-it","baseRefName":"main","url":"https://github.com/acme/app/pull/7","mergeable":"%s","state":"%s","headRepository":{"name":"app"},"headRepositoryOwner":{"login":"%s"},"isCrossRepository":%s,"maintainerCanModify":true}' "$2" "$1" "$3" "$4"
}

test_open_conflicting_pr_exits_0() {
  stub_gh_with "$(pr_json OPEN CONFLICTING acme false)"
  fetch 7
  assert_eq 0 "$STATUS" "exit status"
  assert_eq fix-it "$(value_of head)" "head"
  assert_eq acme/app "$(value_of head_repo)" "head_repo"
  assert_eq false "$(value_of cross_repository)" "cross_repository"
  assert_eq dirty "$(value_of mergeable_state)" "mergeable_state"
}

test_fork_pr_names_the_fork_as_head_repo() {
  stub_gh_with "$(pr_json OPEN CONFLICTING contributor true)"
  fetch 7
  assert_eq 0 "$STATUS" "exit status"
  assert_eq contributor/app "$(value_of head_repo)" "head_repo"
  assert_eq true "$(value_of cross_repository)" "cross_repository"
  assert_eq true "$(value_of maintainer_can_modify)" "maintainer_can_modify"
}

test_merged_pr_exits_6() {
  stub_gh_with "$(pr_json MERGED UNKNOWN acme false)"
  fetch 7
  assert_eq 6 "$STATUS" "exit status"
  assert_eq MERGED "$(value_of state)" "state"
  assert_contains "$STDERR" "is MERGED" "error output"
}

# Closed outranks clean: a closed PR stops even when gh calls it mergeable.
test_closed_mergeable_pr_exits_6_not_5() {
  stub_gh_with "$(pr_json CLOSED MERGEABLE acme false)"
  fetch 7
  assert_eq 6 "$STATUS" "exit status"
}

test_open_clean_pr_exits_5() {
  stub_gh_with "$(pr_json OPEN MERGEABLE acme false)"
  fetch 7
  assert_eq 5 "$STATUS" "exit status"
  assert_eq clean "$(value_of mergeable_state)" "mergeable_state"
}

test_missing_jq_exits_2() {
  stub_gh_with "$(pr_json OPEN CONFLICTING acme false)"
  rm -f "$CORE_BIN/jq"
  fetch 7
  assert_eq 2 "$STATUS" "exit status"
  assert_contains "$STDERR" "jq not installed" "error output"
}

test_unparseable_input_exits_1() {
  stub_gh_with "$(pr_json OPEN CONFLICTING acme false)"
  fetch "not a pr"
  assert_eq 1 "$STATUS" "exit status"
}

run_tests
