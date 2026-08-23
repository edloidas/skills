#!/usr/bin/env bash
# agent-config.sh — writes and moves a repo's instruction files. It creates
# symlinks, deletes existing ones, and with --force renames a real file, so the
# cases that matter most are the ones where it must refuse.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

AGENT_CONFIG="maintain/skills/agent-config/scripts/agent-config.sh"

agent_config() {
  run bash "$(script "$AGENT_CONFIG")" "$@"
}

# A repo root with CLAUDE.md as the one real instruction file.
claude_repo() {
  mkdir -p repo
  cd repo
  printf '# Instructions\n' > CLAUDE.md
}

# --------------------------------------------------------- canonical detection --

test_status_detects_claude_md_as_canonical() {
  claude_repo
  agent_config status
  assert_contains "$STDOUT" "Canonical instruction file: CLAUDE.md" "status output"
}

test_status_detects_agents_md_when_claude_md_is_absent() {
  mkdir -p repo
  cd repo
  printf '# Instructions\n' > AGENTS.md
  agent_config status
  assert_contains "$STDOUT" "Canonical instruction file: AGENTS.md" "status output"
}

# Two independent regular files is a conflict only the caller can settle, and
# guessing would silently discard one of them.
test_two_real_instruction_files_exit_2() {
  mkdir -p repo
  cd repo
  printf 'claude\n' > CLAUDE.md
  printf 'agents\n' > AGENTS.md
  agent_config status
  assert_eq 2 "$STATUS" "exit status"
  assert_contains "$STDERR" "both regular files" "error output"
}

test_no_instruction_file_exits_2() {
  mkdir -p repo
  cd repo
  agent_config status
  assert_eq 2 "$STATUS" "exit status"
  assert_contains "$STDERR" "no regular CLAUDE.md or AGENTS.md" "error output"
}

test_explicit_canonical_symlink_is_rejected() {
  claude_repo
  ln -s CLAUDE.md LINKED.md
  agent_config status --canonical LINKED.md
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "is a symlink" "error output"
}

test_explicit_canonical_missing_file_is_rejected() {
  claude_repo
  agent_config status --canonical NOPE.md
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "not found" "error output"
}

# ------------------------------------------------------------------- status ----

# AGENTS.md is required whenever it is not canonical, so its absence is drift.
test_status_reports_drift_when_required_link_is_missing() {
  claude_repo
  agent_config status
  assert_eq 3 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Drift found." "status output"
}

test_status_is_clean_when_required_link_is_correct() {
  claude_repo
  ln -s CLAUDE.md AGENTS.md
  agent_config status
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Every required instruction file is consistent." "status output"
}

test_status_reports_a_broken_link_as_drift() {
  claude_repo
  ln -s MISSING.md AGENTS.md
  agent_config status
  assert_eq 3 "$STATUS" "exit status"
  assert_contains "$STDOUT" "BROKEN symlink" "status output"
}

test_status_reports_a_misdirected_link_as_drift() {
  claude_repo
  printf 'other\n' > OTHER.md
  ln -s OTHER.md AGENTS.md
  agent_config status
  assert_eq 3 "$STATUS" "exit status"
  assert_contains "$STDOUT" "expected CLAUDE.md" "status output"
}

test_status_reports_a_duplicate_regular_file_as_drift() {
  claude_repo
  printf 'duplicate\n' > GEMINI.md
  agent_config status
  assert_eq 3 "$STATUS" "exit status"
  assert_contains "$STDOUT" "REGULAR FILE" "status output"
}

# GEMINI.md and the Copilot file are opt-in, so their absence is not drift.
test_missing_optional_links_are_not_drift() {
  claude_repo
  ln -s CLAUDE.md AGENTS.md
  agent_config status
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Optional hosts left unlinked." "status output"
}

# --------------------------------------------------------------------- link ----

test_link_creates_a_relative_symlink_at_the_root() {
  claude_repo
  agent_config link AGENTS.md
  assert_eq 0 "$STATUS" "exit status"
  assert_symlink_to AGENTS.md CLAUDE.md
  assert_eq "$(cat CLAUDE.md)" "$(cat AGENTS.md)" "content read through the link"
}

# A nested name has to walk back up to the root, or the link resolves relative
# to .github/ and dangles.
test_link_walks_back_up_for_a_nested_name() {
  claude_repo
  agent_config link .github/copilot-instructions.md
  assert_eq 0 "$STATUS" "exit status"
  assert_symlink_to .github/copilot-instructions.md ../CLAUDE.md
  assert_eq "$(cat CLAUDE.md)" "$(cat .github/copilot-instructions.md)" \
    "content read through the nested link"
}

test_link_accepts_several_names_at_once() {
  claude_repo
  agent_config link AGENTS.md GEMINI.md
  assert_eq 0 "$STATUS" "exit status"
  assert_symlink_to AGENTS.md CLAUDE.md
  assert_symlink_to GEMINI.md CLAUDE.md
}

test_link_is_idempotent() {
  claude_repo
  agent_config link AGENTS.md
  agent_config link AGENTS.md
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "identical" "second-run output"
  assert_symlink_to AGENTS.md CLAUDE.md
}

test_link_repoints_a_misdirected_symlink() {
  claude_repo
  printf 'other\n' > OTHER.md
  ln -s OTHER.md AGENTS.md
  agent_config link AGENTS.md
  assert_eq 0 "$STATUS" "exit status"
  assert_symlink_to AGENTS.md CLAUDE.md
  # The old target is left alone; relinking is not a delete.
  assert_file OTHER.md
}

test_link_repoints_a_broken_symlink() {
  claude_repo
  ln -s MISSING.md AGENTS.md
  agent_config link AGENTS.md
  assert_eq 0 "$STATUS" "exit status"
  assert_symlink_to AGENTS.md CLAUDE.md
}

# The important refusal: a real file at the target holds content that is not in
# the canonical file, and overwriting it silently would lose it.
test_link_refuses_to_clobber_a_regular_file() {
  claude_repo
  printf 'hand-written\n' > GEMINI.md
  agent_config link GEMINI.md
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "blocked" "link output"
  assert_eq "hand-written" "$(cat GEMINI.md)" "GEMINI.md content"
  [ ! -L GEMINI.md ] || fail "GEMINI.md was replaced by a symlink"
}

test_link_force_backs_up_a_regular_file_before_linking() {
  claude_repo
  printf 'hand-written\n' > GEMINI.md
  agent_config link GEMINI.md --force
  assert_eq 0 "$STATUS" "exit status"
  assert_symlink_to GEMINI.md CLAUDE.md
  assert_eq "hand-written" "$(cat GEMINI.md.bak)" "backup content"
}

# A hand-written AGENTS.md next to a real CLAUDE.md is the two-real-files
# conflict, so auto-detection refuses before `link` is reached. The remedy the
# exit-2 message names has to actually get through, in both steps.
test_regular_agents_md_needs_explicit_canonical_then_force() {
  claude_repo
  printf 'hand-written\n' > AGENTS.md

  agent_config link AGENTS.md
  assert_eq 2 "$STATUS" "exit status"
  assert_contains "$STDERR" "--canonical" "exit-2 advice"

  agent_config link AGENTS.md --canonical CLAUDE.md
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "blocked" "link output"

  agent_config link AGENTS.md --canonical CLAUDE.md --force
  assert_eq 0 "$STATUS" "exit status"
  assert_symlink_to AGENTS.md CLAUDE.md
  assert_eq "hand-written" "$(cat AGENTS.md.bak)" "backup content"
}

test_link_dry_run_writes_nothing() {
  claude_repo
  agent_config link AGENTS.md .github/copilot-instructions.md --dry-run
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Dry run — nothing written." "link output"
  assert_no_file AGENTS.md
  assert_no_file .github
}

test_link_dry_run_still_reports_a_blocked_file() {
  claude_repo
  printf 'hand-written\n' > GEMINI.md
  agent_config link GEMINI.md --dry-run
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "blocked" "link output"
  assert_eq "hand-written" "$(cat GEMINI.md)" "GEMINI.md content"
  [ ! -L GEMINI.md ] || fail "GEMINI.md was replaced by a symlink"
}

test_link_refuses_to_point_the_canonical_file_at_itself() {
  claude_repo
  agent_config link CLAUDE.md
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "cannot link to itself" "error output"
  [ ! -L CLAUDE.md ] || fail "CLAUDE.md was replaced by a symlink"
}

# ------------------------------------------------------------------- usage ----

test_no_subcommand_prints_usage_and_exits_1() {
  claude_repo
  agent_config
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Usage:" "output"
}

test_two_subcommands_are_rejected() {
  claude_repo
  agent_config status link
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "only one subcommand" "error output"
}

test_unknown_flag_is_rejected() {
  claude_repo
  agent_config status --nope
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "unknown flag" "error output"
}

test_help_exits_0() {
  claude_repo
  agent_config --help
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Known link names:" "help output"
}

# `link` with no names must reach its own error message rather than a raw bash
# error. The guard is `[ "${#TARGETS[@]}" -gt 0 ]`, which is the form that is safe
# under `set -u` on bash before 4.4 — unlike `"${TARGETS[@]}"`, which aborts on an
# empty array there. This case pins that the guard fires before any expansion.
test_link_without_names_reports_a_usage_error() {
  claude_repo
  agent_config link
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDERR" "link needs at least one name" "error output"
}

run_tests
