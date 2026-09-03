#!/usr/bin/env bash
# Regressions for --attach handling in the issue update wrapper.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

UPDATE_ISSUE="plan/skills/issue-writer/scripts/update-issue.sh"

test_attach_reaches_gh_once_per_file_with_alt_text() {
  init_repo repo main
  cd repo
  mkdir -p .tmp/screenshots
  : > .tmp/screenshots/one.png
  : > .tmp/screenshots/two.png
  stub_recording gh

  run bash "$(script "$UPDATE_ISSUE")" --issue 42 \
    --attach '.tmp/screenshots/one.png#the clipped tooltip' \
    --attach '.tmp/screenshots/two.png'
  assert_eq 0 "$STATUS" "exit status"

  local calls
  calls="$(calls_of gh)"
  assert_contains "$calls" "issue edit 42" "edits the named issue"
  assert_contains "$calls" "--attach .tmp/screenshots/one.png#the clipped tooltip" "alt text survives"
  assert_contains "$calls" "--attach .tmp/screenshots/two.png" "second file attached"
  assert_eq 2 "$(printf '%s' "$calls" | grep -o -- '--attach' | wc -l | tr -d ' ')" "one flag per file"
}

test_attach_alone_is_a_modification() {
  init_repo repo main
  cd repo
  : > shot.png
  stub_recording gh

  run bash "$(script "$UPDATE_ISSUE")" --issue 7 --attach shot.png
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$(calls_of gh)" "--attach shot.png" "gh was invoked"
}

test_missing_attachment_fails_before_gh_runs() {
  init_repo repo main
  cd repo
  stub_recording gh

  run bash "$(script "$UPDATE_ISSUE")" --issue 7 --title "New title" --attach gone.png
  assert_ne 0 "$STATUS" "exit status"
  assert_contains "$STDOUT$STDERR" "gone.png" "names the missing file"
  assert_eq "" "$(calls_of gh)" "no partial edit was applied"
}

test_missing_attachment_is_detected_behind_alt_text() {
  init_repo repo main
  cd repo
  stub_recording gh

  run bash "$(script "$UPDATE_ISSUE")" --issue 7 --attach 'gone.png#some alt text'
  assert_ne 0 "$STATUS" "exit status"
  assert_eq "" "$(calls_of gh)" "no edit was applied"
}

test_no_modification_still_refused() {
  init_repo repo main
  cd repo
  stub_recording gh

  run bash "$(script "$UPDATE_ISSUE")" --issue 7
  assert_ne 0 "$STATUS" "exit status"
  assert_contains "$STDOUT$STDERR" "--attach" "usage lists the new flag"
  assert_eq "" "$(calls_of gh)" "gh was not invoked"
}

test_unknown_flag_is_still_rejected() {
  init_repo repo main
  cd repo
  stub_recording gh

  run bash "$(script "$UPDATE_ISSUE")" --issue 7 --attatch shot.png
  assert_ne 0 "$STATUS" "exit status"
  assert_contains "$STDOUT$STDERR" "Unknown option" "typo is not silently dropped"
  assert_eq "" "$(calls_of gh)" "gh was not invoked"
}

test_partial_upload_failure_is_reported_not_swallowed() {
  init_repo repo main
  cd repo
  : > shot.png
  stub gh <<'EOF'
echo "https://github.com/o/r/issues/7"
echo "failed to upload shot.png: file too large" >&2
exit 1
EOF

  run bash "$(script "$UPDATE_ISSUE")" --issue 7 --attach shot.png
  assert_ne 0 "$STATUS" "gh's failure is passed through"
  assert_contains "$STDOUT" "Incomplete" "says the edit may be partial"
  assert_contains "$STDOUT" "issues/7" "still shows what gh printed"
  assert_contains "$STDOUT" "appends again" "warns an attach-only retry duplicates"
}

run_tests
