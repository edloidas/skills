#!/usr/bin/env bash
# validate-skills.sh --skill — the per-skill rules of the repo's hard gate, run against
# fixture skills. The gate fails CI, so a rule that misfires blocks every change and a
# rule that never fires lets the regression it exists for ship.

. "$(dirname "$0")/../lib/assert.sh"
. "$(dirname "$0")/../lib/fixture.sh"

VALIDATOR=".github/scripts/validate-skills.sh"
CANONICAL="audit/skills/skill-audit/references/asking-the-user.md"

validate() {
  run bash "$(script "$VALIDATOR")" --skill "$@"
}

# make_skill <group>/skills/<name> <compatibility> [extra frontmatter line]
# Body is read from stdin.
make_skill() {
  local dir="$1" compat="$2" extra="${3:-}"
  mkdir -p "$dir"
  {
    printf -- '---\nname: %s\ndescription: Formats a changelog entry from a commit range.\n' "$(basename "$dir")"
    printf 'compatibility: %s\n' "$compat"
    [ -z "$extra" ] || printf '%s\n' "$extra"
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
  make_skill demo/skills/clean "$portable" <<'EOF'
# Clean

Read the range and print one line per commit.
EOF
  validate demo/skills/clean
  assert_eq 0 "$STATUS" "exit status"
}

test_shouty_body_line_fails() {
  make_skill demo/skills/loud "$portable" <<'EOF'
# Loud

You MUST print one line per commit.
EOF
  validate demo/skills/loud
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
  long_body 200 | make_skill demo/skills/wide "$portable"
  validate demo/skills/wide
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "the ceiling is 5000" "error output"
}

test_budgeted_skill_inside_its_ceiling_passes() {
  long_body 180 | make_skill review/skills/consilium "$portable"
  validate review/skills/consilium
  assert_eq 0 "$STATUS" "exit status"
}

test_budgeted_skill_past_its_ceiling_fails() {
  long_body 200 | make_skill review/skills/consilium "$portable"
  validate review/skills/consilium
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "the ceiling is 5300" "error output"
}

# -------------------------------------------------------- dispatched prompts --

test_shouty_word_inside_a_prompt_fence_fails() {
  make_skill demo/skills/fleet "$portable" <<'EOF'
# Fleet

Dispatch one worker per file with `references/worker-prompt.md`.
EOF
  mkdir -p demo/skills/fleet/references
  printf '# Worker\n\n```\nYou MUST report every finding.\n```\n' > demo/skills/fleet/references/worker-prompt.md
  validate demo/skills/fleet
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "references/worker-prompt.md:4" "error output"
}

test_shouty_word_in_backticks_inside_a_prompt_passes() {
  make_skill demo/skills/fleet "$portable" <<'EOF'
# Fleet

Dispatch one worker per file with `references/worker-prompt.md`.
EOF
  mkdir -p demo/skills/fleet/references
  printf '# Worker\n\n```\nFlag `You MUST` wherever it appears.\n```\n' > demo/skills/fleet/references/worker-prompt.md
  validate demo/skills/fleet
  assert_eq 0 "$STATUS" "exit status"
}

test_shouty_word_in_a_non_prompt_reference_passes() {
  make_skill demo/skills/fleet "$portable" <<'EOF'
# Fleet

Look the rule up in `references/catalog.md`.
EOF
  mkdir -p demo/skills/fleet/references
  printf '# Catalog\n\n```\nThe ruleset MUST block deletion.\n```\n' > demo/skills/fleet/references/catalog.md
  validate demo/skills/fleet
  assert_eq 0 "$STATUS" "exit status"
}

# --------------------------------------------------------- Asking the User --

test_canonical_ask_section_passes() {
  { printf '# Asker\n\n'; canonical_section; printf '\n## Workflow\n\nAsk, per **Asking the User**:\n'; } \
    | make_skill demo/skills/asker "$portable" "allowed-tools: AskUserQuestion Read"
  validate demo/skills/asker
  assert_eq 0 "$STATUS" "exit status"
}

# Reflowing the paragraph must not break the build; only the words are the contract.
test_reflowed_canonical_ask_section_passes() {
  { printf '# Asker\n\n'; canonical_section | tr '\n' ' ' | sed 's/ Every/\n\nEvery/; s/^## Asking the User */## Asking the User\n\n/'; printf '\n'; } \
    | make_skill demo/skills/asker "$portable" "allowed-tools: AskUserQuestion Read"
  validate demo/skills/asker
  assert_eq 0 "$STATUS" "exit status"
}

test_paraphrased_ask_section_fails() {
  make_skill demo/skills/asker "$portable" "allowed-tools: AskUserQuestion Read" <<'EOF'
# Asker

## Asking the User

Ask with `AskUserQuestion` where available; otherwise list numbered options in chat.
EOF
  validate demo/skills/asker
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "differs from the canonical wording" "error output"
}

test_call_site_without_a_section_fails() {
  make_skill demo/skills/asker "$portable" <<'EOF'
# Asker

Ask, per **Asking the User**: keep or drop the entry.
EOF
  validate demo/skills/asker
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "missing or differs" "error output"
}

test_claude_only_skill_may_paraphrase() {
  make_skill demo/skills/asker "Claude Code" "allowed-tools: AskUserQuestion Read" <<'EOF'
# Asker

## Asking the User

Ask with `AskUserQuestion`.
EOF
  validate demo/skills/asker
  assert_eq 0 "$STATUS" "exit status"
}

test_refusal_exempt_skill_keeps_its_own_section() {
  make_skill review/skills/pr-review "$portable" <<'EOF'
# PR Review

## Asking the User

This skill asks one question in prose, as the last line of its report, and never a modal.
EOF
  validate review/skills/pr-review
  assert_eq 0 "$STATUS" "exit status"
}

run_tests
