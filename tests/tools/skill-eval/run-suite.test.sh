#!/usr/bin/env bash
# tools/skill-eval/scripts/run-suite.sh — the flags it hands `claude plugin eval`, and
# that it collects and summarizes whatever result comes back. `claude` is a stub here:
# no case in this file calls a model.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"
. "$(dirname "$0")/helpers.sh"

RUN_SUITE="tools/skill-eval/scripts/run-suite.sh"

# A stub `claude` that records its arguments and writes a one-case result into --output-dir,
# exiting with $FAKE_EVAL_EXIT.
fake_claude() {
  stub_path >/dev/null
  stub claude <<'STUB'
printf '%s\n' "$@" > "$SANDBOX/claude.args"
dir=""
prev=""
for a in "$@"; do
  [ "$prev" = "--output-dir" ] && dir="$a"
  prev="$a"
done
[ -n "$dir" ] || exit 1
mkdir -p "$dir"
cat > "$dir/aggregate-result.json" <<JSON
{"claudeVersion":"2.1.314","startedAt":"t","durationSeconds":1,"costUsd":0.1,"partial":false,
 "suite":{"root":"$SANDBOX/none","ablation":"none"},
 "cases":[{"name":"routing-x","dir":"d","promptMarkdown":"p","arms":{"with":[{"passed":true,"error":null,"tracePath":"","graders":[]}]}}],
 "aggregates":{"casesTotal":1,"casesPassed":1}}
JSON
exit "${FAKE_EVAL_EXIT:-0}"
STUB
}

args() { cat "$SANDBOX/claude.args"; }

test_no_suite_prints_usage_and_exits_1() {
  run bash "$(script "$RUN_SUITE")"
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "run-suite.sh <suite>" "usage"
}

test_missing_claude_exits_1_before_running() {
  stub_path >/dev/null
  run bash "$(script "$RUN_SUITE")" routing --out "$PWD/out"
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "claude is required" "stderr"
}

test_defaults_run_the_tagged_suite_three_times_one_arm_read_only() {
  fake_claude
  run bash "$(script "$RUN_SUITE")" routing --out "$PWD/out"
  assert_eq 0 "$STATUS" "exit status"
  a="$(args | tr '\n' ' ')"
  assert_contains "$a" "plugin eval $REPO_ROOT " "plugin is the repo root"
  assert_contains "$a" "--eval-dir tools/skill-eval/cases" "eval dir"
  assert_contains "$a" "--tag routing" "suite tag"
  assert_contains "$a" "--runs 3" "default runs"
  assert_contains "$a" "--ablation none" "one arm"
  assert_contains "$a" "--disallow-tools Agent" "no subagents"
  assert_contains "$a" "--output-dir $PWD/out" "output dir"
  assert_not_contains "$a" "--allow-tools" "no gated tools granted"
  assert_not_contains "$a" "--model" "no model override"
}

test_options_are_passed_through() {
  fake_claude
  run bash "$(script "$RUN_SUITE")" ambient --runs 1 --model claude-sonnet-5 --case 'ambient-ex*' --jobs 4 --out "$PWD/out"
  a="$(args | tr '\n' ' ')"
  assert_contains "$a" "--runs 1" "runs"
  assert_contains "$a" "--model claude-sonnet-5" "model"
  assert_contains "$a" "--case ambient-ex*" "case glob"
  assert_contains "$a" "--concurrency 4" "jobs"
}

test_summary_is_written_and_the_eval_exit_status_kept() {
  fake_claude
  FAKE_EVAL_EXIT=1 run bash "$(script "$RUN_SUITE")" routing --out "$PWD/out"
  assert_eq 1 "$STATUS" "eval exit status propagated"
  assert_file out/summary.md
  assert_contains "$(cat out/summary.md)" "# Skill eval: routing" "summary"
  assert_contains "$STDOUT" "| routing-x | p |" "summary printed"
}

test_unknown_option_prints_usage() {
  run bash "$(script "$RUN_SUITE")" routing --bogus
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "run-suite.sh <suite>" "usage"
}

run_tests
