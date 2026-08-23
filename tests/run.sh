#!/usr/bin/env bash
# run.sh — behavioral test suite for the shell scripts this repo bundles.
#
#   bash tests/run.sh                        every test file
#   bash tests/run.sh detect-base            only files whose path matches
#   bash tests/run.sh plan/ ship/            several filters
#
# Plain bash by design: a contributor runs it from a clean checkout with no
# install step, and CI provisions nothing. `bats` would read better and cost a
# dependency that a skills collection should not need.
#
# A test file is `tests/**/*.test.sh`. It sources lib/assert.sh and
# lib/fixture.sh, defines `test_*` functions, and ends with `run_tests`.
#
# Exit codes: 0 = every case passed, 1 = at least one failed or the discovery
# found nothing to run.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/.." && pwd)"
export REPO_ROOT

# Test files are found by path, not by a manifest, so adding one is a single
# new file and never an edit here.
ALL_FILES="$(find "$TESTS_DIR" -name '*.test.sh' -type f | sort)"

if [ -z "$ALL_FILES" ]; then
  echo "no test files found under $TESTS_DIR" >&2
  exit 1
fi

# Filters match against the path relative to tests/, so `detect-base`,
# `plan/issue-flow`, and `plan/` all select sensibly.
FILES=""
if [ "$#" -eq 0 ]; then
  FILES="$ALL_FILES"
else
  while IFS= read -r file; do
    rel="${file#$TESTS_DIR/}"
    for filter in "$@"; do
      case "$rel" in
        *"$filter"*) FILES="$FILES$file
"; break ;;
      esac
    done
  done <<EOF
$ALL_FILES
EOF
fi

if [ -z "$FILES" ]; then
  echo "no test files matched: $*" >&2
  exit 1
fi

files_run=0
files_failed=0
failed_list=""

while IFS= read -r file; do
  [ -n "$file" ] || continue
  files_run=$((files_run + 1))
  rel="${file#$TESTS_DIR/}"
  echo "$rel"
  # Each file is a separate bash process: one file's `set -e`, exported stubs,
  # or stray global cannot reach the next.
  if ! bash "$file"; then
    files_failed=$((files_failed + 1))
    failed_list="$failed_list  $rel
"
  fi
  echo
done <<EOF
$FILES
EOF

echo "================================"
if [ "$files_failed" -eq 0 ]; then
  echo "PASS — $files_run test file(s)"
  exit 0
fi

echo "FAIL — $files_failed of $files_run test file(s) failed:"
printf '%s' "$failed_list"
exit 1
