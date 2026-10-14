#!/usr/bin/env bash
# Behaviour of issue-triage's apply.sh: manifest validation, the order of
# writes, idempotency through markers, close-reason repair, the board guard,
# the approval binding, and stopping on a permission denial.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

APPLY="workflow/skills/issue-triage/scripts/apply.sh"

# A gh stand-in. Reads answer from fixture files in the case directory, applies
# --jq like gh does, and records every write to writes.calls. A line in
# fail_on that matches the arguments makes that call fail with stderr from
# fail_err.
stub_gh() {
  stub gh <<'EOF'
args="$*"
jqexpr=""
prev=""
for a in "$@"; do
  [ "$prev" = "--jq" ] && jqexpr="$a"
  prev="$a"
done
answer() { if [ -n "$jqexpr" ]; then jq -r "$jqexpr"; else cat; fi; }
if [ -f fail_on ] && printf '%s' "$args" | grep -qf fail_on; then
  cat fail_err >&2
  exit 1
fi
case "$args" in
  "api user"*) echo me | answer; exit 0 ;;
  "api -i user") printf 'HTTP/2.0 200 OK\nX-Oauth-Scopes: %s\n\n{}\n' "$(cat scopes 2>/dev/null || echo 'repo, project')"; exit 0 ;;
  "label list"*) answer < labels.json; exit 0 ;;
  "api repos/o/r/milestones"*) answer < milestones.json; exit 0 ;;
  "api graphql"*issueTypes*) answer < types.json; exit 0 ;;
  "api graphql"*repositoryOwner*) cat project.json; exit 0 ;;
  "api graphql"*)
    n="$(printf '%s' "$args" | sed -n 's/.*-F n=\([0-9]*\).*/\1/p')"
    cat "live/$n.json"; exit 0 ;;
  "issue view"*"--json state"*)
    n="$(printf '%s' "$args" | awk '{print $3}')"
    cat "state_$n" 2>/dev/null || echo OPEN; exit 0 ;;
esac
case "$args" in
  "api repos/o/r/issues/"*)
    if [ "$(printf '%s' "$args" | grep -c -- '-X')" = 0 ]; then
      n="$(printf '%s' "$args" | sed 's|api repos/o/r/issues/\([0-9]*\).*|\1|')"
      printf '{"id":%s00,"body":"original body of %s"}' "$n" "$n" | answer; exit 0
    fi ;;
esac
printf '%s\n' "$args" >> writes.calls
prev=""
for a in "$@"; do
  if [ "$prev" = "--body-file" ]; then cat "$a" >> bodies.txt; echo "=====" >> bodies.txt; fi
  prev="$a"
done
case "$args" in
  "project item-add"*) echo '{"id":"ITEM_NEW"}' ;;
  "issue create"*) echo "https://github.com/o/r/issues/900" ;;
esac
exit 0
EOF
}

# live <n> <state> [extra-json-for-the-issue]
live() {
  mkdir -p live
  local extra="${3:-}"
  printf '{"data":{"repository":{"issue":{"id":"I_%s","number":%s,"state":"%s","stateReason":%s,"duplicateOf":null,"title":"Title %s","body":"body %s","issueType":{"name":"Task"},"labels":{"nodes":[{"name":"Bug"}]},"milestone":null,"parent":null,"comments":{"nodes":[]},"projectItems":{"nodes":[]}%s}}}}' \
    "$1" "$1" "$2" "$( [ "$2" = CLOSED ] && echo '"COMPLETED"' || echo null)" "$1" "$1" "$extra" > "live/$1.json"
}

on_board() {
  printf ',"projectItems":{"nodes":[{"id":"ITEM_%s","project":{"number":7,"owner":{"login":"o"}},"fieldValueByName":{"name":"%s"}}]}' "$1" "$2"
}

fixtures() {
  stub_gh
  echo '[{"name":"Bug"},{"name":"Tech Debt"},{"name":"Security"}]' > labels.json
  echo '{"data":{"repository":{"issueTypes":{"nodes":[{"name":"Task"},{"name":"Bug"},{"name":"Feature"}]}}}}' > types.json
  echo '[{"title":"Old","number":3,"state":"open"}]' > milestones.json
  echo '{"data":{"repositoryOwner":{"projectV2":{"id":"PVT_1","title":"Board","workflows":{"nodes":[{"name":"Auto-close issue","enabled":true},{"name":"Item closed","enabled":true}]},"field":{"id":"FIELD_1","options":[{"id":"OPT_B","name":"Backlog"},{"id":"OPT_D","name":"Done"}]}}}}}' > project.json
  mkdir -p text
  printf 'Closing: done in abc123.\n' > text/1.close.md
  printf 'Scope changed.\n' > text/2.note.md
}

manifest() {
  printf '{"version":1,"repo":"o/r","marker":"t1","project":{"owner":"o","number":7,"status_field":"Status","closed_status":"Done"},%s}' "$1" > manifest.json
}

plan_ops() {
  run bash "$(script "$APPLY")" plan manifest.json
  printf '%s\n' "$STDOUT" | sed '$d' | cut -f1,2
}

expect_id() {
  run bash "$(script "$APPLY")" plan manifest.json
  last_line "$STDOUT" | awk '{print $2}'
}

export ISSUE_TRIAGE_PAUSE=0 ISSUE_TRIAGE_SETTLE=0

test_invalid_rows_are_refused_before_any_gh_call() {
  fixtures
  manifest '"issues":[{"number":1,"state":"closed"},{"number":2,"state":"closed","reason":"duplicate"},{"number":3,"state":"closed","reason":"duplicate","duplicate_of":3},{"number":4,"comment_file":"text/missing.md"}]'
  run bash "$(script "$APPLY")" plan manifest.json
  assert_eq 2 "$STATUS" "exit status"
  assert_contains "$STDERR" "#1: a closed row needs reason"
  assert_contains "$STDERR" "#2: duplicate needs duplicate_of"
  assert_contains "$STDERR" "#3: duplicate of itself"
  assert_contains "$STDERR" "text file missing: text/missing.md"
  assert_no_file writes.calls
}

test_writes_run_in_a_fixed_order_with_close_before_status() {
  fixtures
  live 1 OPEN
  manifest '"issues":[{"number":1,"type":"Bug","labels":{"add":["Security"],"remove":["Bug"]},"title":"fix: new title","status":"Done","state":"closed","reason":"not_planned","comment_file":"text/1.close.md","body":{"mode":"append","file":"text/2.note.md"}}]'
  assert_eq "1	title
1	type
1	label-add
1	label-remove
1	project-add
1	body
1	comment
1	close
1	status" "$(plan_ops)" "op order"
}

test_live_state_that_already_matches_plans_nothing() {
  fixtures
  live 1 CLOSED "$(on_board 1 Done),\"comments\":{\"nodes\":[{\"body\":\"x\\n<!-- issue-triage:t1:comment -->\"}]}"
  manifest '"issues":[{"number":1,"type":"Task","labels":{"add":["Bug"]},"status":"Done","state":"closed","reason":"completed","comment_file":"text/1.close.md"}]'
  run bash "$(script "$APPLY")" audit manifest.json
  assert_eq 0 "$STATUS" "audit exit"
  assert_contains "$STDOUT" "live state matches"
}

test_wrong_close_reason_is_repaired_without_reopening_unless_duplicate() {
  fixtures
  live 1 CLOSED "$(on_board 1 Done)"
  live 2 CLOSED "$(on_board 2 Done)"
  manifest '"issues":[{"number":1,"state":"closed","reason":"not_planned"},{"number":2,"state":"closed","reason":"duplicate","duplicate_of":5}]'
  assert_eq "1	reason
2	redup" "$(plan_ops)" "repair ops"
  run bash "$(script "$APPLY")" apply manifest.json --expect "$(expect_id)"
  assert_eq 0 "$STATUS" "apply exit: $STDERR"
  assert_contains "$(cat writes.calls)" "api -X PATCH repos/o/r/issues/1 -f state=closed -f state_reason=not_planned"
  assert_contains "$(cat writes.calls)" "issue reopen 2 -R o/r"
  assert_contains "$(cat writes.calls)" "issue close 2 -R o/r --duplicate-of 5"
}

test_status_that_auto_closes_is_refused_on_an_issue_meant_to_stay_open() {
  fixtures
  live 1 OPEN "$(on_board 1 Backlog)"
  manifest '"issues":[{"number":1,"status":"Done"}]'
  run bash "$(script "$APPLY")" plan manifest.json
  assert_eq 2 "$STATUS" "exit status"
  assert_contains "$STDERR" "auto-closes issues on this board"
}

test_apply_refuses_a_manifest_changed_after_approval() {
  fixtures
  live 1 OPEN "$(on_board 1 Backlog)"
  manifest '"issues":[{"number":1,"type":"Bug"}]'
  run bash "$(script "$APPLY")" apply manifest.json --expect 0000000000000000000000000000000000000000
  assert_eq 2 "$STATUS" "exit status"
  assert_contains "$STDERR" "manifest changed since the approved plan"
  assert_no_file writes.calls
}

test_a_text_edited_after_approval_changes_the_id() {
  fixtures
  live 1 OPEN "$(on_board 1 Backlog)"
  manifest '"issues":[{"number":1,"comment_file":"text/1.close.md"}]'
  local approved
  approved="$(expect_id)"
  printf 'A different comment.\n' > text/1.close.md
  run bash "$(script "$APPLY")" apply manifest.json --expect "$approved"
  assert_eq 2 "$STATUS" "exit status"
  assert_contains "$STDERR" "manifest changed since the approved plan"
  assert_no_file writes.calls
}

test_permission_denial_stops_the_run() {
  fixtures
  live 1 OPEN "$(on_board 1 Backlog)"
  manifest '"issues":[{"number":1,"type":"Bug","title":"fix: x","labels":{"add":["Security"]}}]'
  echo 'issue edit 1 -R o/r --type' > fail_on
  echo 'HTTP 403: Resource not accessible by integration' > fail_err
  run bash "$(script "$APPLY")" apply manifest.json --expect "$(expect_id)"
  assert_eq 4 "$STATUS" "exit status"
  assert_contains "$STDERR" "permission denied"
  assert_eq "issue edit 1 -R o/r --title fix: x" "$(cat writes.calls)" "only the write before the denial ran"
}

test_board_workflow_closing_an_open_issue_stops_the_run() {
  fixtures
  live 1 OPEN "$(on_board 1 Done)"
  printf '{"version":1,"repo":"o/r","marker":"t1","project":{"owner":"o","number":7,"status_field":"Status"},"issues":[{"number":1,"state":"open","status":"Backlog"}]}' > manifest.json
  echo CLOSED > state_1
  run bash "$(script "$APPLY")" apply manifest.json --expect "$(expect_id)"
  assert_eq 6 "$STATUS" "exit status"
  assert_contains "$STDERR" "a board workflow closed #1"
}

test_texts_are_posted_unchanged_with_one_marker_line() {
  fixtures
  live 1 OPEN "$(on_board 1 Backlog)"
  printf 'Tabs\there, `code`, $(not run) and a trailing line\n' > text/1.close.md
  manifest '"issues":[{"number":1,"comment_file":"text/1.close.md","body":{"mode":"prepend","file":"text/2.note.md"}}]'
  run bash "$(script "$APPLY")" apply manifest.json --expect "$(expect_id)"
  assert_eq 0 "$STATUS" "apply exit: $STDERR"
  assert_contains "$(cat bodies.txt)" 'Tabs	here, `code`, $(not run) and a trailing line

<!-- issue-triage:t1:comment -->'
  assert_contains "$(cat bodies.txt)" 'Scope changed.

<!-- issue-triage:t1:note -->

original body of 1'
}

test_new_issue_is_created_then_reconciled() {
  fixtures
  live 900 OPEN
  printf 'New body.\n' > text/new.md
  manifest '"issues":[],"new_issues":[{"key":"poller","title":"refactor: poller","body_file":"text/new.md","type":"Bug","status":"Backlog"}]'
  run bash "$(script "$APPLY")" apply manifest.json --expect "$(expect_id)"
  assert_eq 0 "$STATUS" "apply exit: $STDERR"
  assert_eq '{"poller":900}' "$(jq -c . created.json)" "created map"
  assert_contains "$(cat writes.calls)" "issue create -R o/r --title refactor: poller"
  assert_contains "$(cat writes.calls)" "issue edit 900 -R o/r --type Bug"
  assert_contains "$(cat writes.calls)" "project item-add 7 --owner o --url https://github.com/o/r/issues/900"
  assert_contains "$(cat writes.calls)" "project item-edit --id ITEM_NEW --project-id PVT_1 --field-id FIELD_1 --single-select-option-id OPT_B"
}

test_preflight_names_an_env_token_without_project_scope() {
  fixtures
  echo 'repo, read:org' > scopes
  manifest '"issues":[{"number":1,"labels":{"add":["Nope"]}}]'
  GH_TOKEN=x run bash "$(script "$APPLY")" preflight manifest.json
  assert_eq 3 "$STATUS" "exit status"
  assert_contains "$STDERR" "GH_TOKEN in the environment overrides the stored gh login"
}

test_preflight_refuses_names_that_do_not_exist() {
  fixtures
  manifest '"issues":[{"number":1,"type":"Epic","status":"Later","labels":{"add":["Nope"]}}],"milestones_close":["Gone"]'
  run bash "$(script "$APPLY")" preflight manifest.json
  assert_eq 3 "$STATUS" "exit status"
  assert_contains "$STDERR" "label does not exist: Nope (labels-sync owns the label set)"
  assert_contains "$STDERR" "issue type does not exist: Epic"
  assert_contains "$STDERR" "status option does not exist: Later"
  assert_contains "$STDERR" "milestone does not exist: Gone"
}

test_only_limits_the_rows() {
  fixtures
  live 1 OPEN "$(on_board 1 Backlog)"
  live 2 OPEN "$(on_board 2 Backlog)"
  manifest '"issues":[{"number":1,"type":"Bug"},{"number":2,"type":"Bug"}],"milestones_close":["Old"]'
  run bash "$(script "$APPLY")" plan manifest.json --only 2
  assert_eq "2	type" "$(printf '%s\n' "$STDOUT" | sed '$d' | cut -f1,2)" "only #2, no milestone"
}

test_milestone_close_is_planned_once() {
  fixtures
  manifest '"issues":[],"milestones_close":["Old"]'
  assert_eq "milestone:Old	milestone-close" "$(plan_ops)" "milestone op"
}

run_tests
