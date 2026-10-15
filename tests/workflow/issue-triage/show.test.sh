#!/usr/bin/env bash
# Behaviour of issue-triage's show.sh: offline print from the run directory, gh for a longer
# thread or an issue outside it, and references resolved through refs.json.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

SHOW="workflow/skills/issue-triage/scripts/show.sh"

stub_gh() {
  stub gh <<'EOF'
echo "$*" >> gh.calls
case "$*" in
  "issue view 9 "*) printf '%s' '{"number":9,"title":"Closed one","state":"CLOSED","reason":"COMPLETED","body":"old","createdAt":"2019-01-01T00:00:00Z","updatedAt":"2019-02-01T00:00:00Z","author":"x","labels":[],"assignees":[],"milestone":null,"comments":[{"author":"m","role":"MEMBER","createdAt":"2019-01-05T00:00:00Z","body":"Won'"'"'t do"}]}'; exit 0 ;;
esac
exit 1
EOF
}

run_dir() {
  mkdir -p run
  echo '{"repo":"o/r","labels":[],"types":[]}' > run/context.json
  echo '{"9":{"kind":"issue","title":"Closed one","state":"CLOSED","reason":"COMPLETED","merged":null,"author":"x"},"x/y#3":null}' > run/refs.json
  echo '{"1":{"type":"Bug","owner":"m","flags":["stale"]}}' > run/lint.json
  jq -n '[{number: 1, title: "Broken", body: "see #9", createdAt: "2020-01-01T00:00:00Z", updatedAt: "2020-02-01T00:00:00Z",
           author: "a", authorRole: "NONE", assignees: [], labels: ["Bug"], type: null, milestone: null, parent: null,
           comments: {total: 1, last: [{author: "m", role: "MEMBER", createdAt: "2020-01-02T00:00:00Z", body: "confirmed"}]},
           refs: ["9", "x/y#3"]},
          {number: 2, title: "Long", body: "b", createdAt: "2020-01-01T00:00:00Z", updatedAt: "2020-02-01T00:00:00Z",
           author: "a", assignees: [], labels: [], type: null, milestone: null, parent: null,
           comments: {total: 9, last: []}, refs: []}]' > run/issues.json
}

test_prints_an_issue_offline_with_lint_comments_and_references() {
  stub_gh; run_dir
  run bash "$(script "$SHOW")" run 1
  assert_eq 0 "$STATUS" "exit: $STDERR"
  assert_contains "$STDOUT" "#### #1 Broken"
  assert_contains "$STDOUT" "lint: type Bug · owner m · stale"
  assert_contains "$STDOUT" "-- m (member), 2020-01-02:"
  assert_contains "$STDOUT" "  9: issue closed (completed) — Closed one — @x"
  assert_contains "$STDOUT" "  x/y#3: does not exist or cannot be read"
  assert_no_file gh.calls
}

test_reads_a_longer_thread_or_an_outside_issue_with_gh() {
  stub_gh; run_dir
  run bash "$(script "$SHOW")" run 9
  assert_eq 0 "$STATUS" "exit: $STDERR"
  assert_contains "$STDOUT" "state CLOSED (completed)"
  assert_contains "$STDOUT" "Won't do"
  run bash "$(script "$SHOW")" run 2
  assert_eq 1 "$STATUS" "a thread longer than the fetch goes to gh, which fails here"
  assert_contains "$(cat gh.calls)" "issue view 2 -R o/r"
}

test_refuses_bad_arguments() {
  stub_gh; run_dir
  run bash "$(script "$SHOW")" run
  assert_eq 2 "$STATUS" "no number"
  run bash "$(script "$SHOW")" run abc
  assert_eq 2 "$STATUS" "not a number"
}

run_tests
