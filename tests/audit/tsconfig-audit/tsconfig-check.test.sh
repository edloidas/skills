#!/usr/bin/env bash
# tsconfig-check.mjs — the audit itself needs a TypeScript project and a compiler,
# so what is pinned here is the one thing that fails silently: whether main() runs
# at all. Skills are installed by symlink, and a guard that compares argv[1] to a
# realpath'd import.meta.url skips the audit and exits 0 — indistinguishable from
# a clean report.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

# PATH is deliberately left alone: this is the one script under test that is not
# bash, and the sandbox tool list carries no node.
SKILL_DIR="audit/skills/tsconfig-audit"
CHECK="$SKILL_DIR/scripts/tsconfig-check.mjs"

# An empty directory, so a guard that fired reports the missing tsconfig and a
# guard that did not says nothing.
test_runs_when_invoked_through_the_real_path() {
  run node "$(script "$CHECK")"
  assert_eq 2 "$STATUS" "exit status"
  assert_contains "$STDERR" "No tsconfig found" "stderr"
}

# The shape a skill is actually installed in: ~/.claude/skills/<name> links to
# ~/.agents/skills/<name>, which links on to the checkout.
test_runs_when_invoked_through_a_symlink_chain() {
  ln -s "$(script "$SKILL_DIR")" hop1
  ln -s "$PWD/hop1" hop2
  run node hop2/scripts/tsconfig-check.mjs
  assert_eq 2 "$STATUS" "exit status"
  assert_contains "$STDERR" "No tsconfig found" "stderr"
}

# The other half of the guard: importing the helpers must not start an audit.
test_importing_the_module_does_not_run_the_audit() {
  ln -s "$(script "$SKILL_DIR")" hop1
  printf "await import('file://%s/hop1/scripts/tsconfig-check.mjs')\nconsole.log('imported')\n" "$PWD" > importer.mjs
  run node importer.mjs
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "imported" "stdout"
  assert_not_contains "$STDERR" "No tsconfig found" "stderr"
}

run_tests
