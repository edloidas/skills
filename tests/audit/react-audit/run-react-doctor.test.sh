#!/usr/bin/env bash
# run-react-doctor.sh — the flags it hands react-doctor must be ones the pinned
# version accepts. 0.9.18 has no --cwd and no --no-dead-code, and commander
# rejects an unknown option, so passing either failed every run.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

RUN="audit/skills/react-audit/scripts/run-react-doctor.sh"

# A react-doctor on PATH that records its arguments and working directory, and
# writes an empty diagnostics.json where --output-dir points.
setup() {
  stub react-doctor <<STUB
[ "\$1" = "--version" ] && { echo 0.9.18; exit 0; }
printf '%s\n' "\$*" > "$SANDBOX/args"
pwd -P > "$SANDBOX/cwd"
while [ \$# -gt 0 ]; do
  if [ "\$1" = "--output-dir" ]; then echo '[]' > "\$2/diagnostics.json"; fi
  shift
done
exit 0
STUB
  mkdir -p project
}

test_runs_from_the_project_without_unsupported_flags() {
  run bash "$(script "$RUN")" project out.txt diag --scope files --include-untracked
  assert_eq 0 "$STATUS" "exit status"
  assert_eq "$(cd "$SANDBOX/project" && pwd -P)" "$(cat "$SANDBOX/cwd")" "react-doctor working directory"
  assert_not_contains "$(cat "$SANDBOX/args")" "--cwd" "arguments"
  assert_not_contains "$(cat "$SANDBOX/args")" "--no-dead-code" "arguments"
  assert_contains "$(cat "$SANDBOX/args")" "--scope files --include-untracked" "arguments"
}

test_relative_output_paths_land_outside_the_project() {
  run bash "$(script "$RUN")" project out.txt diag
  assert_eq 0 "$STATUS" "exit status"
  assert_file "$SANDBOX/out.txt"
  assert_file "$SANDBOX/diag/diagnostics.json"
  assert_no_file "$SANDBOX/project/diag"
}

test_missing_project_dir_exits_4() {
  run bash "$(script "$RUN")" nowhere out.txt diag
  assert_eq 4 "$STATUS" "exit status"
  assert_contains "$(cat out.txt)" "project directory not found" "output file"
}

run_tests
