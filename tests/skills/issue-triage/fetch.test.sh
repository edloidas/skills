#!/usr/bin/env bash
# Behaviour of issue-triage's fetch.sh: scoping, reference resolution, and
# clustering issues joined by parent, cross-reference, mention or a shared upstream reference.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

FETCH="skills/issue-triage/scripts/fetch.sh"

stub_gh() {
  stub gh <<'EOF'
args="$*"
case "$args" in
  "label list"*) echo '[{"name":"Bug","description":""}]'; exit 0 ;;
  "api --paginate repos/o/r/issues/1/sub_issues"*) printf '2\n3\n'; exit 0 ;;
  "api graphql"*issueTypes*) echo '[{"name":"Task","description":""}]'; exit 0 ;;
  "api graphql"*issueOrPullRequest*)
    # Answer each alias from refs.fixture, one "owner/repo#N <json>" line per known reference.
    printf '%s' "$args" | grep -oE 'a[0-9]+: repository\(owner:"[^"]+",name:"[^"]+"\)\{issueOrPullRequest\(number:[0-9]+' \
      | sed -E 's/^(a[0-9]+): repository\(owner:"([^"]+)",name:"([^"]+)"\)\{issueOrPullRequest\(number:([0-9]+)$/\1 \2\/\3#\4/' \
      | { printf '{"data":{'; sep=""
          while read -r alias key; do
            v="$(grep -F "$key " refs.fixture 2>/dev/null | head -1 | cut -d' ' -f2-)"
            printf '%s"%s":{"issueOrPullRequest":%s}' "$sep" "$alias" "${v:-null}"; sep=","
          done; printf '}}'; }
    exit 0 ;;
  "api graphql"*) cat issues.response; exit 0 ;;
esac
echo "unexpected gh: $args" >&2
exit 1
EOF
}

# issue <number> <labels-json> <body> [parent] [cross-ref-number] [cross-ref-repo]
issue() {
  local parent="${4:-null}" xref=""
  [ "$parent" = null ] || parent="{\"number\":$parent,\"state\":\"OPEN\"}"
  [ -z "${5:-}" ] || xref="{\"source\":{\"__typename\":\"Issue\",\"number\":${5#*#},\"state\":\"OPEN\",\"repository\":{\"nameWithOwner\":\"${6:-o/r}\"}}}"
  printf '{"number":%s,"title":"T%s","body":"%s","createdAt":"2020-01-01T00:00:00Z","updatedAt":"2020-01-02T00:00:00Z","author":{"login":"a"},"assignees":{"nodes":[]},"labels":{"nodes":%s},"issueType":null,"milestone":null,"parent":%s,"subIssuesSummary":{"total":0,"completed":0},"comments":{"totalCount":0,"nodes":[]},"timelineItems":{"nodes":[%s]}}' \
    "$1" "$1" "$3" "$2" "$parent" "$xref"
}

page() {
  printf '{"data":{"repository":{"issues":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[%s]}}}}' "$1" > issues.response
}

test_resolves_mentions_and_marks_missing_numbers() {
  stub_gh
  page "$(issue 1 '[]' 'see #5 and #404, not enonic/xp#77')"
  echo 'o/r#5 {"__typename":"PullRequest","title":"Fix","state":"MERGED","merged":true,"author":{"login":"dependabot"}}' > refs.fixture
  echo 'enonic/xp#77 {"__typename":"Issue","title":"Upstream","state":"OPEN","stateReason":null,"author":{"login":"b"}}' >> refs.fixture
  run bash "$(script "$FETCH")" --repo o/r --out out
  assert_eq 0 "$STATUS" "exit: $STDERR"
  assert_eq '{"kind":"pr","title":"Fix","state":"MERGED","reason":null,"merged":true,"author":"dependabot"}' "$(jq -c '."5"' out/refs.json)" "resolved PR"
  assert_eq null "$(jq -c '."404"' out/refs.json)" "missing number"
  assert_eq false "$(jq 'has("77")' out/refs.json)" "another repository's reference is not this repo's #77"
  assert_eq '"Upstream"' "$(jq -c '."enonic/xp#77".title' out/refs.json)" "another repository's reference resolved under its own key"
  assert_eq "issues 1 refs 3 unresolved 1 foreign 1 clusters 1 similar 0" "$(last_line "$STDOUT")" "summary"
}

test_cross_reference_from_another_repository_keeps_its_repository() {
  stub_gh
  page "$(issue 1 '[]' 'body' '' 2 enonic/xp),$(issue 2 '[]' 'body')"
  echo 'enonic/xp#2 {"__typename":"Issue","title":"Upstream","state":"CLOSED","stateReason":"COMPLETED","author":{"login":"a"}}' > refs.fixture
  run bash "$(script "$FETCH")" --repo o/r --out out
  assert_eq 0 "$STATUS" "exit: $STDERR"
  assert_eq '"enonic/xp#2"' "$(jq -c '.[0].crossRefs[0].ref' out/issues.json)" "keyed with its repository"
  assert_eq '"Upstream"' "$(jq -c '."enonic/xp#2".title' out/refs.json)" "resolved into refs.json"
  assert_eq "c1	1
c2	2" "$(cat out/clusters.tsv)" "not joined to this repository's #2"
}

test_reads_issue_and_pull_request_urls() {
  stub_gh
  page "$(issue 1 '[]' 'as in https://github.com/O/R/issues/9 and https://github.com/x/y/pull/3#discussion')"
  echo 'o/r#9 {"__typename":"Issue","title":"Nine","state":"CLOSED","stateReason":"COMPLETED","author":{"login":"a"}}' > refs.fixture
  run bash "$(script "$FETCH")" --repo o/r --out out
  assert_eq 0 "$STATUS" "exit: $STDERR"
  assert_eq '9 x/y#3' "$(jq -r 'keys | join(" ")' out/refs.json)" "a URL to this repository is keyed by number, case-insensitively"
  assert_eq '"COMPLETED"' "$(jq -c '."9".reason' out/refs.json)" "close reason"
}

test_clusters_follow_parent_cross_reference_and_mention() {
  stub_gh
  page "$(issue 1 '[]' 'epic'),$(issue 2 '[]' 'child' 1),$(issue 3 '[]' 'x' '' 2),$(issue 4 '[]' 'relates to #1'),$(issue 5 '[]' 'alone'),$(issue 6 '[]' 'see https://github.com/o/r/issues/5'),$(issue 7 '[]' 'upstream x/y#3'),$(issue 8 '[]' 'also x/y#3')"
  run bash "$(script "$FETCH")" --repo o/r --out out
  assert_eq 0 "$STATUS" "exit: $STDERR"
  assert_eq "c1	1 2 3 4
c2	5 6
c3	7 8" "$(cat out/clusters.tsv)" "clusters"
}

test_pairs_issues_whose_titles_share_most_words() {
  stub_gh
  page "$(issue 1 '[]' 'a'),$(issue 2 '[]' 'b'),$(issue 3 '[]' 'c')"
  jq '.data.repository.issues.nodes[0].title = "Browse panel is not refreshed after moving content"
      | .data.repository.issues.nodes[1].title = "Browse panel not refreshed after updating content"
      | .data.repository.issues.nodes[2].title = "Add a schedule button to the publish dialog"' issues.response > p.json && mv p.json issues.response
  run bash "$(script "$FETCH")" --repo o/r --out out
  assert_eq 0 "$STATUS" "exit: $STDERR"
  assert_eq "1	2	66" "$(cat out/similar.tsv)" "one candidate pair, unrelated title left out"
  assert_eq false "$(grep -q '^c1	1 2$' out/clusters.tsv && echo true || echo false)" "a similar title is a hint, not a cluster edge"
}

test_label_and_number_scope() {
  stub_gh
  page "$(issue 1 '[{"name":"Bug"}]' 'a'),$(issue 2 '[]' 'b'),$(issue 3 '[{"name":"Bug"}]' 'c')"
  run bash "$(script "$FETCH")" --repo o/r --out out --label Bug
  assert_eq "1 3" "$(jq -r '[.[].number] | join(" ")' out/issues.json)" "label scope"
  run bash "$(script "$FETCH")" --repo o/r --out out --numbers 2,3
  assert_eq "2 3" "$(jq -r '[.[].number] | join(" ")' out/issues.json)" "number scope"
  run bash "$(script "$FETCH")" --repo o/r --out out --epic 1
  assert_eq "1 2 3" "$(jq -r '[.[].number] | join(" ")' out/issues.json)" "the epic and its sub-issues"
}

test_refuses_bad_arguments() {
  stub_gh
  run bash "$(script "$FETCH")" --out out
  assert_eq 2 "$STATUS" "no repo"
  run bash "$(script "$FETCH")" --repo o/r --out out --older-than soon
  assert_eq 2 "$STATUS" "non-numeric age"
}

run_tests
