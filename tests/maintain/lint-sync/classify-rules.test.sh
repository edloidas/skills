#!/usr/bin/env bash
# classify-rules.sh — joins active ESLint rules against a Biome or Oxc mapping.
# The cases pin the bucket rules and the lookup order against small fixture
# references, so a mapping refresh cannot change what they assert.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

CLASSIFY="maintain/skills/lint-sync/scripts/classify-rules.sh"

classify() {
  run bash "$(script "$CLASSIFY")" "$@" --refs refs
}

setup() {
  mkdir -p refs
  cat > refs/biome-eslint-mapping.json <<'EOF'
{"_meta":{"biomeVersion":"2.4","updatedAt":"2026-04-01"},"rules":{
 "no-debugger":{"biome":"suspicious/noDebugger","relationship":"same"},
 "@typescript-eslint/naming-convention":{"biome":"style/useNamingConvention","relationship":"inspired"},
 "eslint-plugin-react/jsx-key":{"biome":"correctness/useJsxKeyInIterable","relationship":"same"},
 "@next/no-img-element":{"biome":"performance/noImgElement","relationship":"same"},
 "curly":{"biome":"style/useBlockStatements","relationship":"same"}}}
EOF
  cat > refs/oxc-eslint-mapping.json <<'EOF'
{"_meta":{"oxlintVersion":"1.x","updatedAt":"2026-04-01"},"rules":{
 "no-debugger":{"oxlint":"eslint/no-debugger","relationship":"same"},
 "@typescript-eslint/await-thenable":{"oxlint":"typescript/await-thenable","relationship":"same","typeAware":true},
 "eslint-plugin-import/no-cycle":{"oxlint":"import/no-cycle","relationship":"same"}}}
EOF
  printf '{"_meta":{},"rules":["no-floating-promises","dot-notation"]}\n' > refs/type-aware-rules.json
}

eslint_rules() {
  printf '{"rules":[' > eslint.json
  local first=1 r
  for r in "$@"; do
    [ "$first" = 1 ] || printf ',' >> eslint.json
    printf '{"name":"%s","severity":"error","options":[]}' "$r" >> eslint.json
    first=0
  done
  printf ']}\n' >> eslint.json
}

active_rules() {
  printf '{"rules":[' > active.json
  local first=1 r
  for r in "$@"; do
    [ "$first" = 1 ] || printf ',' >> active.json
    printf '"%s"' "$r" >> active.json
    first=0
  done
  printf ']}\n' >> active.json
}

bucket_of() {
  printf '%s' "$STDOUT" | jq -r --arg r "$1" \
    '[("DISABLE","REVIEW","ENABLE_TARGET","ESLINT_ONLY","TYPE_AWARE") as $b | select(any(.[$b][]; .eslint == $r)) | $b] | join(",")'
}

# ------------------------------------------------------------------ biome --

test_biome_active_same_rule_is_disable() {
  eslint_rules no-debugger
  active_rules suspicious/noDebugger
  classify biome eslint.json active.json
  assert_eq 0 "$STATUS" "exit status"
  assert_eq DISABLE "$(bucket_of no-debugger)" "bucket"
}

# A rule promoted out of nursery keeps its name and changes category, so Biome
# matches by rule name only.
test_biome_matches_by_rule_name_not_category() {
  eslint_rules no-debugger
  active_rules nursery/noDebugger
  classify biome eslint.json active.json
  assert_eq DISABLE "$(bucket_of no-debugger)" "bucket"
}

test_biome_active_inspired_rule_is_review() {
  eslint_rules @typescript-eslint/naming-convention
  active_rules style/useNamingConvention
  classify biome eslint.json active.json
  assert_eq REVIEW "$(bucket_of @typescript-eslint/naming-convention)" "bucket"
}

test_mapped_but_inactive_rule_is_enable_target() {
  eslint_rules curly
  active_rules suspicious/noDebugger
  classify biome eslint.json active.json
  assert_eq ENABLE_TARGET "$(bucket_of curly)" "bucket"
}

test_plugin_rule_resolves_through_eslint_plugin_prefix() {
  eslint_rules react/jsx-key
  active_rules correctness/useJsxKeyInIterable
  classify biome eslint.json active.json
  assert_eq DISABLE "$(bucket_of react/jsx-key)" "bucket"
}

test_scoped_plugin_rule_collapses_to_scope_and_rule() {
  eslint_rules @next/next/no-img-element
  active_rules performance/noImgElement
  classify biome eslint.json active.json
  assert_eq DISABLE "$(bucket_of @next/next/no-img-element)" "bucket"
}

# Only the typescript-eslint copy is type-aware; core dot-notation is not.
test_unmapped_typescript_type_aware_rule_is_type_aware() {
  eslint_rules @typescript-eslint/no-floating-promises dot-notation my/custom
  active_rules
  classify biome eslint.json active.json
  assert_eq TYPE_AWARE "$(bucket_of @typescript-eslint/no-floating-promises)" "ts bucket"
  assert_eq ESLINT_ONLY "$(bucket_of dot-notation)" "core bucket"
  assert_eq ESLINT_ONLY "$(bucket_of my/custom)" "custom bucket"
}

test_summary_line_carries_every_count() {
  eslint_rules no-debugger curly my/custom
  active_rules suspicious/noDebugger
  classify biome eslint.json active.json
  assert_eq "3 active ESLint rules -> 1 DISABLE, 0 REVIEW, 1 ENABLE_TARGET, 1 ESLINT_ONLY, 0 TYPE_AWARE" \
    "$(printf '%s' "$STDOUT" | jq -r .summary)" "summary"
  assert_eq "2.4" "$(printf '%s' "$STDOUT" | jq -r .mapping.version)" "mapping version"
}

# -------------------------------------------------------------------- oxc --

test_oxc_matches_full_name_with_optional_eslint_prefix() {
  eslint_rules no-debugger import/no-cycle
  active_rules no-debugger import/no-cycle
  classify oxc eslint.json active.json
  assert_eq DISABLE "$(bucket_of no-debugger)" "core bucket"
  assert_eq DISABLE "$(bucket_of import/no-cycle)" "plugin bucket"
}

test_oxc_carries_type_aware_flag_on_mapped_rules() {
  eslint_rules @typescript-eslint/await-thenable
  active_rules
  classify oxc eslint.json active.json
  assert_eq ENABLE_TARGET "$(bucket_of @typescript-eslint/await-thenable)" "bucket"
  assert_eq true "$(printf '%s' "$STDOUT" | jq -r '.ENABLE_TARGET[0].typeAware')" "typeAware"
}

# ---------------------------------------------------------------- refusals --

test_unknown_target_exits_2() {
  eslint_rules no-debugger
  active_rules
  classify eslint eslint.json active.json
  assert_eq 2 "$STATUS" "exit status"
  assert_contains "$STDERR" "Usage" "error output"
}

test_missing_input_file_exits_1() {
  active_rules
  classify biome missing.json active.json
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "file not found: missing.json" "error output"
}

run_tests
