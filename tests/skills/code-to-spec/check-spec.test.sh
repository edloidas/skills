#!/usr/bin/env bash
# check-spec.sh — mechanical checks on a code-to-spec output tree. Every case
# builds a one-module spec over a tiny repository and breaks one thing.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

RUN="skills/code-to-spec/scripts/check-spec.sh"

# repo/src/auth/lock.ts has 30 lines, repo/test/auth/lock.test.ts has 20.
setup() {
  mkdir -p repo/src/auth repo/test/auth spec/modules spec/acceptance
  seq 1 30 > repo/src/auth/lock.ts
  seq 1 20 > repo/test/auth/lock.test.ts
  cat > spec/modules/auth.md <<'EOF'
# Module: auth

## 10. Obligations

### OB-auth-001 · rule · observed
The fifth failed attempt locks the account.
- Evidence: `src/auth/lock.ts:10-20`
- Cases: positive, negative

### OB-auth-002 · timing · inferred
The lockout window slides.
- Evidence: `src/auth/lock.ts:25`
- Basis: attempts are read by timestamp at `src/auth/lock.ts:22`
- Cases: edge
- Depends on: OB-auth-001
EOF
  cat > spec/acceptance/auth.md <<'EOF'
# Acceptance: auth

## OB-auth-001

### AC-auth-001-a · OB-auth-001 · positive
- Then: `423`
- Source: test — `test/auth/lock.test.ts:5-12`

### AC-auth-001-b · OB-auth-001 · negative
- Then: `401`
- Source: code — `src/auth/lock.ts:14`

## OB-auth-002

### AC-auth-002-a · OB-auth-002 · edge
- Then: unlocked after 15 minutes
- Source: code — `src/auth/lock.ts:25`
EOF
}

check() {
  run bash "$(script "$RUN")" spec repo
}

test_clean_spec_passes() {
  check
  assert_eq 0 "$STATUS" "exit status"
  assert_eq "check-spec: 2 obligations, 3 cases, 6 citations, 0 problems." "$(last_line "$STDOUT")" "summary"
}

test_listed_case_kind_without_a_case_fails() {
  sed -i.bak 's/^- Cases: edge$/- Cases: edge, malformed/' spec/modules/auth.md
  check
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "OB-auth-002 lists malformed but no acceptance case covers it" "output"
}

test_case_for_an_unknown_obligation_fails() {
  printf '\n### AC-auth-009-a · OB-auth-009 · positive\n- Source: code — `src/auth/lock.ts:1`\n' >> spec/acceptance/auth.md
  check
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "case for unknown obligation OB-auth-009" "output"
}

test_dangling_dependency_fails() {
  sed -i.bak 's/^- Depends on: OB-auth-001$/- Depends on: OB-auth-001, OB-x-004/' spec/modules/auth.md
  check
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "OB-auth-002 depends on unknown obligation OB-x-004" "output"
}

test_malformed_obligation_heading_fails() {
  sed -i.bak 's/^### OB-auth-001 · rule · observed$/### OB-auth-001 · rule · likely/' spec/modules/auth.md
  check
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "modules/auth.md:5: malformed obligation heading" "output"
}

test_inferred_without_basis_fails() {
  sed -i.bak '/^- Basis:/d' spec/modules/auth.md
  check
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "inferred obligation OB-auth-002 has no Basis line" "output"
}

test_citation_problems_are_each_reported() {
  cat >> spec/modules/auth.md <<'EOF'

## 12. Suspicious Conditions
- `src/auth/gone.ts:3` and `src/auth/lock.ts:28-31` and `lock.ts:4` and `/abs/src/auth/lock.ts:2`
- Config literal `retry.max:3` is not a citation.
EOF
  check
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "cited file not found \`src/auth/gone.ts:3\`" "missing file"
  assert_contains "$STDOUT" "cited line 31 is past the end of src/auth/lock.ts (30 lines)" "past the end"
  assert_contains "$STDOUT" "citation without a repository path \`lock.ts:4\`" "bare file name"
  assert_contains "$STDOUT" "absolute path in citation" "absolute path"
  assert_not_contains "$STDOUT" "retry.max" "non-citation literal"
  assert_eq "check-spec: 2 obligations, 3 cases, 10 citations, 4 problems." "$(last_line "$STDOUT")" "summary"
}

test_test_source_must_cite_a_test_file() {
  sed -i.bak 's#^- Source: test — `test/auth/lock.test.ts:5-12`#- Source: test — `src/auth/lock.ts:5`#' spec/acceptance/auth.md
  check
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "case AC-auth-001-a says Source: test but cites a non-test file src/auth/lock.ts" "output"
}

test_case_without_source_fails() {
  sed -i.bak '/^- Source: code — `src\/auth\/lock.ts:14`$/d' spec/acceptance/auth.md
  check
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "case AC-auth-001-b has no Source line" "output"
}

test_contracts_file_is_checked_too() {
  cat > spec/contracts.md <<'EOF'
# Contracts

## Obligations

### OB-x-001 · rule · observed
Lockout spans modules.
- Evidence: `src/auth/lock.ts:99`
- Cases: positive
EOF
  check
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "contracts.md:7: cited line 99 is past the end" "citation"
  assert_contains "$STDOUT" "OB-x-001 lists positive but no acceptance case covers it" "coverage"
}

test_usage_errors_exit_2() {
  run bash "$(script "$RUN")" spec
  assert_eq 2 "$STATUS" "one argument"
  run bash "$(script "$RUN")" repo repo
  assert_eq 2 "$STATUS" "no modules directory"
  assert_contains "$STDERR" "no modules/ directory" "stderr"
  run bash "$(script "$RUN")" spec nowhere
  assert_eq 2 "$STATUS" "missing repository root"
}

run_tests
