#!/usr/bin/env bash
# Behaviour of issue-triage's fetch.sh: scoping, reference resolution, and
# clustering issues joined by parent, cross-reference or mention.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

FETCH="workflow/skills/issue-triage/scripts/fetch.sh"

stub_gh() {
  stub gh <<'EOF'
args="$*"
case "$args" in
  "label list"*) echo '[{"name":"Bug","description":""}]'; exit 0 ;;
  "api graphql"*issueTypes*) echo '[{"name":"Task","description":""}]'; exit 0 ;;
  "api graphql"*issueOrPullRequest*) cat refs.response; exit 0 ;;
  "api graphql"*) cat issues.response; exit 0 ;;
esac
echo "unexpected gh: $args" >&2
exit 1
EOF
}

# issue <number> <labels-json> <body> [parent] [cross-ref-number]
issue() {
  local parent="${4:-null}" xref=""
  [ "$parent" = null ] || parent="{\"number\":$parent,\"state\":\"OPEN\"}"
  [ -z "${5:-}" ] || xref="{\"source\":{\"__typename\":\"Issue\",\"number\":$5,\"state\":\"OPEN\"}}"
  printf '{"number":%s,"title":"T%s","body":"%s","createdAt":"2020-01-01T00:00:00Z","updatedAt":"2020-01-02T00:00:00Z","author":{"login":"a"},"assignees":{"nodes":[]},"labels":{"nodes":%s},"issueType":null,"milestone":null,"parent":%s,"subIssuesSummary":{"total":0,"completed":0},"comments":{"totalCount":0,"nodes":[]},"timelineItems":{"nodes":[%s]}}' \
    "$1" "$1" "$3" "$2" "$parent" "$xref"
}

page() {
  printf '{"data":{"repository":{"issues":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[%s]}}}}' "$1" > issues.response
}

test_resolves_mentions_and_marks_missing_numbers() {
  stub_gh
  page "$(issue 1 '[]' 'see #5 and #404, not enonic/xp#77')"
  echo '{"data":{"repository":{"n5":{"__typename":"PullRequest","title":"Fix","state":"MERGED","merged":true,"author":{"login":"dependabot"}},"n404":null}}}' > refs.response
  run bash "$(script "$FETCH")" --repo o/r --out out
  assert_eq 0 "$STATUS" "exit: $STDERR"
  assert_eq '{"kind":"pr","title":"Fix","state":"MERGED","reason":null,"merged":true,"author":"dependabot"}' "$(jq -c '."5"' out/refs.json)" "resolved PR"
  assert_eq null "$(jq -c '."404"' out/refs.json)" "missing number"
  assert_eq false "$(jq 'has("77")' out/refs.json)" "another repository's reference is not this repo's #77"
  assert_eq "issues 1 refs 2 unresolved 1 clusters 1" "$(last_line "$STDOUT")" "summary"
}

test_clusters_follow_parent_cross_reference_and_mention() {
  stub_gh
  page "$(issue 1 '[]' 'epic'),$(issue 2 '[]' 'child' 1),$(issue 3 '[]' 'x' '' 2),$(issue 4 '[]' 'relates to #1'),$(issue 5 '[]' 'alone')"
  echo '{"data":{"repository":{}}}' > refs.response
  run bash "$(script "$FETCH")" --repo o/r --out out
  assert_eq 0 "$STATUS" "exit: $STDERR"
  assert_eq "c1	1 2 3 4
c2	5" "$(cat out/clusters.tsv)" "clusters"
}

test_label_and_number_scope() {
  stub_gh
  page "$(issue 1 '[{"name":"Bug"}]' 'a'),$(issue 2 '[]' 'b'),$(issue 3 '[{"name":"Bug"}]' 'c')"
  echo '{"data":{"repository":{}}}' > refs.response
  run bash "$(script "$FETCH")" --repo o/r --out out --label Bug
  assert_eq "1 3" "$(jq -r '[.[].number] | join(" ")' out/issues.json)" "label scope"
  run bash "$(script "$FETCH")" --repo o/r --out out --numbers 2,3
  assert_eq "2 3" "$(jq -r '[.[].number] | join(" ")' out/issues.json)" "number scope"
}

test_refuses_bad_arguments() {
  stub_gh
  run bash "$(script "$FETCH")" --out out
  assert_eq 2 "$STATUS" "no repo"
  run bash "$(script "$FETCH")" --repo o/r --out out --older-than soon
  assert_eq 2 "$STATUS" "non-numeric age"
}

run_tests
