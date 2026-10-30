#!/usr/bin/env bash
# fetch-issue.sh: argument parsing, the single GraphQL call, and its refusals.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

FETCH="skills/issue-analyze/scripts/fetch-issue.sh"

ISSUE_OPEN='{"data":{"viewer":{"login":"me"},"repository":{"issue":{"number":42,"title":"Add X","body":"Do X","state":"OPEN","url":"https://github.com/acme/widgets/issues/42","labels":{"nodes":[{"name":"bug"}]},"assignees":{"nodes":[{"login":"other"}]},"comments":{"totalCount":1,"nodes":[{"author":{"login":"other"},"body":"narrow it","createdAt":"2026-01-01T00:00:00Z"}]},"subIssues":{"totalCount":2,"nodes":[{"number":43,"title":"Part A","body":"a","state":"CLOSED"},{"number":44,"title":"Part B","body":"b","state":"OPEN"}]}}}}}'

# gh answering `repo view` with acme/widgets and the issue query with $1.
stub_gh_issue() {
  printf '%s' "$1" > "$SANDBOX/issue.json"
  stub gh <<'EOF'
printf '%s\n' "$*" >> "$SANDBOX/gh.calls"
if [ "$1" = "repo" ] && [ "$2" = "view" ]; then
  echo acme/widgets
  exit 0
fi
if [ "$1" = "api" ] && [ "$2" = "graphql" ]; then
  cat "$SANDBOX/issue.json"
  case "$(cat "$SANDBOX/issue.json")" in *'"errors"'*) exit 1 ;; esac
  exit 0
fi
echo "unexpected gh: $*" >&2
exit 1
EOF
}

test_bare_number_resolves_the_current_repo() {
  stub_gh_issue "$ISSUE_OPEN"

  run bash "$(script "$FETCH")" 42
  assert_eq 0 "$STATUS" "exit status"
  assert_eq "acme/widgets" "$(printf '%s' "$STDOUT" | jq -r .repo)" "repo"
  assert_eq "me" "$(printf '%s' "$STDOUT" | jq -r .login)" "login"
  assert_eq "open false" "$(printf '%s' "$STDOUT" | jq -r '"\(.state) \(.closed)"')" "state"
  assert_eq "other" "$(printf '%s' "$STDOUT" | jq -r '.assignees | join(",")')" "assignees"
  assert_eq "narrow it" "$(printf '%s' "$STDOUT" | jq -r '.comments[0].body')" "comment"
  assert_eq "43:closed 44:open" "$(printf '%s' "$STDOUT" | jq -r '[.subIssues[] | "\(.number):\(.state)"] | join(" ")')" "sub-issues"
  assert_eq "1" "$(grep -c '^api graphql' "$SANDBOX/gh.calls")" "graphql calls"
  assert_contains "$(cat "$SANDBOX/gh.calls")" "number=42" "issue number passed"
}

test_hash_prefix_is_accepted() {
  stub_gh_issue "$ISSUE_OPEN"

  run bash "$(script "$FETCH")" '#42'
  assert_eq 0 "$STATUS" "exit status"
  assert_eq 42 "$(printf '%s' "$STDOUT" | jq -r .number)" "number"
}

test_url_from_another_repo_uses_that_repo() {
  stub_gh_issue "$ISSUE_OPEN"

  run bash "$(script "$FETCH")" "https://github.com/other-org/tools/issues/42?foo=1"
  assert_eq 0 "$STATUS" "exit status"
  assert_eq "other-org/tools" "$(printf '%s' "$STDOUT" | jq -r .repo)" "repo"
  calls="$(cat "$SANDBOX/gh.calls")"
  assert_not_contains "$calls" "repo view" "cwd repo lookup"
  assert_contains "$calls" "owner=other-org" "owner"
  assert_contains "$calls" "name=tools" "name"
}

test_pull_request_url_is_refused() {
  stub_gh_issue "$ISSUE_OPEN"

  run bash "$(script "$FETCH")" "https://github.com/acme/widgets/pull/42"
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "not an issue URL" "error"
}

test_closed_issue_is_flagged() {
  stub_gh_issue "$(printf '%s' "$ISSUE_OPEN" | sed 's/"state":"OPEN","url"/"state":"CLOSED","url"/')"

  run bash "$(script "$FETCH")" 42
  assert_eq 0 "$STATUS" "exit status"
  assert_eq "closed true" "$(printf '%s' "$STDOUT" | jq -r '"\(.state) \(.closed)"')" "closed flag"
}

test_undefined_sub_issues_retries_without_them() {
  stub gh <<'EOF'
printf '%s\n' "$*" >> "$SANDBOX/gh.calls"
if [ "$1" = "api" ] && [ "$2" = "graphql" ]; then
  case "$*" in
    *subIssues*)
      echo '{"errors":[{"extensions":{"code":"undefinedField"},"message":"Field '"'"'subIssues'"'"' doesn'"'"'t exist on type '"'"'Issue'"'"'"}]}'
      exit 1 ;;
  esac
  echo '{"data":{"viewer":{"login":"me"},"repository":{"issue":{"number":7,"title":"T","body":"","state":"OPEN","url":"u","labels":{"nodes":[]},"assignees":{"nodes":[]},"comments":{"totalCount":0,"nodes":[]}}}}}'
  exit 0
fi
echo "unexpected gh: $*" >&2
exit 1
EOF

  run bash "$(script "$FETCH")" https://github.com/acme/widgets/issues/7
  assert_eq 0 "$STATUS" "exit status"
  assert_eq "null" "$(printf '%s' "$STDOUT" | jq -c .subIssues)" "sub-issues"
  assert_contains "$(printf '%s' "$STDOUT" | jq -r '.unavailable[0]')" "subIssues — Field 'subIssues' doesn't exist" "unavailable"
  assert_eq "2" "$(grep -c '^api graphql' "$SANDBOX/gh.calls")" "graphql calls"
}

test_not_found_issue() {
  stub_gh_issue '{"data":{"viewer":{"login":"me"},"repository":{"issue":null}},"errors":[{"type":"NOT_FOUND","path":["repository","issue"],"message":"Could not resolve to an Issue with the number of 999."}]}'

  run bash "$(script "$FETCH")" 999
  assert_eq 2 "$STATUS" "exit status"
  assert_eq "Issue #999 not found in acme/widgets." "$STDERR" "error"
  assert_eq "" "$STDOUT" "stdout"
}

test_not_found_repository() {
  stub_gh_issue '{"data":{"viewer":{"login":"me"},"repository":null},"errors":[{"type":"NOT_FOUND","path":["repository"],"message":"Could not resolve to a Repository with the name '"'"'acme/gone'"'"'."}]}'

  run bash "$(script "$FETCH")" https://github.com/acme/gone/issues/1
  assert_eq 2 "$STATUS" "exit status"
  assert_eq "Repository acme/gone not found." "$STDERR" "error"
}

test_unauthenticated_gh_is_a_clear_error() {
  stub gh <<'EOF'
echo '{"message":"Requires authentication","status":"401"}' >&2
echo 'gh: Requires authentication (HTTP 401)' >&2
exit 1
EOF

  run bash "$(script "$FETCH")" https://github.com/acme/widgets/issues/1
  assert_eq 3 "$STATUS" "exit status"
  assert_eq 'Run `gh auth login` first.' "$STDERR" "error"
}

test_unauthenticated_repo_lookup_is_a_clear_error() {
  stub gh <<'EOF'
echo 'To get started with GitHub CLI, please run:  gh auth login' >&2
exit 4
EOF

  run bash "$(script "$FETCH")" 5
  assert_eq 3 "$STATUS" "exit status"
  assert_eq 'Run `gh auth login` first.' "$STDERR" "error"
}

test_no_repository_and_no_url() {
  stub gh <<'EOF'
echo 'failed to run git: fatal: not a git repository' >&2
exit 1
EOF

  run bash "$(script "$FETCH")" 5
  assert_eq 5 "$STATUS" "exit status"
  assert_contains "$STDERR" "Provide a full GitHub URL" "error"
}

test_non_numeric_argument_is_refused() {
  stub_gh_issue "$ISSUE_OPEN"

  run bash "$(script "$FETCH")" abc
  assert_eq 1 "$STATUS" "exit status"
  assert_eq "" "$(cat "$SANDBOX/gh.calls" 2>/dev/null)" "gh calls"
}

test_missing_gh() {
  stub_path > /dev/null
  unstub gh

  run bash "$(script "$FETCH")" 5
  assert_eq 4 "$STATUS" "exit status"
  assert_contains "$STDERR" "gh CLI is not installed" "error"
}

run_tests
