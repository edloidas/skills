#!/usr/bin/env bash
# context.sh: next-issue's Phase 1 gathering — the git side against a fixture
# repo, the gh side against a stub, and the aliased parents query.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

CONTEXT="skills/next-issue/scripts/context.sh"

# A repo on `issue-12`, branched from a `main` whose last commits reference
# #12 and #229 and touch src/world, docs, and a release.
setup_repo() {
  init_repo repo main
  cd repo
  commit "feat: world map #12" src/world/map.ts
  commit "fix: world tiles (#229)" src/world/tiles/a.ts
  commit "docs: readme" README.md
  commit "chore: release 1.2.0" package.json
  add_remote main
  git checkout --quiet -b issue-12
}

PARENTS_OK='{"data":{"repository":{"r12":{"number":12,"state":"OPEN","parent":{"number":5,"title":"Epic: world","state":"OPEN"}},"r229":{"number":229,"state":"MERGED","closingIssuesReferences":{"nodes":[{"number":11,"state":"CLOSED","parent":{"number":5,"title":"Epic: world","state":"OPEN"}},{"number":13,"state":"CLOSED","parent":null}]}},"r40":{"number":40,"state":"CLOSED","parent":null}}}}'

# stub_gh_context <graphql-response>
stub_gh_context() {
  printf '%s' "$1" > "$SANDBOX/graphql.json"
  stub gh <<'EOF'
printf '%s\n' "$*" >> "$SANDBOX/gh.calls"
case "$1 $2" in
  "api user") echo me; exit 0 ;;
  "repo view") echo "acme/widgets main"; exit 0 ;;
  "pr list") printf '77\tme\tissue-12\tmain\t12\n'; exit 0 ;;
  "issue list") printf '40\t2026-01-02T00:00:00Z\tOld thing\n'; exit 0 ;;
  "api graphql")
    cat "$SANDBOX/graphql.json"
    case "$(cat "$SANDBOX/graphql.json")" in *'"errors"'*) exit 1 ;; esac
    exit 0 ;;
esac
echo "unexpected gh: $*" >&2
exit 1
EOF
}

test_happy_path() {
  setup_repo
  stub_gh_context "$PARENTS_OK"
  tab="$(printf '\t')"

  run bash "$(script "$CONTEXT")"
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "login: me
repo: acme/widgets
default-branch: main
branch: issue-12
base-ref: origin/main
current: 12 OPEN" "header"
  assert_contains "$STDOUT" "== open-prs ==
77${tab}me${tab}issue-12${tab}main${tab}12" "open PRs"
  assert_contains "$STDOUT" "== recently-closed ==
40${tab}2026-01-02T00:00:00Z${tab}Old thing" "recently closed"
  assert_contains "$STDOUT" "feat: world map #12" "base log"
  assert_contains "$STDOUT" "== hot-paths ==
2${tab}src/world
1${tab}README.md
== refs ==" "hot paths, release commit skipped"
  assert_contains "$STDOUT" "12${tab}issue${tab}OPEN${tab}12${tab}5${tab}OPEN${tab}Epic: world" "current's parent"
  assert_contains "$STDOUT" "229${tab}pr${tab}MERGED${tab}11${tab}5${tab}OPEN${tab}Epic: world" "PR resolved to its issue"
  assert_contains "$STDOUT" "229${tab}pr${tab}MERGED${tab}13${tab}-${tab}-${tab}-" "second closing issue"
  assert_contains "$STDOUT" "40${tab}issue${tab}CLOSED${tab}40${tab}-" "recently closed resolved"
  assert_not_contains "$STDOUT" "unavailable" "unavailable lines"

  query="$(sed -n '/^api graphql/,$p' "$SANDBOX/gh.calls")"
  assert_contains "$query" "r12: issueOrPullRequest(number: 12)" "alias for current"
  assert_contains "$query" "r229: issueOrPullRequest(number: 229)" "alias for commit ref"
  assert_contains "$query" "r40: issueOrPullRequest(number: 40)" "alias for closed issue"
}

test_not_found_alias_is_dropped() {
  setup_repo
  stub_gh_context '{"data":{"repository":{"r12":{"number":12,"state":"OPEN","parent":null},"r229":null,"r40":{"number":40,"state":"CLOSED","parent":null}}},"errors":[{"type":"NOT_FOUND","path":["repository","r229"],"message":"Could not resolve to an issue or pull request with the number of 229."}]}'

  run bash "$(script "$CONTEXT")"
  assert_eq 0 "$STATUS" "exit status"
  assert_not_contains "$STDOUT" "229	" "dropped number"
  assert_contains "$STDOUT" "12	issue	OPEN	12	-" "kept number"
  assert_contains "$STDOUT" "current: 12 OPEN" "current"
  assert_not_contains "$STDOUT" "unavailable" "unavailable lines"
}

test_undefined_field_means_no_parents() {
  setup_repo
  stub_gh_context '{"errors":[{"extensions":{"code":"undefinedField"},"message":"Field '"'"'parent'"'"' doesn'"'"'t exist on type '"'"'Issue'"'"'"}]}'

  run bash "$(script "$CONTEXT")"
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "== refs ==
unavailable: parents — Field 'parent' doesn't exist on type 'Issue'" "unavailable line"
  assert_contains "$STDOUT" "current: 12 UNKNOWN" "current"
}

test_closed_current_issue() {
  setup_repo
  stub_gh_context "$(printf '%s' "$PARENTS_OK" | sed 's/"number":12,"state":"OPEN"/"number":12,"state":"CLOSED"/')"

  run bash "$(script "$CONTEXT")"
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "current: 12 CLOSED" "current"
}

test_falls_back_to_local_default_branch() {
  init_repo repo main
  cd repo
  commit "feat: one" a.txt
  git checkout --quiet -b 3-thing
  stub_gh_context '{"data":{"repository":{"r3":{"number":3,"state":"OPEN","parent":null},"r40":{"number":40,"state":"CLOSED","parent":null}}}}'

  run bash "$(script "$CONTEXT")"
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "base-ref: main" "base ref"
  assert_contains "$STDOUT" "current: 3 OPEN" "current from <N>-*"
}

test_no_base_ref_is_named() {
  init_repo repo trunk
  cd repo
  commit "feat: one" a.txt
  stub_gh_context '{"data":{"repository":{"r40":{"number":40,"state":"CLOSED","parent":null}}}}'

  run bash "$(script "$CONTEXT")"
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "base-ref: none" "base ref"
  assert_contains "$STDOUT" "unavailable: base history — neither origin/main nor main resolves" "named"
  assert_contains "$STDOUT" "current: none" "current"
}

test_type_prefixed_branch() {
  setup_repo
  git checkout --quiet -b fix/12-tiles
  stub_gh_context "$PARENTS_OK"

  run bash "$(script "$CONTEXT")"
  assert_contains "$STDOUT" "current: 12 OPEN" "current from <type>/<N>-*"
}

test_unauthenticated_gh_is_a_clear_error() {
  setup_repo
  stub gh <<'EOF'
echo 'gh: Requires authentication (HTTP 401)' >&2
exit 1
EOF

  run bash "$(script "$CONTEXT")"
  assert_eq 3 "$STATUS" "exit status"
  assert_eq "Run gh auth login first." "$STDERR" "error"
  assert_eq "" "$STDOUT" "stdout"
}

test_outside_a_github_repository() {
  stub gh <<'EOF'
case "$1 $2" in
  "api user") echo me; exit 0 ;;
esac
echo 'none of the git remotes configured for this repository point to a known GitHub host' >&2
exit 1
EOF

  run bash "$(script "$CONTEXT")"
  assert_eq 5 "$STATUS" "exit status"
  assert_eq "Not inside a GitHub repository." "$STDERR" "error"
}

test_missing_gh() {
  stub_path > /dev/null
  unstub gh

  run bash "$(script "$CONTEXT")"
  assert_eq 4 "$STATUS" "exit status"
  assert_eq "next-issue needs the gh CLI." "$STDERR" "error"
}

run_tests
