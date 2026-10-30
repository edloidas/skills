#!/usr/bin/env bash
# validate-codex.sh — the tier-to-Codex mapping, run against a fixture repo. The script
# resolves the repo from its own location, so each case copies it into the sandbox
# beside a one-skill catalog.

. "$(dirname "$0")/../lib/assert.sh"
. "$(dirname "$0")/../lib/fixture.sh"

# make_repo <tier> <allow_implicit_invocation>
make_repo() {
  local tier="$1" implicit="$2"
  mkdir -p scripts/codex skills/sample/agents
  cp "$(script scripts/validate-codex.sh)" scripts/validate-codex.sh
  cat > scripts/codex/catalog.json <<'EOF'
{
  "version": "1.0.0",
  "marketplace": { "name": "fixture", "displayName": "Fixture" },
  "plugins": [
    {
      "name": "fixture", "displayName": "Fixture", "description": "d", "shortDescription": "s",
      "longDescription": "l", "category": "c", "websiteURL": "https://example.com",
      "brandColor": "#000000", "keywords": ["k"], "skills": ["skills/sample"]
    }
  ]
}
EOF
  printf -- '---\nname: sample\ndescription: Formats a changelog entry.\ncompatibility: Claude Code, Codex, OpenCode, Pi\nmetadata:\n  tier: %s\n---\n\n# Sample\n' \
    "$tier" > skills/sample/SKILL.md
  printf 'interface:\n  display_name: "Sample"\npolicy:\n  allow_implicit_invocation: %s\n' \
    "$implicit" > skills/sample/agents/openai.yaml
}

validate() {
  run bash scripts/validate-codex.sh
}

test_auto_with_implicit_passes() {
  make_repo auto true
  validate
  assert_eq 0 "$STATUS" "exit status"
}

test_auto_without_implicit_fails() {
  make_repo auto false
  validate
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "needs allow_implicit_invocation: true" "error output"
}

test_routed_without_implicit_passes() {
  make_repo routed false
  validate
  assert_eq 0 "$STATUS" "exit status"
}

test_routed_with_implicit_fails() {
  make_repo routed true
  validate
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "needs allow_implicit_invocation: false" "error output"
}

test_manual_with_implicit_fails() {
  make_repo manual true
  validate
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "needs allow_implicit_invocation: false" "error output"
}

test_missing_tier_fails() {
  make_repo "" false
  validate
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "has no valid metadata.tier" "error output"
}

run_tests
