#!/usr/bin/env bash
# tools/skill-eval/scripts/summarize.sh — the Markdown summary of one suite run. What a
# run did is read from its trace (Skill calls, the Route line, the playbook Read), never
# from what the run claims about itself.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"
. "$(dirname "$0")/helpers.sh"

SUMMARIZE="tools/skill-eval/scripts/summarize.sh"

summarize() {
  run bash "$(script "$SUMMARIZE")" out "$@"
}

row_of() {
  printf '%s\n' "$STDOUT" | grep "^| $1 |"
}

routed_explain() {
  case_yaml "$PWD/root" cases/routing/explain explain
  trace_init out/traces/routing-explain/1.jsonl claude-opus-5-5
  trace_text out/traces/routing-explain/1.jsonl 'Task: explain the tr.

Route: `explain` — a why question, no fix asked.'
  trace_tool out/traces/routing-explain/1.jsonl Skill '{"skill":"edloidas:explain","args":"why"}'
}

test_missing_result_exits_1_with_usage() {
  run bash "$(script "$SUMMARIZE")"
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "usage: summarize.sh" "stderr"
}

test_header_records_version_model_runs_and_cost() {
  routed_explain
  aggregate out "$PWD/root" '[{"name":"routing-explain","dir":"cases/routing/explain","prompt":"/edloidas:do why?","runs":[{"passed":true,"trace":"x"}]}]'
  summarize routing
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "# Skill eval: routing" "title"
  assert_contains "$STDOUT" "- Claude Code: 2.1.314" "version"
  assert_contains "$STDOUT" "- Model: claude-opus-5-5" "model from the trace"
  assert_contains "$STDOUT" "- Runs per case: 1" "runs counted from the result, not runsPerCase"
  assert_contains "$STDOUT" 'cost $1.23' "cost"
  assert_contains "$STDOUT" "Cases fully passing: 1 of 1 · runs passing: 1 of 1" "totals"
}

test_row_shows_expected_pass_rate_route_and_skill() {
  routed_explain
  aggregate out "$PWD/root" '[{"name":"routing-explain","dir":"cases/routing/explain","prompt":"/edloidas:do why?","runs":[{"passed":true}]}]'
  summarize
  assert_eq "| routing-explain | /edloidas:do why? | explain | 1/1 | 1: route: explain · skill: explain |" "$(row_of routing-explain)" "row"
}

test_playbook_read_and_in_session_route_are_observed() {
  case_yaml "$PWD/root" cases/routing/bug "bug playbook"
  t=out/traces/routing-bug/1.jsonl
  trace_init "$t" m
  trace_text "$t" 'Route: `references/bug.md` — broken output.'
  trace_tool "$t" Read '{"file_path":"/plug/skills/do/references/bug.md"}'
  t2=out/traces/routing-bug/2.jsonl
  trace_init "$t2" m
  trace_text "$t2" 'Route: in session — a one-line change.'
  aggregate out "$PWD/root" '[{"name":"routing-bug","dir":"cases/routing/bug","prompt":"fix it","runs":[{"passed":true},{"passed":false,"graders":[{"name":"playbook","passed":false,"explanation":"Read called 0x (expected 1..∞)"}]}]}]'
  summarize
  assert_contains "$(row_of routing-bug)" "| bug playbook | 1/2 |" "pass rate"
  assert_contains "$(row_of routing-bug)" "1: route: references/bug.md · read: bug.md" "run 1"
  assert_contains "$(row_of routing-bug)" "<br>2: route: in session |" "run 2"
  assert_contains "$STDOUT" "- routing-bug run 2: playbook: Read called 0x (expected 1..∞)" "failed grader listed"
}

# A run that says it loaded a skill, without a Skill call, loaded nothing.
test_a_claimed_skill_without_a_skill_call_is_not_counted() {
  case_yaml "$PWD/root" cases/ambient/explain explain
  t=out/traces/ambient-explain/1.jsonl
  trace_init "$t" m
  trace_text "$t" 'I used the explain skill for this.'
  aggregate out "$PWD/root" '[{"name":"ambient-explain","dir":"cases/ambient/explain","prompt":"why?","runs":[{"passed":false}]}]'
  summarize
  assert_contains "$(row_of ambient-explain)" "1: no skill, no route |" "observed"
}

test_several_skill_calls_are_listed_in_order() {
  case_yaml "$PWD/root" cases/ambient/next next-issue
  t=out/traces/ambient-next/1.jsonl
  trace_init "$t" m
  trace_tool "$t" Skill '{"skill":"edloidas:do"}'
  trace_tool "$t" Skill '{"skill":"edloidas:next-issue"}'
  aggregate out "$PWD/root" '[{"name":"ambient-next","dir":"cases/ambient/next","prompt":"next?","runs":[{"passed":true}]}]'
  summarize
  assert_contains "$(row_of ambient-next)" "1: skill: do, next-issue |" "observed"
}

test_errored_run_without_trace_is_reported() {
  case_yaml "$PWD/root" cases/routing/pr pr-review
  aggregate out "$PWD/root" '[{"name":"routing-pr","dir":"cases/routing/pr","prompt":"review PR 51","runs":[{"passed":false,"error":"timeout after 300s"}]}]'
  summarize
  assert_contains "$(row_of routing-pr)" "| 0/1 (1 error) | 1: no trace |" "row"
  assert_contains "$STDOUT" "- routing-pr run 1: error: timeout after 300s" "error listed"
  assert_contains "$STDOUT" "- Model: unknown (no traces collected)" "model"
}

# Cases cap max_turns deliberately, so reaching the cap is not an error: the run is
# scored on its graders and the row says it stopped there.
test_turn_cap_is_not_an_error_and_failed_graders_still_listed() {
  case_yaml "$PWD/root" cases/routing/c consilium
  aggregate out "$PWD/root" '[{"name":"routing-c","dir":"cases/routing/c","prompt":"weigh it","runs":[
    {"passed":true,"error":"exit 1: Reached maximum number of turns (6)"},
    {"passed":false,"error":"exit 1: Reached maximum number of turns (6)","graders":[{"name":"route","passed":false,"explanation":"Skill called 0x (expected 1..∞)"}]}]}]'
  summarize
  assert_contains "$(row_of routing-c)" "| 1/2 (2 at turn cap) |" "pass cell"
  assert_not_contains "$STDOUT" "error: exit 1" "cap not listed as an error"
  assert_contains "$STDOUT" "- routing-c run 2: route: Skill called 0x" "failed grader still listed"
}

test_a_pipe_in_the_prompt_does_not_break_the_table() {
  case_yaml "$PWD/root" cases/routing/p explain
  aggregate out "$PWD/root" '[{"name":"routing-p","dir":"cases/routing/p","prompt":"why a | b?","runs":[{"passed":true}]}]'
  summarize
  assert_contains "$(row_of routing-p)" 'why a \| b?' "escaped pipe"
}

test_missing_jq_exits_1() {
  aggregate out "$PWD/root" '[]'
  stub_path >/dev/null
  unstub jq
  summarize
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "jq is required" "stderr"
}

run_tests
