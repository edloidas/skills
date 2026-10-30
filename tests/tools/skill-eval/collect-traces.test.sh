#!/usr/bin/env bash
# tools/skill-eval/scripts/collect-traces.sh — copies each run's trace out of the eval's
# kept, sealed temp directory and deletes that directory, and nothing else.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"
. "$(dirname "$0")/helpers.sh"

COLLECT="tools/skill-eval/scripts/collect-traces.sh"

collect() {
  run bash "$(script "$COLLECT")" out
}

# A kept run directory as the eval leaves it: out/trace.jsonl readable, the rest sealed.
kept_run() {
  mkdir -p "$1/out" "$1/sealed/home"
  trace_init "$1/out/trace.jsonl" "$2"
  chmod 000 "$1/sealed"
  chmod 500 "$1"
}

test_trace_is_copied_per_case_and_run_and_the_kept_dir_removed() {
  kept_run "$PWD/claude-eval-aaa" model-a
  kept_run "$PWD/claude-eval-bbb" model-b
  aggregate out "$PWD" "[{\"name\":\"routing-x\",\"dir\":\"d\",\"prompt\":\"p\",\"runs\":[
    {\"passed\":true,\"trace\":\"$PWD/claude-eval-aaa/out/trace.jsonl\"},
    {\"passed\":true,\"trace\":\"$PWD/claude-eval-bbb/out/trace.jsonl\"}]}]"
  collect
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$(cat out/traces/routing-x/1.jsonl)" model-a "run 1"
  assert_contains "$(cat out/traces/routing-x/2.jsonl)" model-b "run 2"
  assert_no_file claude-eval-aaa
  assert_no_file claude-eval-bbb
  assert_contains "$STDOUT" "Collected 2 trace(s), 0 missing" "output"
}

test_a_directory_not_named_claude_eval_is_never_removed() {
  mkdir -p keepme/out
  trace_init keepme/out/trace.jsonl m
  aggregate out "$PWD" "[{\"name\":\"c\",\"dir\":\"d\",\"prompt\":\"p\",\"runs\":[{\"passed\":true,\"trace\":\"$PWD/keepme/out/trace.jsonl\"}]}]"
  collect
  assert_eq 0 "$STATUS" "exit status"
  assert_file keepme/out/trace.jsonl
  assert_file out/traces/c/1.jsonl
}

test_runs_without_a_trace_are_skipped_or_counted_missing() {
  aggregate out "$PWD" "[{\"name\":\"c\",\"dir\":\"d\",\"prompt\":\"p\",\"runs\":[
    {\"passed\":false,\"error\":\"scaffold failed\"},
    {\"passed\":false,\"trace\":\"$PWD/claude-eval-gone/out/trace.jsonl\"}]}]"
  collect
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Collected 0 trace(s), 1 missing" "output"
}

test_missing_result_exits_1() {
  run bash "$(script "$COLLECT")" nowhere
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "usage: collect-traces.sh" "stderr"
}

run_tests
