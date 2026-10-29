#!/usr/bin/env bash
# sync-labels.sh — diffs a label definition against the repo and applies it.
# `gh` is stubbed: `label list` serves current.json, every other call is
# recorded, so a case asserts on exactly which writes the script would make.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

SYNC="maintain/skills/labels-sync/scripts/sync-labels.sh"

setup() {
  stub gh <<EOF
if [ "\$1" = "auth" ] && [ "\$2" = "status" ]; then
  [ -f "$SANDBOX/logged-out" ] && exit 1
  exit 0
fi
if [ "\$1" = "label" ] && [ "\$2" = "list" ]; then
  cat "$SANDBOX/current.json"
  exit 0
fi
printf '%s\n' "\$*" >> "$SANDBOX/gh.calls"
exit 0
EOF
  cat > current.json <<'EOF'
[
  {"name": "bug", "description": "Something isn't working", "color": "d73a4a"},
  {"name": "Documentation", "description": "Docs", "color": "0075CA"},
  {"name": "question", "description": "Further information is requested", "color": "d876e3"},
  {"name": "wontfix", "description": "This will not be worked on", "color": "ffffff"}
]
EOF
  cat > defined.json <<'EOF'
[
  {"name": "bug", "description": "Something isn't working", "color": "B60205"},
  {"name": "docs", "description": "Docs", "color": "0075CA"},
  {"name": "question", "description": "Further information is requested", "color": "D876E3"},
  {"name": "feature", "description": "New functionality", "color": "1D76DB"}
]
EOF
}

sync() {
  run bash "$(script "$SYNC")" "$@" < defined.json
}

field() {
  printf '%s' "$STDOUT" | jq -c "$1"
}

test_dry_run_reports_each_bucket_and_writes_nothing() {
  sync
  assert_eq 0 "$STATUS" "exit status"
  assert_eq '["docs","feature"]' "$(field '[.create[].name] | sort')" "create"
  assert_eq '["bug"]' "$(field '[.update[].name]')" "update"
  assert_eq '[{"field":"color","from":"d73a4a","to":"b60205"}]' "$(field '.update[0].changes')" "bug changes"
  assert_eq '["Documentation","wontfix"]' "$(field '[.delete[].name] | sort')" "delete"
  assert_eq '[]' "$(field '.kept')" "kept"
  assert_eq '["question"]' "$(field '.unchanged')" "unchanged"
  assert_eq "" "$(calls_of gh)" "gh writes"
}

test_name_case_difference_is_an_update_not_a_delete() {
  printf '[{"name":"Bug","description":"Something isn'"'"'t working","color":"d73a4a"}]\n' > current.json
  sync
  assert_eq '[]' "$(field '.delete')" "delete"
  assert_eq '[{"field":"name","from":"Bug","to":"bug"},{"field":"color","from":"d73a4a","to":"b60205"}]' \
    "$(field '.update[0].changes')" "changes"
}

test_no_delete_moves_extras_to_kept_in_the_plan() {
  sync --no-delete
  assert_eq 0 "$STATUS" "exit status"
  assert_eq '[]' "$(field '.delete')" "delete"
  assert_eq '["Documentation","wontfix"]' "$(field '[.kept[].name] | sort')" "kept"
}

test_apply_deletes_only_labels_absent_from_the_set() {
  sync --apply
  assert_eq 0 "$STATUS" "exit status"
  local deletes
  deletes="$(calls_of gh | grep '^label delete' | sort)"
  assert_eq "label delete Documentation --yes
label delete wontfix --yes" "$deletes" "delete calls"
  assert_contains "$(calls_of gh)" "label create feature --description New functionality --color 1D76DB --force"
  assert_contains "$(calls_of gh)" "label edit bug --description Something isn't working --color b60205"
  assert_contains "$STDERR" "Created 2, updated 1, deleted 2"
}

test_apply_no_delete_makes_no_delete_call() {
  sync --apply --no-delete
  assert_eq 0 "$STATUS" "exit status"
  assert_not_contains "$(calls_of gh)" "label delete" "gh calls"
  assert_contains "$(calls_of gh)" "label create feature"
  assert_contains "$STDERR" "Created 2, updated 1, deleted 0, kept 2"
}

test_failed_write_stops_before_deletes() {
  stub gh <<EOF
if [ "\$1" = "label" ] && [ "\$2" = "list" ]; then cat "$SANDBOX/current.json"; exit 0; fi
printf '%s\n' "\$*" >> "$SANDBOX/gh.calls"
if [ "\$2" = "edit" ]; then echo "HTTP 403: forbidden" >&2; exit 1; fi
exit 0
EOF
  sync --apply
  assert_ne 0 "$STATUS" "exit status"
  assert_contains "$STDERR" "HTTP 403: forbidden"
  assert_not_contains "$(calls_of gh)" "label delete" "gh calls"
}

test_get_exports_reusable_shape() {
  run bash "$(script "$SYNC")" --get
  assert_eq 0 "$STATUS" "exit status"
  assert_eq '{"name":"bug","description":"Something isn'"'"'t working","color":"D73A4A"}' "$(field '.[0]')" "first label"
}

test_get_rejects_no_delete() {
  run bash "$(script "$SYNC")" --get --no-delete
  assert_eq 1 "$STATUS" "exit status"
}

test_missing_jq_is_named_before_any_gh_call() {
  unstub jq
  sync
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "jq is required but not installed" "stderr"
  assert_eq "" "$(calls_of gh)" "gh calls"
}

test_missing_gh_is_named() {
  unstub gh
  sync
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "gh (GitHub CLI) is required" "stderr"
}

test_unauthenticated_gh_stops_before_reading_labels() {
  touch "$SANDBOX/logged-out"
  sync --apply
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "gh is not authenticated" "stderr"
  assert_eq "" "$STDOUT" "stdout"
  assert_eq "" "$(calls_of gh)" "gh writes"
}

test_non_array_input_is_rejected() {
  echo '{"name":"bug"}' > defined.json
  sync
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "Invalid JSON input"
}

run_tests
