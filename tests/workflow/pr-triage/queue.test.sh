#!/usr/bin/env bash
# Behaviour of pr-triage's queue.sh: merging the review searches, the created
# set, the "moved since my verdict" flag, counting other people's activity,
# scoping, and refusals.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

QUEUE="workflow/skills/pr-triage/scripts/queue.sh"

# gh answers `api user` with "me" and `api graphql` with ./response.json, and
# records the graphql arguments so a case can check the search qualifiers.
stub_gh_with_response() {
  stub gh <<'EOF'
if [ "$1" = "api" ] && [ "$2" = "user" ]; then
  echo me
  exit 0
fi
if [ "$1" = "api" ] && [ "$2" = "graphql" ]; then
  printf '%s\n' "$*" >> "$PWD/graphql.calls"
  cat "$PWD/response.json"
  exit 0
fi
echo "unexpected gh: $*" >&2
exit 1
EOF
}

# pr <number> <repo> <head> [extra-json-fields]
pr() {
  local extra="${4:-}"
  printf '{"number":%s,"title":"PR %s","url":"https://github.com/%s/pull/%s","isDraft":false,"updatedAt":"2026-10-09T10:00:00Z","headRefOid":"%s","mergeStateStatus":"CLEAN","author":{"login":"alice"},"repository":{"nameWithOwner":"%s"},"commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]},"mine":{"nodes":[]},"reviews":{"nodes":[]},"comments":{"nodes":[]},"reviewThreads":{"nodes":[]},"reviewDecision":null%s}' \
    "$1" "$1" "$2" "$1" "$3" "$2" "$extra"
}

# respond <requested> <reviewed> [created]
respond() {
  printf '{"data":{"requested":{"nodes":[%s]},"reviewed":{"nodes":[%s]},"created":{"nodes":[%s]}}}' \
    "$1" "$2" "${3:-}" > response.json
}

row_for() {
  printf '%s\n' "$STDOUT" | grep -F "$1	"
}

field() {
  printf '%s' "$1" | cut -f "$2"
}

test_merges_searches_and_orders_reasons() {
  stub_gh_with_response
  respond "$(pr 7 o/b aaaaaaaaaaaa)" "$(pr 7 o/b aaaaaaaaaaaa),$(pr 3 o/a bbbbbbbbbbbb)"
  run bash "$(script "$QUEUE")"
  assert_eq 0 "$STATUS" "exit status"
  assert_eq 3 "$(printf '%s\n' "$STDOUT" | wc -l | tr -d ' ')" "header plus two rows"
  assert_eq "o/a#3" "$(printf '%s\n' "$STDOUT" | sed -n 2p | cut -f1)" "sorted by repository"
  assert_eq "requested,reviewed" "$(field "$(row_for 'o/b#7')" 4)" "reasons merged in fixed order"
}

test_created_rows_have_no_verdict_and_count_since_my_latest_activity() {
  stub_gh_with_response
  local own
  own="$(pr 4 o/r h44444444444 ',"author":{"login":"me"},"reviewDecision":"CHANGES_REQUESTED","commits":{"nodes":[{"commit":{"committedDate":"2026-10-08T10:00:00Z","statusCheckRollup":{"state":"SUCCESS"}}}]},"comments":{"nodes":[{"author":{"login":"bob"},"createdAt":"2026-10-08T09:00:00Z"},{"author":{"login":"bob"},"createdAt":"2026-10-08T11:00:00Z"},{"author":{"login":"me"},"createdAt":"2026-10-08T12:00:00Z"},{"author":{"login":"carol"},"createdAt":"2026-10-08T13:00:00Z"}]},"reviewThreads":{"nodes":[{"isResolved":true},{"isResolved":false},{"isResolved":false}]}')"
  respond "" "" "$own"
  run bash "$(script "$QUEUE")"
  local row
  row="$(row_for 'o/r#4')"
  assert_eq "created" "$(field "$row" 4)" "own pull request"
  assert_eq "-" "$(field "$row" 5)" "no verdict on my own"
  assert_eq "-" "$(field "$row" 6)" "no moved flag on my own"
  assert_eq "1" "$(field "$row" 7)" "only activity after my own latest comment"
  assert_eq "CHANGES_REQUESTED" "$(field "$row" 8)" "review decision"
  assert_eq "2" "$(field "$row" 9)" "unresolved threads"
  assert_eq "needs-you" "$(field "$row" 14)" "changes requested on my own"
}

test_only_selects_the_searches() {
  stub_gh_with_response
  respond "" "" ""
  run bash "$(script "$QUEUE")"
  assert_contains "$(cat graphql.calls)" "review=true" "review searches on by default"
  assert_contains "$(cat graphql.calls)" "own=true" "created search on by default"
  : > graphql.calls
  run bash "$(script "$QUEUE")" --only review
  assert_contains "$(cat graphql.calls)" "own=false" "created search off"
  : > graphql.calls
  run bash "$(script "$QUEUE")" --only created
  assert_contains "$(cat graphql.calls)" "review=false" "review searches off"
  assert_contains "$(cat graphql.calls)" "own=true" "created search on"
}

test_repo_scopes_every_search() {
  stub_gh_with_response
  respond "" "" ""
  run bash "$(script "$QUEUE")" --repo enonic/app-users
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$(cat graphql.calls)" "repo:enonic/app-users review-requested:me -author:me" "requested search scoped"
  assert_contains "$(cat graphql.calls)" "repo:enonic/app-users reviewed-by:me" "reviewed search scoped"
  assert_contains "$(cat graphql.calls)" "repo:enonic/app-users author:me" "created search scoped"
}

test_moved_compares_verdict_commit_with_head() {
  stub_gh_with_response
  local same moved
  same="$(pr 1 o/r head1111111 ',"mine":{"nodes":[{"state":"CHANGES_REQUESTED","submittedAt":"2026-10-08T10:00:00Z","commit":{"oid":"head1111111"}}]}')"
  moved="$(pr 2 o/r head2222222 ',"mine":{"nodes":[{"state":"CHANGES_REQUESTED","submittedAt":"2026-10-08T10:00:00Z","commit":{"oid":"old0000000"}},{"state":"COMMENTED","submittedAt":"2026-10-08T12:00:00Z","commit":{"oid":"head2222222"}}]}')"
  respond "" "$same,$moved,$(pr 3 o/r head3333333)"
  run bash "$(script "$QUEUE")"
  assert_eq "no" "$(field "$(row_for 'o/r#1')" 6)" "head equals verdict commit"
  assert_eq "yes" "$(field "$(row_for 'o/r#2')" 6)" "a later comment does not hide a moved head"
  assert_eq "CHANGES_REQUESTED" "$(field "$(row_for 'o/r#2')" 5)" "verdict, not the later comment"
  assert_eq "-" "$(field "$(row_for 'o/r#3')" 6)" "never reviewed"
  assert_eq "none" "$(field "$(row_for 'o/r#3')" 5)" "no review state"
  assert_eq "no-change" "$(field "$(row_for 'o/r#1')" 14)" "verdict stands, nothing since"
  assert_eq "recheck" "$(field "$(row_for 'o/r#2')" 14)" "head moved since the verdict"
  assert_eq "fresh" "$(field "$(row_for 'o/r#3')" 14)" "never reviewed"
}

test_set_rechecks_a_repeat_request_and_classifies_my_own() {
  stub_gh_with_response
  local asked ready waiting
  asked="$(pr 1 o/r head1111111 ',"mine":{"nodes":[{"state":"APPROVED","submittedAt":"2026-10-08T10:00:00Z","commit":{"oid":"head1111111"}}]}')"
  ready="$(pr 2 o/r head2222222 ',"author":{"login":"me"},"reviewDecision":"APPROVED"')"
  waiting="$(pr 3 o/r head3333333 ',"author":{"login":"me"},"isDraft":true,"reviewDecision":"APPROVED"')"
  respond "$asked" "$asked" "$ready,$waiting"
  run bash "$(script "$QUEUE")"
  assert_eq "recheck" "$(field "$(row_for 'o/r#1')" 14)" "requested again with nothing moved"
  assert_eq "ready" "$(field "$(row_for 'o/r#2')" 14)" "approved, green, clean"
  assert_eq "waiting" "$(field "$(row_for 'o/r#3')" 14)" "a draft waits"
}

test_others_counts_only_after_my_latest_review() {
  stub_gh_with_response
  local one
  one="$(pr 5 o/r h55555555555 ',"mine":{"nodes":[{"state":"APPROVED","submittedAt":"2026-10-08T10:00:00Z","commit":{"oid":"h55555555555"}}]},"reviews":{"nodes":[{"author":{"login":"bob"},"submittedAt":"2026-10-08T09:00:00Z"},{"author":{"login":"bob"},"submittedAt":"2026-10-08T11:00:00Z"},{"author":{"login":"me"},"submittedAt":"2026-10-08T12:00:00Z"}]},"comments":{"nodes":[{"author":{"login":"alice"},"createdAt":"2026-10-09T08:00:00Z"},{"author":null,"createdAt":"2026-10-09T09:00:00Z"}]}')"
  respond "" "$one"
  run bash "$(script "$QUEUE")"
  assert_eq "2" "$(field "$(row_for 'o/r#5')" 7)" "one later review and one later comment by others"
  assert_eq "recheck" "$(field "$(row_for 'o/r#5')" 14)" "others commented since the verdict"
}

test_others_ignores_bots() {
  stub_gh_with_response
  local one
  one="$(pr 8 o/r h88888888888 ',"comments":{"nodes":[{"author":{"login":"copilot-pull-request-reviewer","__typename":"Bot"},"createdAt":"2026-10-09T08:00:00Z"},{"author":{"login":"bob","__typename":"User"},"createdAt":"2026-10-09T09:00:00Z"}]}')"
  respond "$one" "" ""
  run bash "$(script "$QUEUE")"
  assert_eq "1" "$(field "$(row_for 'o/r#8')" 7)" "the bot comment is not counted"
}

test_missing_checks_and_tabs_in_title() {
  stub_gh_with_response
  printf '{"data":{"requested":{"nodes":[{"number":9,"title":"a\\tb","url":"u9","isDraft":true,"updatedAt":"t","headRefOid":"abcdef1234567","mergeStateStatus":null,"author":null,"repository":{"nameWithOwner":"o/r"},"commits":{"nodes":[{"commit":{"statusCheckRollup":null}}]},"mine":{"nodes":[]},"reviews":{"nodes":[]},"comments":{"nodes":[]}}]},"reviewed":{"nodes":[]}}}' > response.json
  run bash "$(script "$QUEUE")"
  local row
  row="$(row_for 'o/r#9')"
  assert_eq "draft" "$(field "$row" 3)" "draft flag"
  assert_eq "NONE" "$(field "$row" 8)" "no review decision"
  assert_eq "0" "$(field "$row" 9)" "no thread data"
  assert_eq "NONE" "$(field "$row" 10)" "no status rollup"
  assert_eq "UNKNOWN" "$(field "$row" 11)" "no merge state"
  assert_eq "ghost" "$(field "$row" 2)" "deleted author"
  assert_eq "a b" "$(field "$row" 15)" "tab in title flattened"
}

test_owner_scopes_every_search() {
  stub_gh_with_response
  respond "" "" ""
  run bash "$(script "$QUEUE")" --owner enonic
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$(cat graphql.calls)" "user:enonic review-requested:me" "requested search scoped"
  assert_contains "$(cat graphql.calls)" "reviewed-by:me -author:me" "own PRs excluded from reviewed"
  assert_eq 1 "$(printf '%s\n' "$STDOUT" | wc -l | tr -d ' ')" "header only on an empty queue"
}

test_usage_errors() {
  stub_gh_with_response
  run bash "$(script "$QUEUE")" --limit many
  assert_eq 2 "$STATUS" "non-numeric limit"
  run bash "$(script "$QUEUE")" --limit 0
  assert_eq 2 "$STATUS" "zero limit"
  run bash "$(script "$QUEUE")" --owner 'a b'
  assert_eq 2 "$STATUS" "invalid owner"
  run bash "$(script "$QUEUE")" --bogus
  assert_eq 2 "$STATUS" "unknown flag"
  run bash "$(script "$QUEUE")" --only assigned
  assert_eq 2 "$STATUS" "unknown set"
  run bash "$(script "$QUEUE")" --repo app-users
  assert_eq 2 "$STATUS" "repo without owner"
  run bash "$(script "$QUEUE")" --repo 'o/r;x'
  assert_eq 2 "$STATUS" "repo with a stray character"
  run bash "$(script "$QUEUE")" --owner
  assert_eq 2 "$STATUS" "flag without a value"
}

test_warns_when_a_search_hits_the_limit() {
  stub_gh_with_response
  respond "$(pr 1 o/r h1111111111),$(pr 2 o/r h2222222222)" "" ""
  run bash "$(script "$QUEUE")" --limit 2
  assert_eq 0 "$STATUS" "still lists"
  assert_contains "$STDERR" "WARN: the requested search returned 2 results" "names the capped search"
  run bash "$(script "$QUEUE")" --limit 3
  assert_not_contains "$STDERR" "WARN" "no warning under the cap"
}

test_warns_when_a_pull_request_fills_the_comment_window() {
  stub_gh_with_response
  local comments="" i
  for i in $(seq 1 50); do
    comments="${comments:+$comments,}{\"author\":{\"login\":\"bob\"},\"createdAt\":\"2026-10-09T08:00:00Z\"}"
  done
  respond "$(pr 4 o/r h4444444444 ",\"comments\":{\"nodes\":[$comments]}"),$(pr 6 o/r h6666666666)" "" ""
  run bash "$(script "$QUEUE")"
  assert_contains "$STDERR" "WARN: o/r#4 fills the fetched reviews, comments or threads" "names the capped pull request"
  assert_not_contains "$STDERR" "o/r#6" "only the capped one"
}

test_gh_failure_and_missing_gh() {
  stub gh <<'EOF'
echo "HTTP 401: Bad credentials" >&2
exit 1
EOF
  run bash "$(script "$QUEUE")"
  assert_eq 1 "$STATUS" "gh failed"
  assert_contains "$STDERR" "Bad credentials" "keeps gh's own error"
  no_gh
  run bash "$(script "$QUEUE")"
  assert_eq 1 "$STATUS" "gh missing"
  assert_contains "$STDERR" "gh not found" "names the missing tool"
}

run_tests
