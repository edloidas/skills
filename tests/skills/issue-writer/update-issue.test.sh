#!/usr/bin/env bash
# Regressions for --attach handling in the issue update wrapper.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

UPDATE_ISSUE="skills/issue-writer/scripts/update-issue.sh"

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

test_body_file_reaches_gh_as_a_file() {
  init_repo repo main
  cd repo
  printf '%s\n' 'Uses `$(id)` and `$HOME` verbatim.' > body.md
  stub_recording gh

  run bash "$(script "$UPDATE_ISSUE")" --issue 7 --body-file body.md
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$(calls_of gh)" "--body-file body.md" "gh reads the body itself"
  assert_not_contains "$(calls_of gh)" "--body " "the body is not passed as an argument"
}

test_flag_without_value_is_refused_before_gh() {
  init_repo repo main
  cd repo
  stub_recording gh

  run bash "$(script "$UPDATE_ISSUE")" --issue 7 --title
  assert_ne 0 "$STATUS" "exit status"
  assert_contains "$STDOUT$STDERR" "--title needs a value" "names the flag"
  assert_eq "" "$(calls_of gh)" "gh was not invoked"
}

test_unrecognised_issue_reference_is_refused_before_gh() {
  init_repo repo main
  cd repo
  stub_recording gh

  run bash "$(script "$UPDATE_ISSUE")" --issue 'latest' --title "New title"
  assert_ne 0 "$STATUS" "exit status"
  assert_contains "$STDOUT$STDERR" "Not an issue reference: latest" "names the bad reference"
  assert_eq "" "$(calls_of gh)" "gh was not invoked"
}

test_issue_url_resolves_to_its_number() {
  init_repo repo main
  cd repo
  stub_recording gh

  run bash "$(script "$UPDATE_ISSUE")" --issue 'https://github.com/o/r/issues/42' --title "New title"
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$(calls_of gh)" "issue edit 42 --repo o/r" "edits that number in the URL's repository"
}

test_short_reference_targets_its_own_repository() {
  init_repo repo main
  cd repo
  stub_recording gh

  run bash "$(script "$UPDATE_ISSUE")" --issue 'other/proj#9' --title "New title"
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$(calls_of gh)" "issue edit 9 --repo other/proj" "never the same number in the current repository"
}

test_missing_body_file_fails_before_gh_runs() {
  init_repo repo main
  cd repo
  stub_recording gh

  run bash "$(script "$UPDATE_ISSUE")" --issue 7 --body-file gone.md
  assert_ne 0 "$STATUS" "exit status"
  assert_contains "$STDOUT$STDERR" "gone.md" "names the missing file"
  assert_eq "" "$(calls_of gh)" "gh was not invoked"
}

run_tests
