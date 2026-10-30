#!/usr/bin/env bash
# pr-state.sh — the poll orchestrate runs while a pull request waits on CI and
# its review bot. The verdict decides whether a worker is dispatched, so the
# wait / act / timeout / done boundaries are what these cases pin.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

PR_STATE="skills/orchestrate/scripts/pr-state.sh"

# gh is stubbed to apply the script's own --jq expression to fixture JSON, so the
# projections — CI classification above all — run for real. Each case writes:
#   pr.json        gh pr view --json payload
#   timeline.json  REST issue timeline page
#   suites.json    REST check suites of the head commit
#   reviews.json   REST pull request reviews page
#   threads.json   GraphQL reviewThreads response
stub_gh() {
  stub gh <<EOF
expr=""
prev=""
for arg in "\$@"; do
  [ "\$prev" = "--jq" ] && expr="\$arg"
  prev="\$arg"
done
case "\$*" in
  "repo view"*) [ -f "$SANDBOX/repo.txt" ] && cat "$SANDBOX/repo.txt" && exit 0; exit 1 ;;
  "pr view"*) file="$SANDBOX/pr.json" ;;
  "api graphql"*) file="$SANDBOX/threads.json" ;;
  "api "*/timeline*) file="$SANDBOX/timeline.json" ;;
  "api "*/check-suites*) file="$SANDBOX/suites.json" ;;
  "api "*/reviews*) file="$SANDBOX/reviews.json" ;;
  *) echo "stub gh: unexpected invocation: \$*" >&2; exit 1 ;;
esac
[ -f "\$file" ] || { echo "stub gh: no fixture for \$*" >&2; exit 1; }
jq -r "\$expr" "\$file"
EOF
}

HEAD_SHA="abcdef1234567890abcdef1234567890abcdef12"
OLD_SHA="0000000000000000000000000000000000000000"

# ago <seconds> — a timestamp that many seconds before now, in GitHub's format.
ago() {
  jq -nr --argjson s "$1" 'now - $s | floor | todate'
}

# The PR opened an hour ago and its head commit is as old, so every window has
# passed unless a case moves a clock.
CREATED=$(ago 3600)
COMMITTED=$(ago 3600)
SUITE=""
MERGEABLE=MERGEABLE
ROLLUP=""
TIMELINE=""
REVIEWS=""

check_run() {
  printf '{"__typename":"CheckRun","status":"%s","conclusion":%s}' "$1" "$2"
}

# timeline_add <json-object> / review_add <json-object>
timeline_add() { TIMELINE="${TIMELINE:+$TIMELINE,}$1"; }
review_add() { REVIEWS="${REVIEWS:+$REVIEWS,}$1"; }

# bot_requested <time> [login]
bot_requested() {
  timeline_add "$(printf '{"event":"review_requested","requested_reviewer":{"login":"%s","type":"Bot"},"created_at":"%s"}' \
    "${2:-Copilot}" "$1")"
}

human_requested() {
  timeline_add "$(printf '{"event":"review_requested","requested_reviewer":{"login":"rymsha","type":"User"},"created_at":"%s"}' "$1")"
}

force_pushed() {
  timeline_add "$(printf '{"event":"head_ref_force_pushed","created_at":"%s"}' "$1")"
}

# bot_reviewed <time> [commit] [login]
bot_reviewed() {
  review_add "$(printf '{"user":{"login":"%s","type":"Bot"},"commit_id":"%s","submitted_at":"%s"}' \
    "${3:-copilot-pull-request-reviewer[bot]}" "${2:-$HEAD_SHA}" "$1")"
}

# threads <Bot|User>:<true|false> ...   (THREADS_NEXT_PAGE=true marks a second page)
THREADS=""
threads() {
  local t
  THREADS=""
  for t in "$@"; do
    THREADS="${THREADS:+$THREADS,}{\"isResolved\":${t#*:},\"comments\":{\"nodes\":[{\"author\":{\"__typename\":\"${t%%:*}\"}}]}}"
  done
}

write_fixtures() {
  printf '{"state":"%s","headRefOid":"%s","baseRefName":"issue-41","mergeable":"%s","createdAt":"%s","commits":[{"oid":"%s","committedDate":"%s"},{"oid":"%s","committedDate":"%s"}],"statusCheckRollup":[%s]}\n' \
    "${STATE:-OPEN}" "$HEAD_SHA" "$MERGEABLE" "$CREATED" "$HEAD_SHA" "$COMMITTED" "$OLD_SHA" "$(ago 1)" "$ROLLUP" \
    > "$SANDBOX/pr.json"
  printf '[%s]\n' "$TIMELINE" > "$SANDBOX/timeline.json"
  if [ -n "$SUITE" ]; then
    printf '{"check_suites":[{"created_at":"%s"}]}\n' "$SUITE" > "$SANDBOX/suites.json"
  else
    echo '{"check_suites":[]}' > "$SANDBOX/suites.json"
  fi
  printf '[%s]\n' "$REVIEWS" > "$SANDBOX/reviews.json"
  printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"pageInfo":{"hasNextPage":%s},"nodes":[%s]}}}}}\n' \
    "${THREADS_NEXT_PAGE:-false}" "$THREADS" > "$SANDBOX/threads.json"
}

# A green PR whose bot was asked when it opened and reviewed this head.
base_pr() {
  stub_gh
  ROLLUP="$(check_run COMPLETED '"SUCCESS"')"
  bot_requested "$(ago 3590)"
  bot_reviewed "$(ago 3400)"
}

check() {
  write_fixtures
  run bash "$(script "$PR_STATE")" "$@"
}

verdict() {
  last_line "$STDOUT"
}

# ------------------------------------------------------------------- usage --

test_no_argument_is_a_usage_error() {
  stub_gh
  run bash "$(script "$PR_STATE")"
  assert_eq 2 "$STATUS" "exit status"
}

test_non_numeric_pr_is_a_usage_error() {
  stub_gh
  run bash "$(script "$PR_STATE")" 12a acme/widgets
  assert_eq 2 "$STATUS" "exit status"
}

test_repo_without_owner_is_a_usage_error() {
  stub_gh
  run bash "$(script "$PR_STATE")" 12 widgets
  assert_eq 2 "$STATUS" "exit status"
}

test_budget_without_minutes_is_a_usage_error() {
  stub_gh
  run bash "$(script "$PR_STATE")" 12 acme/widgets --budget
  assert_eq 2 "$STATUS" "exit status"
}

test_non_numeric_budget_is_a_usage_error() {
  stub_gh
  run bash "$(script "$PR_STATE")" 12 acme/widgets --budget x
  assert_eq 2 "$STATUS" "exit status"
}

test_missing_gh_is_named() {
  stub_gh
  unstub gh
  run bash "$(script "$PR_STATE")" 12 acme/widgets
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "gh is not installed" "names the missing tool"
}

test_unresolvable_repo_fails() {
  stub_gh
  run bash "$(script "$PR_STATE")" 12
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "pass <owner/repo>" "hint"
}

test_repo_is_resolved_from_the_clone_when_omitted() {
  base_pr
  echo "acme/widgets" > "$SANDBOX/repo.txt"
  check 12
  assert_eq 0 "$STATUS" "exit status"
  assert_eq "VERDICT=done" "$(verdict)" "verdict"
}

# -------------------------------------------------------------- failures --

test_failed_pr_view_exits_1() {
  base_pr
  check 12 acme/widgets
  rm "$SANDBOX/pr.json"
  run bash "$(script "$PR_STATE")" 12 acme/widgets
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "gh pr view" "names the failed query"
}

test_failed_timeline_exits_1() {
  base_pr
  check 12 acme/widgets
  rm "$SANDBOX/timeline.json"
  run bash "$(script "$PR_STATE")" 12 acme/widgets
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "timeline query" "names the failed query"
}

test_failed_threads_query_exits_1_without_a_verdict() {
  base_pr
  check 12 acme/widgets
  rm "$SANDBOX/threads.json"
  run bash "$(script "$PR_STATE")" 12 acme/widgets
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "review threads query" "names the failed query"
  assert_not_contains "$STDOUT" "VERDICT=" "no verdict on failure"
}

# ---------------------------------------------------------------- output --

test_green_reviewed_pr_is_done() {
  base_pr
  check 12 acme/widgets
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "STATE=OPEN HEAD=abcdef1 BASE=issue-41" "state line"
  assert_contains "$STDOUT" "HEAD_MIN=60" "head age"
  assert_contains "$STDOUT" "CI=pass" "ci"
  assert_contains "$STDOUT" "BOT=reviewed BOT_MIN=-" "bot"
  assert_contains "$STDOUT" "THREADS=0 HUMAN_THREADS=0" "threads"
  assert_eq "VERDICT=done" "$(verdict)" "verdict"
}

test_merged_pr_is_merged_whatever_else_holds() {
  base_pr
  STATE=MERGED
  MERGEABLE=UNKNOWN
  ROLLUP="$(check_run COMPLETED '"FAILURE"')"
  threads Bot:false
  check 12 acme/widgets
  assert_eq "VERDICT=merged" "$(verdict)" "verdict"
}

test_closed_pr_is_closed() {
  base_pr
  STATE=CLOSED
  check 12 acme/widgets
  assert_eq "VERDICT=closed" "$(verdict)" "verdict"
}

# -------------------------------------------------------------------- CI --

test_running_check_is_wait() {
  base_pr
  ROLLUP="$(check_run COMPLETED '"SUCCESS"'),$(check_run IN_PROGRESS null)"
  check 12 acme/widgets
  assert_contains "$STDOUT" "CI=pending" "ci"
  assert_eq "VERDICT=wait" "$(verdict)" "verdict"
}

test_pending_status_context_is_wait() {
  base_pr
  ROLLUP='{"__typename":"StatusContext","state":"PENDING"}'
  check 12 acme/widgets
  assert_contains "$STDOUT" "CI=pending" "ci"
}

test_failed_check_is_act_even_while_others_run() {
  base_pr
  ROLLUP="$(check_run COMPLETED '"FAILURE"'),$(check_run QUEUED null)"
  check 12 acme/widgets
  assert_contains "$STDOUT" "CI=fail" "ci"
  assert_eq "VERDICT=act" "$(verdict)" "verdict"
}

test_failed_status_context_is_act() {
  base_pr
  ROLLUP='{"__typename":"StatusContext","state":"ERROR"}'
  check 12 acme/widgets
  assert_eq "VERDICT=act" "$(verdict)" "verdict"
}

test_startup_failure_is_act() {
  base_pr
  ROLLUP="$(check_run COMPLETED '"STARTUP_FAILURE"')"
  check 12 acme/widgets
  assert_contains "$STDOUT" "CI=fail" "ci"
}

test_skipped_and_neutral_checks_pass() {
  base_pr
  ROLLUP="$(check_run COMPLETED '"SUCCESS"'),$(check_run COMPLETED '"SKIPPED"'),$(check_run COMPLETED '"NEUTRAL"')"
  check 12 acme/widgets
  assert_contains "$STDOUT" "CI=pass" "ci"
}

test_stale_and_conclusionless_checks_are_ignored() {
  base_pr
  ROLLUP="$(check_run COMPLETED '"STALE"'),$(check_run COMPLETED null)"
  check 12 acme/widgets
  assert_contains "$STDOUT" "CI=none" "ci"
  assert_eq "VERDICT=done" "$(verdict)" "verdict"
}

test_no_checks_on_an_old_head_is_done() {
  base_pr
  ROLLUP=""
  check 12 acme/widgets
  assert_contains "$STDOUT" "CI=none" "ci"
  assert_eq "VERDICT=done" "$(verdict)" "verdict"
}

test_no_checks_yet_on_a_fresh_head_is_wait() {
  base_pr
  ROLLUP=""
  COMMITTED=$(ago 20)
  bot_requested "$(ago 15)"
  bot_reviewed "$(ago 5)"
  check 12 acme/widgets
  assert_eq "VERDICT=wait" "$(verdict)" "verdict"
}

test_ci_pending_is_wait_even_past_the_bot_budget() {
  base_pr
  REVIEWS=""
  ROLLUP="$(check_run IN_PROGRESS null)"
  check 12 acme/widgets
  assert_eq "VERDICT=wait" "$(verdict)" "verdict"
}

# -------------------------------------------------------------- threads --

test_unresolved_bot_thread_is_act() {
  base_pr
  threads Bot:true Bot:false
  check 12 acme/widgets
  assert_contains "$STDOUT" "THREADS=1 HUMAN_THREADS=0" "threads"
  assert_eq "VERDICT=act" "$(verdict)" "verdict"
}

test_unresolved_human_thread_is_reported_not_act() {
  base_pr
  threads User:false Bot:true
  check 12 acme/widgets
  assert_contains "$STDOUT" "THREADS=0 HUMAN_THREADS=1" "threads"
  assert_eq "VERDICT=done" "$(verdict)" "verdict"
}

test_a_second_page_of_threads_is_act() {
  base_pr
  THREADS_NEXT_PAGE=true
  threads Bot:true
  check 12 acme/widgets
  assert_contains "$STDOUT" "THREADS=100+" "threads"
  assert_eq "VERDICT=act" "$(verdict)" "verdict"
}

test_conflict_is_act() {
  base_pr
  MERGEABLE=CONFLICTING
  check 12 acme/widgets
  assert_eq "VERDICT=act" "$(verdict)" "verdict"
}

# -------------------------------------------------------- review bot --

test_requested_bot_inside_the_budget_is_wait() {
  base_pr
  REVIEWS=""
  TIMELINE=""
  COMMITTED=$(ago 600)
  bot_requested "$(ago 120)"
  check 12 acme/widgets
  assert_contains "$STDOUT" "BOT=requested BOT_MIN=2" "bot"
  assert_eq "VERDICT=wait" "$(verdict)" "verdict"
}

test_requested_bot_past_the_default_budget_is_timeout() {
  base_pr
  REVIEWS=""
  TIMELINE=""
  COMMITTED=$(ago 900)
  bot_requested "$(ago 600)"
  check 12 acme/widgets
  assert_eq "VERDICT=timeout" "$(verdict)" "verdict"
}

test_budget_flag_extends_the_wait() {
  base_pr
  REVIEWS=""
  TIMELINE=""
  COMMITTED=$(ago 900)
  bot_requested "$(ago 600)"
  check 12 acme/widgets --budget 30
  assert_eq "VERDICT=wait" "$(verdict)" "verdict"
}

test_budget_never_hides_act() {
  base_pr
  REVIEWS=""
  threads Bot:false
  check 12 acme/widgets
  assert_eq "VERDICT=act" "$(verdict)" "verdict"
}

test_bot_review_of_an_older_head_does_not_answer() {
  base_pr
  REVIEWS=""
  TIMELINE=""
  COMMITTED=$(ago 600)
  bot_requested "$(ago 120)"
  bot_reviewed "$(ago 60)" "$OLD_SHA"
  check 12 acme/widgets
  assert_contains "$STDOUT" "BOT=requested" "bot"
}

test_request_for_an_earlier_head_is_not_for_this_one() {
  base_pr
  COMMITTED=$(ago 300)
  REVIEWS=""
  check 12 acme/widgets
  assert_contains "$STDOUT" "BOT=none" "bot"
  assert_eq "VERDICT=done" "$(verdict)" "verdict"
}

test_force_push_moves_the_head_past_an_older_request() {
  base_pr
  REVIEWS=""
  TIMELINE=""
  COMMITTED=$(ago 3000)
  bot_requested "$(ago 600)"
  force_pushed "$(ago 400)"
  check 12 acme/widgets
  assert_contains "$STDOUT" "BOT=none" "the request predates the push"
  assert_contains "$STDOUT" "HEAD_MIN=6" "head age from the push"
}

test_check_suite_marks_a_slow_push() {
  base_pr
  REVIEWS=""
  TIMELINE=""
  ROLLUP="$(check_run COMPLETED '"SUCCESS"')"
  COMMITTED=$(ago 600)
  SUITE=$(ago 20)
  check 12 acme/widgets
  assert_contains "$STDOUT" "HEAD_MIN=0" "head age from the push, not the commit"
  assert_eq "VERDICT=wait" "$(verdict)" "attach window"
}

test_no_bot_inside_the_attach_window_is_wait() {
  base_pr
  REVIEWS=""
  TIMELINE=""
  COMMITTED=$(ago 30)
  check 12 acme/widgets
  assert_contains "$STDOUT" "BOT=none" "bot"
  assert_eq "VERDICT=wait" "$(verdict)" "verdict"
}

test_no_bot_after_the_attach_window_is_done() {
  base_pr
  REVIEWS=""
  TIMELINE=""
  COMMITTED=$(ago 90)
  check 12 acme/widgets
  assert_eq "VERDICT=done" "$(verdict)" "verdict"
}

test_request_at_the_head_moment_counts() {
  base_pr
  REVIEWS=""
  TIMELINE=""
  COMMITTED=$(ago 120)
  bot_requested "$COMMITTED"
  check 12 acme/widgets
  assert_contains "$STDOUT" "BOT=requested" "an equal timestamp counts"
}

test_requested_human_reviewer_is_not_waited_for() {
  base_pr
  REVIEWS=""
  TIMELINE=""
  human_requested "$(ago 3590)"
  check 12 acme/widgets
  assert_contains "$STDOUT" "BOT=none" "bot"
  assert_eq "VERDICT=done" "$(verdict)" "verdict"
}

test_one_bot_reviewing_does_not_answer_another() {
  base_pr
  REVIEWS=""
  TIMELINE=""
  COMMITTED=$(ago 600)
  bot_requested "$(ago 180)" Copilot
  bot_requested "$(ago 180)" coderabbitai
  bot_reviewed "$(ago 60)" "$HEAD_SHA" "coderabbitai[bot]"
  check 12 acme/widgets
  assert_contains "$STDOUT" "BOT=requested" "Copilot is still pending"
  assert_eq "VERDICT=wait" "$(verdict)" "verdict"
}

test_review_before_a_re_request_does_not_answer_it() {
  base_pr
  REVIEWS=""
  TIMELINE=""
  COMMITTED=$(ago 600)
  bot_requested "$(ago 500)"
  bot_reviewed "$(ago 400)"
  bot_requested "$(ago 60)"
  check 12 acme/widgets
  assert_contains "$STDOUT" "BOT=requested BOT_MIN=1" "the re-request is pending"
}

test_unknown_mergeability_on_a_fresh_head_is_wait() {
  base_pr
  MERGEABLE=UNKNOWN
  COMMITTED=$(ago 70)
  REVIEWS=""
  TIMELINE=""
  check 12 acme/widgets
  assert_eq "VERDICT=wait" "$(verdict)" "verdict"
}

test_unknown_mergeability_on_an_old_head_is_done() {
  base_pr
  MERGEABLE=UNKNOWN
  check 12 acme/widgets
  assert_eq "VERDICT=done" "$(verdict)" "verdict"
}

test_head_commit_is_found_by_oid_not_position() {
  base_pr
  REVIEWS=""
  TIMELINE=""
  # The fixture lists the head first and an older commit, made a second ago, last.
  COMMITTED=$(ago 600)
  check 12 acme/widgets
  assert_contains "$STDOUT" "HEAD_MIN=10" "uses the head's own date"
}

# ------------------------------------------------------------------ wait --

# sleep is stubbed to record each call, and, when $SANDBOX/pr.next.json exists,
# to swap it in — the state GitHub shows by the next minute.
stub_sleep() {
  stub sleep <<EOF
echo "\$*" >> "$SANDBOX/sleep.calls"
[ -f "$SANDBOX/pr.next.json" ] && mv "$SANDBOX/pr.next.json" "$SANDBOX/pr.json"
exit 0
EOF
}

test_non_numeric_wait_is_a_usage_error() {
  stub_gh
  run bash "$(script "$PR_STATE")" 12 acme/widgets --wait x
  assert_eq 2 "$STATUS" "exit status"
}

test_wait_returns_at_once_when_not_waiting() {
  base_pr
  stub_sleep
  check 12 acme/widgets --wait 60
  assert_eq 0 "$STATUS" "exit status"
  assert_eq "VERDICT=done" "$(verdict)" "verdict"
  assert_eq "" "$(cat "$SANDBOX/sleep.calls" 2>/dev/null)" "never slept"
}

test_wait_stops_when_the_verdict_changes() {
  base_pr
  stub_sleep
  write_fixtures
  cp "$SANDBOX/pr.json" "$SANDBOX/pr.next.json"
  ROLLUP="$(check_run IN_PROGRESS null)"
  check 12 acme/widgets --wait 60
  assert_eq 0 "$STATUS" "exit status"
  assert_eq "VERDICT=done" "$(verdict)" "verdict after CI passed"
  assert_eq "60" "$(cat "$SANDBOX/sleep.calls")" "slept one minute, once"
}

test_wait_gives_up_after_the_minutes_given() {
  base_pr
  stub_sleep
  ROLLUP="$(check_run IN_PROGRESS null)"
  check 12 acme/widgets --wait 2
  assert_eq 0 "$STATUS" "exit status"
  assert_eq "VERDICT=wait" "$(verdict)" "still waiting"
  assert_eq 2 "$(wc -l < "$SANDBOX/sleep.calls" | tr -d ' ')" "slept twice"
  assert_contains "$STDOUT" "CI=pending" "prints the full last check"
}

test_wait_passes_a_failure_through() {
  base_pr
  stub_sleep
  check 12 acme/widgets
  rm "$SANDBOX/timeline.json"
  run bash "$(script "$PR_STATE")" 12 acme/widgets --wait 5
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "timeline query" "names the failed query"
}

run_tests
