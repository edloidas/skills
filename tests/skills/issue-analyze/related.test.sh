#!/usr/bin/env bash
# related.sh: the related set, and how each GraphQL failure becomes an
# `unavailable:` line instead of a failure.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

RELATED="skills/issue-analyze/scripts/related.sh"

PARENT_OK='{"data":{"repository":{"issue":{"parent":{"number":10,"title":"Epic","state":"OPEN","subIssues":{"nodes":[{"number":42,"title":"This","state":"OPEN"},{"number":43,"title":"Done one","state":"CLOSED"},{"number":44,"title":"Next one","state":"OPEN"}]}},"timelineItems":{"nodes":[{"willCloseTarget":true,"source":{"__typename":"PullRequest","number":50,"title":"Fix it","state":"OPEN","repository":{"nameWithOwner":"acme/widgets"}}},{"willCloseTarget":false,"source":{"__typename":"Issue","number":7,"title":"Elsewhere","state":"OPEN","repository":{"nameWithOwner":"acme/other"}}},{"willCloseTarget":false,"source":{}}]}}}}}'
BLOCKED_OK='{"data":{"repository":{"issue":{"blockedBy":{"nodes":[{"number":30,"title":"Lands first","state":"OPEN","repository":{"nameWithOwner":"acme/widgets"}}]},"blocking":{"nodes":[{"number":60,"title":"Needs this","state":"OPEN","repository":{"nameWithOwner":"acme/widgets"}}]}}}}}'
UNDEFINED='{"errors":[{"path":["query","repository","issue","blockedBy"],"extensions":{"code":"undefinedField","typeName":"Issue","fieldName":"blockedBy"},"message":"Field '"'"'blockedBy'"'"' doesn'"'"'t exist on type '"'"'Issue'"'"'"}]}'

# stub_gh_related <parent-response> <blocked-response>
# Each response is printed for its query; one carrying `errors` exits 1, as gh does.
stub_gh_related() {
  printf '%s' "$1" > "$SANDBOX/parent.json"
  printf '%s' "$2" > "$SANDBOX/blocked.json"
  stub gh <<'EOF'
if [ "$1" = "api" ] && [ "$2" = "graphql" ]; then
  case "$*" in
    *blockedBy*) f="$SANDBOX/blocked.json" ;;
    *timelineItems*) f="$SANDBOX/parent.json" ;;
    *) echo "unexpected query: $*" >&2; exit 1 ;;
  esac
  cat "$f"
  case "$(cat "$f")" in *'"errors"'*) exit 1 ;; esac
  exit 0
fi
echo "unexpected gh: $*" >&2
exit 1
EOF
}

test_prints_the_related_set() {
  stub_gh_related "$PARENT_OK" "$BLOCKED_OK"
  tab="$(printf '\t')"

  run bash "$(script "$RELATED")" acme/widgets 42
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "parent${tab}#10${tab}issue${tab}OPEN${tab}Epic${tab}1/3 done" "parent"
  assert_contains "$STDOUT" "sibling${tab}#44${tab}issue${tab}OPEN${tab}Next one" "sibling"
  assert_not_contains "$STDOUT" "sibling${tab}#42" "self as sibling"
  assert_contains "$STDOUT" "mention${tab}#50${tab}pr${tab}OPEN${tab}Fix it${tab}closes" "closing PR"
  assert_contains "$STDOUT" "mention${tab}acme/other#7${tab}issue" "cross-repo mention"
  assert_contains "$STDOUT" "blocker${tab}#30${tab}issue${tab}OPEN${tab}Lands first" "blocker"
  assert_contains "$STDOUT" "dependent${tab}#60" "dependent"
  assert_not_contains "$STDOUT" "unavailable" "unavailable lines"
  assert_eq 7 "$(printf '%s\n' "$STDOUT" | wc -l | tr -d ' ')" "line count"
}

test_undefined_field_is_unavailable_not_a_failure() {
  stub_gh_related "$PARENT_OK" "$UNDEFINED"

  run bash "$(script "$RELATED")" acme/widgets 42
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "parent	#10" "parent still read"
  assert_eq "unavailable: blockedBy — Field 'blockedBy' doesn't exist on type 'Issue'" \
    "$(last_line "$STDOUT")" "unavailable line"
  assert_not_contains "$STDOUT" "blocker	" "no blockers parsed"
}

test_any_error_discards_partial_data() {
  stub_gh_related '{"data":{"repository":{"issue":{"parent":{"number":10,"title":"Epic","state":"OPEN","subIssues":{"nodes":[]}},"timelineItems":{"nodes":[]}}}},"errors":[{"type":"FORBIDDEN","message":"Resource not accessible by integration"}]}' "$BLOCKED_OK"

  run bash "$(script "$RELATED")" acme/widgets 42
  assert_eq 0 "$STATUS" "exit status"
  assert_not_contains "$STDOUT" "parent	" "parent from an errored response"
  assert_contains "$STDOUT" "unavailable: parent — Resource not accessible by integration" "unavailable"
  assert_contains "$STDOUT" "blocker	#30" "the other call still runs"
}

test_not_found_is_unavailable() {
  nf='{"data":{"repository":{"issue":null}},"errors":[{"type":"NOT_FOUND","message":"Could not resolve to an Issue with the number of 999."}]}'
  stub_gh_related "$nf" "$nf"

  run bash "$(script "$RELATED")" acme/widgets 999
  assert_eq 0 "$STATUS" "exit status"
  assert_eq "unavailable: parent — Could not resolve to an Issue with the number of 999.
unavailable: blockedBy — Could not resolve to an Issue with the number of 999." "$STDOUT" "output"
}

test_no_parent_no_relations() {
  stub_gh_related '{"data":{"repository":{"issue":{"parent":null,"timelineItems":{"nodes":[]}}}}}' \
    '{"data":{"repository":{"issue":{"blockedBy":{"nodes":[]},"blocking":{"nodes":[]}}}}}'

  run bash "$(script "$RELATED")" acme/widgets 42
  assert_eq 0 "$STATUS" "exit status"
  assert_eq "" "$STDOUT" "output"
}

test_unauthenticated_gh_is_a_clear_error() {
  stub gh <<'EOF'
echo 'gh: Requires authentication (HTTP 401)' >&2
exit 1
EOF

  run bash "$(script "$RELATED")" acme/widgets 42
  assert_eq 3 "$STATUS" "exit status"
  assert_eq 'Run `gh auth login` first.' "$STDERR" "error"
}

test_network_failure_is_unavailable() {
  stub gh <<'EOF'
echo 'error connecting to api.github.com' >&2
exit 1
EOF

  run bash "$(script "$RELATED")" acme/widgets 42
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "unavailable: parent — error connecting to api.github.com" "parent"
  assert_contains "$STDOUT" "unavailable: blockedBy — error connecting to api.github.com" "blockedBy"
}

test_usage() {
  stub_gh_related "$PARENT_OK" "$BLOCKED_OK"

  run bash "$(script "$RELATED")" 42
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "Usage" "error"
}

run_tests
