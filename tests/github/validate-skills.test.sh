#!/usr/bin/env bash
# validate-skills.sh --skill — the per-skill rules of the repo's hard gate, run against
# fixture skills. The gate fails CI, so a rule that misfires blocks every change and a
# rule that never fires lets the regression it exists for ship.

. "$(dirname "$0")/../lib/assert.sh"
. "$(dirname "$0")/../lib/fixture.sh"

VALIDATOR=".github/scripts/validate-skills.sh"
CANONICAL="skills/skill-audit/references/asking-the-user.md"

validate() {
  run bash "$(script "$VALIDATOR")" --skill "$@"
}

# make_skill skills/<name> <compatibility> [extra frontmatter line]
# Body is read from stdin. TIER sets metadata.tier (default routed); TIER=none omits it.
make_skill() {
  local dir="$1" compat="$2" extra="${3:-}" tier="${TIER:-routed}"
  mkdir -p "$dir"
  {
    printf -- '---\nname: %s\ndescription: Formats a changelog entry from a commit range.\n' "$(basename "$dir")"
    printf 'compatibility: %s\n' "$compat"
    [ -z "$extra" ] || printf '%s\n' "$extra"
    [ "$tier" = none ] || printf 'metadata:\n  tier: %s\n' "$tier"
    printf -- '---\n\n'
    cat
  } > "$dir/SKILL.md"
}

portable="Claude Code, Codex, OpenCode, Pi"

# The canonical paragraph exactly as the reference file holds it.
canonical_section() {
  sed -n '/^## Asking the User$/,$p' "$(script "$CANONICAL")"
}

# ----------------------------------------------------------------- baseline --

test_clean_skill_passes() {
  make_skill skills/clean "$portable" <<'EOF'
# Clean

Read the range and print one line per commit.
EOF
  validate skills/clean
  assert_eq 0 "$STATUS" "exit status"
}

test_shouty_body_line_fails() {
  make_skill skills/loud "$portable" <<'EOF'
# Loud

You MUST print one line per commit.
EOF
  validate skills/loud
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "shouty emphasis at SKILL.md" "error output"
}

# ------------------------------------------------------------- token ceiling --

# Few lines, many bytes: the shape the line cap alone let through.
long_body() {
  local n="$1" i=0
  printf '# Wide\n\n'
  while [ "$i" -lt "$n" ]; do
    printf 'Read the next commit in the range and print its subject beside its short hash, then move on to the one after it.\n'
    i=$((i + 1))
  done
}

test_body_over_token_cap_fails() {
  long_body 200 | make_skill skills/wide "$portable"
  validate skills/wide
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "the ceiling is 5000" "error output"
}

test_budgeted_skill_inside_its_ceiling_passes() {
  long_body 190 | make_skill skills/code-cleanup "$portable"
  validate skills/code-cleanup
  assert_eq 0 "$STATUS" "exit status"
}

test_budgeted_skill_past_its_ceiling_fails() {
  long_body 210 | make_skill skills/code-cleanup "$portable"
  validate skills/code-cleanup
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "the ceiling is 5590" "error output"
}

# -------------------------------------------------------- dispatched prompts --

test_shouty_word_inside_a_prompt_fence_fails() {
  make_skill skills/fleet "$portable" <<'EOF'
# Fleet

Dispatch one worker per file with `references/worker-prompt.md`.
EOF
  mkdir -p skills/fleet/references
  printf '# Worker\n\n```\nYou MUST report every finding.\n```\n' > skills/fleet/references/worker-prompt.md
  validate skills/fleet
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "references/worker-prompt.md:4" "error output"
}

test_shouty_word_in_backticks_inside_a_prompt_passes() {
  make_skill skills/fleet "$portable" <<'EOF'
# Fleet

Dispatch one worker per file with `references/worker-prompt.md`.
EOF
  mkdir -p skills/fleet/references
  printf '# Worker\n\n```\nFlag `You MUST` wherever it appears.\n```\n' > skills/fleet/references/worker-prompt.md
  validate skills/fleet
  assert_eq 0 "$STATUS" "exit status"
}

test_shouty_word_in_a_non_prompt_reference_passes() {
  make_skill skills/fleet "$portable" <<'EOF'
# Fleet

Look the rule up in `references/catalog.md`.
EOF
  mkdir -p skills/fleet/references
  printf '# Catalog\n\n```\nThe ruleset MUST block deletion.\n```\n' > skills/fleet/references/catalog.md
  validate skills/fleet
  assert_eq 0 "$STATUS" "exit status"
}

# --------------------------------------------------------- Asking the User --

test_canonical_ask_section_passes() {
  { printf '# Asker\n\n'; canonical_section; printf '\n## Workflow\n\nAsk, per **Asking the User**:\n'; } \
    | make_skill skills/asker "$portable" "allowed-tools: AskUserQuestion Read"
  validate skills/asker
  assert_eq 0 "$STATUS" "exit status"
}

# Reflowing the paragraph must not break the build; only the words are the contract.
test_reflowed_canonical_ask_section_passes() {
  { printf '# Asker\n\n'; canonical_section | tr '\n' ' ' | sed 's/ Every/\n\nEvery/; s/^## Asking the User */## Asking the User\n\n/'; printf '\n'; } \
    | make_skill skills/asker "$portable" "allowed-tools: AskUserQuestion Read"
  validate skills/asker
  assert_eq 0 "$STATUS" "exit status"
}

test_paraphrased_ask_section_fails() {
  make_skill skills/asker "$portable" "allowed-tools: AskUserQuestion Read" <<'EOF'
# Asker

## Asking the User

Ask with `AskUserQuestion` where available; otherwise list numbered options in chat.
EOF
  validate skills/asker
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "differs from the canonical wording" "error output"
}

test_call_site_without_a_section_fails() {
  make_skill skills/asker "$portable" <<'EOF'
# Asker

Ask, per **Asking the User**: keep or drop the entry.
EOF
  validate skills/asker
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "missing or differs" "error output"
}

test_claude_only_skill_may_paraphrase() {
  make_skill skills/asker "Claude Code" "allowed-tools: AskUserQuestion Read" <<'EOF'
# Asker

## Asking the User

Ask with `AskUserQuestion`.
EOF
  validate skills/asker
  assert_eq 0 "$STATUS" "exit status"
}

test_refusal_exempt_skill_keeps_its_own_section() {
  make_skill skills/pr-review "$portable" <<'EOF'
# PR Review

## Asking the User

This skill asks one question in prose, as the last line of its report, and never a modal.
EOF
  validate skills/pr-review
  assert_eq 0 "$STATUS" "exit status"
}

# --------------------------------------------------------------------- tiers --

test_missing_tier_fails() {
  printf '# Untiered\n' | TIER=none make_skill skills/untiered "$portable"
  validate skills/untiered
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "has no metadata.tier" "error output"
}

test_unknown_tier_fails() {
  printf '# Odd\n' | TIER=hidden make_skill skills/odd "$portable"
  validate skills/odd
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "'hidden' is not one of auto, routed, manual" "error output"
}

test_manual_without_the_flag_fails() {
  printf '# Manual\n' | TIER=manual make_skill skills/manual "$portable"
  validate skills/manual
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "tier 'manual' needs disable-model-invocation: true" "error output"
}

test_manual_with_the_flag_passes() {
  printf '# Manual\n' | TIER=manual make_skill skills/manual "$portable" "disable-model-invocation: true"
  validate skills/manual
  assert_eq 0 "$STATUS" "exit status"
}

test_routed_with_the_flag_fails() {
  printf '# Routed\n' | make_skill skills/routed "$portable" "disable-model-invocation: true"
  validate skills/routed
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "tier 'routed' with disable-model-invocation: true" "error output"
}

test_auto_with_the_flag_fails() {
  printf '# Auto\n' | TIER=auto make_skill skills/auto "$portable" "disable-model-invocation: true"
  validate skills/auto
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "tier 'auto' with disable-model-invocation: true" "error output"
}

run_tests
