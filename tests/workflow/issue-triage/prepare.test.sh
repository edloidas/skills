#!/usr/bin/env bash
# Behaviour of issue-triage's prepare.sh: themes from clusters and similar pairs, the metadata
# lint, and a manifest assembled from decisions and lint.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

PREPARE="workflow/skills/issue-triage/scripts/prepare.sh"

# issue <number> [labels-json] [type] [updatedAt] [parent] [parentState] [refs-json] [subtotal] [subdone]
issue() {
  jq -n --argjson n "$1" --argjson l "${2:-[]}" --arg t "${3:-}" --arg u "${4:-2026-10-01T00:00:00Z}" \
        --arg p "${5:-}" --arg ps "${6:-}" --argjson r "${7:-[]}" --argjson st "${8:-0}" --argjson sd "${9:-0}" \
    '{number: $n, title: "T\($n)", body: "", updatedAt: $u, labels: $l, type: (if $t == "" then null else $t end),
      parent: (if $p == "" then null else ($p | tonumber) end), parentState: (if $ps == "" then null else $ps end),
      subIssues: {total: $st, completed: $sd}, comments: {total: 0, last: []}, crossRefs: [], refs: $r}'
}

run_dir() {
  mkdir -p run
  jq -s . > run/issues.json
  echo '{"repo":"o/r","labels":[],"types":[{"name":"Bug"},{"name":"Task"},{"name":"Feature"}]}' > run/context.json
  echo '{"9":null,"8":{"kind":"issue"}}' > run/refs.json
}

test_themes_keep_clusters_and_similar_pairs_together() {
  { for n in 1 2 3 4 5 6; do issue $n; done; } | run_dir
  printf 'c1\t1 2\nc2\t3\nc3\t4\nc4\t5\nc5\t6\n' > run/clusters.tsv
  printf '3\t6\t50\n' > run/similar.tsv
  run bash "$(script "$PREPARE")" themes run --max 3
  assert_eq 0 "$STATUS" "exit: $STDERR"
  assert_eq "t1	1 2
t2	3 6 4
t3	5" "$(cat run/themes.tsv)" "a cluster and a similar pair are never split; themes fill to --max"
}

test_oversized_group_splits_by_parent() {
  { issue 1; issue 2 '[]' '' '' 1; issue 3 '[]' '' '' 1; issue 4 '[]' '' '' 9; issue 5 '[]' '' '' 9; } | run_dir
  printf 'c1\t1 2 3 4 5\n' > run/clusters.tsv
  run bash "$(script "$PREPARE")" themes run --max 3
  assert_eq 0 "$STATUS" "exit: $STDERR"
  assert_eq "t1	1 2 3
t2	4 5" "$(cat run/themes.tsv)" "the epic with its children, then the other family"
}

test_lint_derives_type_and_flags() {
  { issue 1 '["Bug"]'
    issue 2 '["Improvement"]'
    issue 3 '["Bug","Improvement"]'
    issue 4 '[]' '' '2020-01-01T00:00:00Z'
    issue 5 '["Bug"]' 'Bug' '' 7 CLOSED '["9","8"]' 3 3; } | run_dir
  run bash "$(script "$PREPARE")" lint run --type-map "Improvement=Feature"
  assert_eq 0 "$STATUS" "exit: $STDERR"
  assert_eq '"Bug"' "$(jq -c '."1".type' run/lint.json)" "a label named like a type"
  assert_eq '"Feature"' "$(jq -c '."2".type' run/lint.json)" "a mapped label"
  assert_eq '[null,["type-conflict Bug,Feature"]]' "$(jq -c '."3" | [.type, .flags]' run/lint.json)" "two types named: no guess"
  assert_eq '["no-type","stale"]' "$(jq -c '."4".flags' run/lint.json)" "no type and not updated in a year"
  assert_eq '[null,["dead-ref 9","parent-closed #7","subissues-done 3"]]' "$(jq -c '."5" | [.type, .flags]' run/lint.json)" "type already right; reference, parent and sub-issue flags"
}

test_lint_names_the_owner_an_ask_goes_to() {
  { issue 1 | jq '.assignees = ["as"] | .author = "m" | .authorRole = "MEMBER"'
    issue 2 | jq '.author = "m" | .authorRole = "MEMBER"'
    issue 3 | jq '.author = "ext" | .authorRole = "NONE" | .comments.last = [{author: "c1", role: "COLLABORATOR"}, {author: "c2", role: "NONE"}]'
    issue 4 | jq '.author = "ext" | .authorRole = "CONTRIBUTOR"'; } | run_dir
  run bash "$(script "$PREPARE")" lint run
  assert_eq 0 "$STATUS" "exit: $STDERR"
  assert_eq '["as","m","c1",null]' "$(jq -c '[."1".owner, ."2".owner, ."3".owner, ."4".owner]' run/lint.json)" \
    "assignee, then a maintainer author, then the last maintainer who commented, else none"
}

test_manifest_maps_verdicts_and_lint() {
  { issue 1 '["Bug"]'; issue 2; issue 3; issue 4; } | run_dir
  echo '{"1":{"type":"Bug","flags":[]},"2":{"type":null,"flags":[]},"3":{"type":null,"flags":[]},"4":{"type":"Task","flags":[]}}' > run/lint.json
  cat > run/decisions.json <<'EOF'
[{"number": 2, "verdict": "CLOSE-DUPLICATE", "duplicate_of": 1, "type": "Task"},
 {"number": 3, "verdict": "STALE-ASK", "note": true, "labels": {"add": ["On hold"]}},
 {"number": 4, "verdict": "CLOSE-OBSOLETE", "status": "Archive", "skip": true}]
EOF
  echo '[{"key":"k","title":"New","body_file":"texts/new-k.md"}]' > run/new_issues.json
  run bash "$(script "$PREPARE")" manifest run --marker m1 --project o/7 --closed-status Done --status BACKLOG=Backlog --status CLOSE=Done
  assert_eq 0 "$STATUS" "exit: $STDERR"
  assert_eq "manifest rows 4 closes 2" "$(last_line "$STDOUT")" "summary"
  assert_eq '{"number":1,"type":"Bug"}' "$(jq -c '.issues[0]' run/manifest.json)" "lint type on a row without a decision"
  assert_eq '{"number":2,"type":"Task","status":"Done","comment_file":"texts/2.close.md","state":"closed","reason":"duplicate","duplicate_of":1}' \
    "$(jq -c '.issues[1]' run/manifest.json)" "duplicate close"
  assert_eq '{"number":3,"labels":{"add":["On hold"]},"body":{"mode":"prepend","file":"texts/3.note.md"},"comment_file":"texts/3.ask.md"}' \
    "$(jq -c '.issues[2]' run/manifest.json)" "owner question with a note"
  assert_eq '["Task","not_planned","Archive",true]' "$(jq -c '.issues[3] | [.type, .reason, .status, .skip]' run/manifest.json)" "obsolete closes as not planned; a row's own status and skip win"
  assert_eq '"New"' "$(jq -c '.new_issues[0].title' run/manifest.json)" "new issues copied in"
  assert_eq '{"owner":"o","number":7,"status_field":"Status","closed_status":"Done"}' "$(jq -c '.project' run/manifest.json)" "project block"
  assert_eq '"o/r"' "$(jq -c '.repo' run/manifest.json)" "repo"
}

test_security_close_needs_the_users_confirmation() {
  { issue 1 '["Security"]'; issue 2; issue 3; } | run_dir
  echo '{}' > run/lint.json
  echo '[{"number":1,"verdict":"CLOSE-NOT-PLANNED"},{"number":2,"verdict":"CLOSE-DUPLICATE","duplicate_of":3,"security":true},{"number":3,"verdict":"CLOSE-DONE","security":true}]' > run/decisions.json
  run bash "$(script "$PREPARE")" manifest run --marker m
  assert_eq 2 "$STATUS" "refused"
  assert_contains "$STDERR" "#1 #2"
  assert_no_file run/manifest.json
  echo '[{"number":1,"verdict":"CLOSE-NOT-PLANNED","confirmed":true},{"number":2,"verdict":"CLOSE-DUPLICATE","duplicate_of":3,"security":true,"confirmed":true},{"number":3,"verdict":"CLOSE-DONE","security":true}]' > run/decisions.json
  run bash "$(script "$PREPARE")" manifest run --marker m
  assert_eq 0 "$STATUS" "confirmed at the gate: $STDERR"
}

test_claims_lists_close_and_security_claims_with_cited_issues() {
  { issue 1; issue 2; issue 3; } | run_dir
  echo '[{"number":1,"verdict":"CLOSE-DONE","claims":["fixed in #40 (a.ts:3)","no caller of b()"]},{"number":2,"verdict":"KEEP","security":true,"claims":["token checked on start only"]},{"number":3,"verdict":"KEEP","claims":["ignored"]}]' > run/decisions.json
  run bash "$(script "$PREPARE")" claims run
  assert_eq 0 "$STATUS" "exit: $STDERR"
  assert_eq "1. [#1 CLOSE-DONE] fixed in #40 (a.ts:3)
2. [#1 CLOSE-DONE] no caller of b()
3. [#2 KEEP] token checked on start only

Cited issues: 1 2 40" "$(cat run/claims.md)" "numbered claims; a plain keep is left out"
  echo '[{"number":1,"verdict":"CLOSE-OBSOLETE"}]' > run/decisions.json
  run bash "$(script "$PREPARE")" claims run
  assert_eq 2 "$STATUS" "a close without claims"
  assert_contains "$STDERR" "#1"
}

test_refuses_bad_arguments() {
  issue 1 | run_dir
  run bash "$(script "$PREPARE")" themes run
  assert_eq 2 "$STATUS" "themes without clusters.tsv"
  run bash "$(script "$PREPARE")" lint run --stale-days soon
  assert_eq 2 "$STATUS" "non-numeric days"
  echo '{}' > run/lint.json
  run bash "$(script "$PREPARE")" manifest run
  assert_eq 2 "$STATUS" "no marker"
  run bash "$(script "$PREPARE")" manifest run --marker m --project nope
  assert_eq 2 "$STATUS" "bad project"
}

run_tests
