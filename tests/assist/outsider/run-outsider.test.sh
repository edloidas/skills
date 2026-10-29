#!/usr/bin/env bash
# run-outsider.sh — picks an agent CLI that is not the current host and runs it
# read-only. Two properties carry the whole design: it never invokes the host
# (recursion), and it never fails the caller (exit 0, skips reported on
# stdout) — except exit 2 for a review that cannot start (no repository, an unborn
# HEAD, a ref that does not resolve), and exit 3 for
# an uncommitted payload the user has not approved. Everything else is selection
# bookkeeping.
#
# Every case pins PATH to a sandbox, so "installed" means "a stub exists" and no
# real agent CLI on the machine can influence the result.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

OUTSIDER="assist/skills/outsider/scripts/run-outsider.sh"

outsider() {
  run bash "$(script "$OUTSIDER")" "$@"
}

# An agent stub that echoes a recognisable answer. `codex` is invoked with
# `-o FILE` and its answer is read back from there, so the stub honors it.
stub_agent() {
  local name="$1" answer="${2:-ANSWER from $1}"
  stub "$name" <<EOF
out=""
prev=""
for arg in "\$@"; do
  if [ "\$prev" = "-o" ]; then out="\$arg"; fi
  prev="\$arg"
done
cat > /dev/null
if [ -n "\$out" ]; then
  printf '%s\\n' "$answer" > "\$out"
else
  printf '%s\\n' "$answer"
fi
EOF
}

# --------------------------------------------------------------------- list ----

test_list_marks_the_host_as_skipped() {
  only_agents codex claude
  outsider list --host claude
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "claude     claude     host (skipped)" "list output"
  assert_contains "$STDOUT" "codex      codex      installed" "list output"
  assert_contains "$STDOUT" "host: claude" "list output"
}

test_list_reports_uninstalled_agents() {
  only_agents codex
  outsider list --host claude
  assert_contains "$STDOUT" "opencode   opencode   not installed" "list output"
  assert_contains "$STDOUT" "would select: codex" "list output"
}

test_list_reports_when_nothing_is_selectable() {
  only_agents
  outsider list --host claude
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "would select: none" "list output"
}

# ---------------------------------------------------------------- selection ----

# The recursion guard, and the reason the skill can declare every host: with
# only the host's own CLI installed, there is nothing to run and it must skip
# rather than shell out to itself.
test_host_is_never_selected_even_as_the_only_installed_agent() {
  only_agents claude
  stub_agent claude "SHOULD NOT RUN"
  outsider ask --host claude <<< "question"
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "No external agent CLI available" "output"
  assert_not_contains "$STDOUT" "SHOULD NOT RUN" "output"
}

test_first_installed_non_host_agent_wins() {
  only_agents claude opencode
  stub_agent opencode
  outsider ask --host claude <<< "question"
  assert_contains "$STDOUT" "[outsider] agent: opencode" "output"
  assert_contains "$STDOUT" "ANSWER from opencode" "output"
}

test_agent_order_is_configurable() {
  only_agents claude opencode pi
  stub_agent pi
  stub_agent opencode
  OUTSIDER_AGENTS="pi opencode codex claude" outsider ask --host claude <<< "question"
  assert_contains "$STDOUT" "[outsider] agent: pi" "output"
}

# An explicit --agent wins over the order, and over the host exclusion, because
# the caller asked for it by name.
test_explicit_agent_overrides_the_order() {
  only_agents codex opencode
  stub_agent opencode
  outsider ask --agent opencode --host claude <<< "question"
  assert_contains "$STDOUT" "[outsider] agent: opencode" "output"
}

test_unknown_explicit_agent_is_reported() {
  only_agents codex
  outsider ask --agent nope --host claude <<< "question"
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Unknown agent 'nope'" "output"
}

test_uninstalled_explicit_agent_is_reported() {
  only_agents claude
  outsider ask --agent codex --host claude <<< "question"
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Agent 'codex' is not installed" "output"
}

# `--host auto` means "sniff it", not "a host literally named auto", which would
# otherwise exclude nothing and leave the real host selectable.
test_host_auto_falls_back_to_detection() {
  only_agents claude opencode
  stub_agent opencode
  OUTSIDER_HOST=claude outsider ask --host auto <<< "question"
  assert_contains "$STDOUT" "[outsider] agent: opencode" "output"
}

test_host_is_detected_from_the_claude_code_marker() {
  only_agents claude opencode
  stub_agent opencode
  CLAUDECODE=1 outsider ask <<< "question"
  assert_contains "$STDOUT" "[outsider] agent: opencode" "output"
}

# ------------------------------------------------------------------- config ----

config_file() {
  mkdir -p "$HOME/.config/edloidas/outsider"
  cat > "$HOME/.config/edloidas/outsider/config"
}

test_config_file_sets_the_agent_order() {
  only_agents claude opencode pi
  stub_agent pi
  stub_agent opencode
  config_file <<'EOF'
OUTSIDER_AGENTS=pi opencode
EOF
  outsider ask --host claude <<< "question"
  assert_contains "$STDOUT" "[outsider] agent: pi" "output"
}

test_config_file_sets_the_model() {
  only_agents claude opencode
  stub_agent opencode
  config_file <<'EOF'
OUTSIDER_MODEL_OPENCODE="some/model"
EOF
  outsider ask --host claude <<< "question"
  assert_contains "$STDOUT" "(model: some/model)" "output"
}

# The environment wins over the file, so a one-off override does not need the
# file edited.
test_environment_overrides_the_config_file() {
  only_agents claude opencode
  stub_agent opencode
  config_file <<'EOF'
OUTSIDER_MODEL_OPENCODE=from-file
EOF
  OUTSIDER_MODEL_OPENCODE=from-env outsider ask --host claude <<< "question"
  assert_contains "$STDOUT" "(model: from-env)" "output"
  assert_not_contains "$STDOUT" "from-file" "output"
}

# The config is parsed, never sourced. A value that looks like a command
# substitution has to stay a literal string, or a config file becomes arbitrary
# code execution on every invocation.
test_config_file_cannot_execute_commands() {
  only_agents claude opencode
  stub_agent opencode
  config_file <<'EOF'
OUTSIDER_MODEL_OPENCODE=$(touch pwned)
OUTSIDER_ARGS_OPENCODE=`touch pwned-backtick`
EOF
  outsider ask --host claude <<< "question"
  assert_eq 0 "$STATUS" "exit status"
  assert_no_file pwned
  assert_no_file pwned-backtick
}

test_non_outsider_config_lines_are_ignored() {
  only_agents claude opencode
  stub_agent opencode
  config_file <<'EOF'
PATH=/nonexistent
SOMETHING_ELSE=1
OUTSIDER_MODEL_OPENCODE=kept
EOF
  outsider ask --host claude <<< "question"
  assert_contains "$STDOUT" "(model: kept)" "output"
}

# ---------------------------------------------------------------------- ask ----

test_ask_reads_the_question_from_stdin() {
  only_agents claude opencode
  stub_agent opencode
  outsider ask --host claude <<< "what about this"
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "ANSWER from opencode" "output"
}

test_ask_reads_the_question_from_a_file() {
  only_agents claude opencode
  stub_agent opencode
  printf 'what about this\n' > question.md
  outsider ask --host claude question.md
  assert_contains "$STDOUT" "ANSWER from opencode" "output"
}

# A path that does not resolve would otherwise send an empty question and get
# back something that reads like a real answer.
test_ask_rejects_a_question_file_that_does_not_exist() {
  only_agents claude opencode
  stub_agent opencode
  outsider ask --host claude missing.md
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Question file not found: missing.md" "output"
  assert_not_contains "$STDOUT" "ANSWER" "output"
}

# The preamble carries the responder's whole brief. An explicit one that does
# not resolve is a hard stop for the same reason.
test_ask_rejects_an_explicit_preamble_that_does_not_exist() {
  only_agents claude opencode
  stub_agent opencode
  outsider ask --host claude --preamble missing-preamble.md <<< "question"
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Preamble file not found" "output"
  assert_contains "$STDOUT" "hard stop" "output"
  assert_not_contains "$STDOUT" "ANSWER" "output"
}

test_ask_sends_the_default_preamble_with_the_question() {
  only_agents claude opencode
  # This stub echoes the prompt it received rather than an answer, so the test
  # can see what actually reached the agent.
  stub opencode <<'EOF'
cat
EOF
  outsider ask --host claude <<< "MY-QUESTION-MARKER"
  assert_contains "$STDOUT" "MY-QUESTION-MARKER" "prompt sent to the agent"
  # The first line of the default prompt file, so a silently-empty preamble
  # would show up here.
  assert_contains "$STDOUT" "$(head -n 1 "$REPO_ROOT/assist/skills/outsider/references/prompt.md")" \
    "prompt sent to the agent"
}

test_ask_accepts_a_custom_preamble() {
  only_agents claude opencode
  stub opencode <<'EOF'
cat
EOF
  printf 'CUSTOM-PREAMBLE\n' > preamble.md
  outsider ask --host claude --preamble preamble.md <<< "question"
  assert_contains "$STDOUT" "CUSTOM-PREAMBLE" "prompt sent to the agent"
}

# codex is handed `-o FILE` so its answer does not come back wrapped in the
# echoed transcript. The file has to be read, and then removed.
test_codex_answer_is_read_from_its_output_file() {
  only_agents claude codex
  stub_agent codex "CODEX-ANSWER"
  outsider ask --host claude <<< "question"
  assert_contains "$STDOUT" "CODEX-ANSWER" "output"
  assert_eq "" "$(ls "$TMPDIR"/outsider-codex-*.out 2>/dev/null || true)" "leftover codex output file"
}

# Callers such as pr-triage run from a directory holding many clones, which is
# not itself a repo, and codex refuses to start there without this flag.
test_codex_is_invoked_with_skip_git_repo_check() {
  only_agents claude codex
  stub_recording codex
  outsider ask --host claude <<< "question"
  assert_contains "$(calls_of codex)" "exec --ephemeral --skip-git-repo-check -s read-only" "codex arguments"
}

# The outside agent is launched read-only, so no responder may be granted a
# write-capable tool or a blanket git grant.
test_claude_is_invoked_with_read_only_tools_only() {
  only_agents codex claude
  stub_recording claude
  outsider ask --host codex <<< "question"
  local calls
  calls="$(calls_of claude)"
  assert_contains "$calls" "--permission-mode dontAsk" "claude arguments"
  assert_contains "$calls" "--tools Read,Grep,Glob,Bash " "claude arguments"
  assert_contains "$calls" "Bash(git diff:*),Bash(git log:*),Bash(git show:*)" "claude arguments"
  assert_not_contains "$calls" "Bash(git:*)" "claude arguments"
  assert_not_contains "$calls" "--permission-mode auto" "claude arguments"
  local allowed="${calls##*--allowed-tools }"
  assert_not_contains "$allowed" "Edit" "claude allowed tools"
  assert_not_contains "$allowed" "Write" "claude allowed tools"
}

test_pi_is_invoked_with_read_only_tools_only() {
  only_agents claude pi
  stub_recording pi
  outsider ask --host claude <<< "question"
  assert_contains "$(calls_of pi)" "-t read,grep,find,ls" "pi arguments"
  assert_not_contains "$(calls_of pi)" "bash" "pi arguments"
}

# ------------------------------------------------------------------- review ----

test_review_of_a_clean_tree_reports_no_changes() {
  init_repo repo main
  cd repo
  commit "initial"
  only_agents claude opencode
  stub_agent opencode
  outsider review --host claude
  assert_eq 0 "$STATUS" "exit status"
  assert_eq "Nothing to review: no uncommitted changes." "$STDOUT" "output"
}

# Both used to print "Nothing to review", which reads as a clean tree.
test_review_outside_a_git_repository_errors_without_running_the_agent() {
  mkdir norepo
  cd norepo
  export GIT_CEILING_DIRECTORIES="$SANDBOX"
  only_agents claude opencode
  stub_recording opencode
  outsider review --host claude
  assert_eq 2 "$STATUS" "exit status"
  assert_contains "$STDOUT" "not inside a git work tree" "output"
  assert_not_contains "$STDOUT" "Nothing to review" "output"
  assert_eq "" "$(calls_of opencode)" "agent invocations"
}

test_review_on_an_unborn_head_errors_without_running_the_agent() {
  init_repo repo main
  cd repo
  printf 'NEW\n' > file.txt
  only_agents claude opencode
  stub_recording opencode
  outsider review --host claude
  assert_eq 2 "$STATUS" "exit status"
  assert_contains "$STDOUT" "HEAD has no commit yet" "output"
  assert_eq "" "$(calls_of opencode)" "agent invocations"
}

# A ref that does not resolve used to yield an empty diff, and the script then
# reviewed the uncommitted changes instead — a scope nobody asked for.
test_review_with_an_unresolvable_base_errors_without_running_the_agent() {
  init_repo repo main
  cd repo
  commit "initial"
  printf 'UNCOMMITTED\n' >> file.txt
  only_agents claude opencode
  stub_recording opencode
  outsider review --host claude --base no-such-branch
  assert_eq 2 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Cannot review --base 'no-such-branch'" "output"
  assert_eq "" "$(calls_of opencode)" "agent invocations"
}

test_review_with_an_unresolvable_commit_errors_without_running_the_agent() {
  init_repo repo main
  cd repo
  commit "initial"
  printf 'UNCOMMITTED\n' >> file.txt
  only_agents claude opencode
  stub_recording opencode
  outsider review --host claude --commit deadbeef
  assert_eq 2 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Cannot review --commit 'deadbeef'" "output"
  assert_eq "" "$(calls_of opencode)" "agent invocations"
}

test_review_of_an_empty_base_diff_does_not_switch_scope() {
  init_repo repo main
  cd repo
  commit "initial"
  printf 'UNCOMMITTED\n' >> file.txt
  only_agents claude opencode
  stub_recording opencode
  outsider review --host claude --base main
  assert_eq 0 "$STATUS" "exit status"
  assert_eq "Nothing to review: --base 'main' has an empty diff." "$STDOUT" "output"
  assert_eq "" "$(calls_of opencode)" "agent invocations"
}

test_review_includes_uncommitted_changes() {
  init_repo repo main
  cd repo
  commit "initial"
  printf 'CHANGED-LINE\n' >> file.txt
  only_agents claude opencode
  stub opencode <<'EOF'
cat
EOF
  outsider review --host claude --uncommitted --confirm-uncommitted
  assert_contains "$STDOUT" "CHANGED-LINE" "diff sent to the agent"
}

# An untracked file is a new file the reviewer has to see, and it is invisible
# to `git diff HEAD`.
test_review_includes_untracked_files() {
  init_repo repo main
  cd repo
  commit "initial"
  printf 'BRAND-NEW\n' > added.txt
  only_agents claude opencode
  stub opencode <<'EOF'
cat
EOF
  outsider review --host claude --uncommitted --confirm-uncommitted
  assert_contains "$STDOUT" "BRAND-NEW" "diff sent to the agent"
}

test_review_of_a_named_commit() {
  init_repo repo main
  cd repo
  commit "initial"
  commit "second" file.txt "COMMITTED-LINE"
  only_agents claude opencode
  stub opencode <<'EOF'
cat
EOF
  outsider review --host claude --commit HEAD
  assert_contains "$STDOUT" "COMMITTED-LINE" "diff sent to the agent"
}

test_review_against_a_base() {
  init_repo repo main
  cd repo
  commit "initial"
  git checkout --quiet -b feature
  commit "feature" file.txt "FEATURE-LINE"
  only_agents claude opencode
  stub opencode <<'EOF'
cat
EOF
  outsider review --host claude --base main
  assert_contains "$STDOUT" "FEATURE-LINE" "diff sent to the agent"
}

# ------------------------------------------------------- uncommitted gate ----
# Uncommitted and untracked content goes to another vendor only after the user
# approved it. Without --confirm-uncommitted the script exits 3, invokes
# nothing, and prints the counts the caller needs to ask.

dirty_repo() {
  init_repo repo main
  cd repo
  commit "initial"
  printf 'CHANGED-LINE\n' >> file.txt
  printf 'BRAND-NEW\n' > added.txt
}

test_uncommitted_review_without_confirmation_sends_nothing() {
  dirty_repo
  only_agents claude opencode
  stub_recording opencode
  outsider review --host claude --uncommitted
  assert_eq 3 "$STATUS" "exit status"
  assert_contains "$STDOUT" "[outsider] uncommitted payload: 2 files (1 untracked)" "output"
  assert_contains "$STDOUT" "would go to opencode" "output"
  assert_contains "$STDOUT" "--confirm-uncommitted" "output"
  assert_contains "$STDOUT" "  file.txt" "file list"
  assert_contains "$STDOUT" "  added.txt (untracked)" "file list"
  assert_eq "" "$(calls_of opencode)" "agent invocations"
}

test_uncommitted_file_list_is_capped_at_20_with_a_remainder() {
  dirty_repo
  local i
  for i in $(seq 1 23); do printf 'x\n' > "new-$i.txt"; done
  only_agents claude opencode
  stub_recording opencode
  outsider review --host claude --uncommitted
  assert_eq 3 "$STATUS" "exit status"
  assert_contains "$STDOUT" "25 files (24 untracked)" "output"
  assert_eq 20 "$(printf '%s\n' "$STDOUT" | grep -c '^  [^+]')" "listed paths"
  assert_contains "$STDOUT" "  +5 more" "remainder"
  assert_not_contains "$(printf '%s\n' "$STDOUT" | grep '^  ' | head -n 20)" "  file.txt" "tracked file cut before untracked ones"
}

# The default scope is uncommitted, so it is gated the same way.
test_default_review_scope_is_gated() {
  dirty_repo
  only_agents claude opencode
  stub_recording opencode
  outsider review --host claude
  assert_eq 3 "$STATUS" "exit status"
  assert_eq "" "$(calls_of opencode)" "agent invocations"
}

test_uncommitted_review_summary_reports_the_payload_size() {
  dirty_repo
  only_agents claude opencode
  stub_recording opencode
  outsider review --host claude --uncommitted
  local bytes
  bytes="$(git diff HEAD; git diff --no-index -- /dev/null added.txt || true)"
  bytes="$(printf '%s' "$bytes" | wc -c)"
  assert_contains "$STDOUT" ", $((bytes)) bytes," "output"
}

test_uncommitted_review_with_confirmation_runs_the_agent() {
  dirty_repo
  only_agents claude opencode
  stub_recording opencode
  outsider review --host claude --uncommitted --confirm-uncommitted
  assert_eq 0 "$STATUS" "exit status"
  assert_ne "" "$(calls_of opencode)" "agent invocations"
  assert_not_contains "$STDOUT" "uncommitted payload" "output"
}

# Committed-only scopes go without the flag, even with a dirty tree beside them.
test_commit_review_needs_no_confirmation() {
  dirty_repo
  only_agents claude opencode
  stub_recording opencode
  outsider review --host claude --commit HEAD
  assert_eq 0 "$STATUS" "exit status"
  assert_ne "" "$(calls_of opencode)" "agent invocations"
}

test_base_review_needs_no_confirmation() {
  init_repo repo main
  cd repo
  commit "initial"
  git checkout --quiet -b feature
  commit "feature" file.txt "FEATURE-LINE"
  printf 'BRAND-NEW\n' > added.txt
  only_agents claude opencode
  stub_recording opencode
  outsider review --host claude --base main
  assert_eq 0 "$STATUS" "exit status"
  assert_ne "" "$(calls_of opencode)" "agent invocations"
}

test_ask_without_attachments_needs_no_confirmation() {
  dirty_repo
  only_agents claude opencode
  stub_recording opencode
  outsider ask --host claude <<< "question"
  assert_eq 0 "$STATUS" "exit status"
  assert_ne "" "$(calls_of opencode)" "agent invocations"
}

test_ask_attaching_a_modified_file_is_gated() {
  dirty_repo
  only_agents claude opencode
  stub_recording opencode
  outsider ask --host claude --attach file.txt --attach added.txt <<< "question"
  assert_eq 3 "$STATUS" "exit status"
  assert_contains "$STDOUT" "[outsider] uncommitted payload: 2 files (1 untracked)" "output"
  assert_contains "$STDOUT" "  file.txt" "file list"
  assert_contains "$STDOUT" "  added.txt (untracked)" "file list"
  assert_eq "" "$(calls_of opencode)" "agent invocations"
}

# A gitignored file is where secrets usually live, so it counts as untracked.
test_ask_attaching_an_ignored_file_is_gated() {
  init_repo repo main
  cd repo
  printf 'secret.env\n' > .gitignore
  commit "initial" .gitignore ""
  printf 'TOKEN=1\n' > secret.env
  only_agents claude opencode
  stub_recording opencode
  outsider ask --host claude --attach secret.env <<< "question"
  assert_eq 3 "$STATUS" "exit status"
  assert_contains "$STDOUT" "1 files (1 untracked)" "output"
}

test_ask_attaching_a_clean_committed_file_needs_no_confirmation() {
  init_repo repo main
  cd repo
  commit "initial" file.txt "COMMITTED-CONTENT"
  only_agents claude opencode
  stub opencode <<'EOF'
cat
EOF
  outsider ask --host claude --attach file.txt <<< "question"
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "COMMITTED-CONTENT" "prompt sent to the agent"
}

test_ask_attachment_is_sent_once_confirmed() {
  dirty_repo
  only_agents claude opencode
  stub opencode <<'EOF'
cat
EOF
  outsider ask --host claude --attach added.txt --confirm-uncommitted <<< "question"
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "----- begin added.txt -----" "prompt sent to the agent"
  assert_contains "$STDOUT" "BRAND-NEW" "prompt sent to the agent"
}

test_ask_rejects_an_attachment_that_does_not_exist() {
  only_agents claude opencode
  stub_recording opencode
  outsider ask --host claude --attach missing.txt <<< "question"
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Attached file not found: missing.txt" "output"
  assert_eq "" "$(calls_of opencode)" "agent invocations"
}

# Asking the user is pointless when no agent would run; the skip comes first.
test_gate_does_not_fire_when_no_agent_is_available() {
  dirty_repo
  only_agents claude
  outsider review --host claude --uncommitted
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "No external agent CLI available" "output"
}

# --------------------------------------------------------- failure handling ----
# The caller is a skill that continues either way, so nothing here may return a
# non-zero status.

test_a_failing_agent_is_reported_without_failing_the_caller() {
  only_agents claude opencode
  stub opencode <<'EOF'
cat > /dev/null
echo "partial output"
exit 3
EOF
  outsider ask --host claude <<< "question"
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "partial output" "output"
  assert_contains "$STDOUT" "opencode failed (exit code 3)" "output"
}

# A bare exit code hides why the agent refused, so its stderr has to reach the
# caller, bounded to the tail.
test_a_failing_agent_reports_its_stderr() {
  only_agents claude opencode
  stub opencode <<'EOF'
cat > /dev/null
for i in $(seq 1 25); do echo "noise $i" >&2; done
echo "Not inside a trusted directory" >&2
exit 1
EOF
  outsider ask --host claude <<< "question"
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "opencode failed (exit code 1)" "output"
  assert_contains "$STDOUT" "Not inside a trusted directory" "output"
  assert_contains "$STDOUT" "noise 25" "output"
  assert_not_contains "$STDOUT" $'noise 5\n' "output"
  assert_eq "" "$(ls "$TMPDIR"/outsider-opencode-*.err 2>/dev/null || true)" "leftover stderr file"
}

test_a_successful_agent_does_not_echo_its_stderr() {
  only_agents claude opencode
  stub opencode <<'EOF'
cat > /dev/null
echo "STDERR-CHATTER" >&2
echo "GOOD-ANSWER"
EOF
  outsider ask --host claude <<< "question"
  assert_contains "$STDOUT" "GOOD-ANSWER" "output"
  assert_not_contains "$STDOUT" "STDERR-CHATTER" "output"
}

test_a_hanging_agent_is_timed_out() {
  only_agents claude opencode
  stub opencode <<'EOF'
cat > /dev/null
sleep 30
EOF
  outsider ask --host claude 1 <<< "question"
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "timed out after 1s" "output"
}

# Every agent invocation goes through `timeout`, which stock macOS does not ship —
# it arrives with Homebrew coreutils as `gtimeout`. A missing one is a local tool
# problem and must not be reported as the agent failing.
#
# `unstub` both spellings. CORE_TOOLS seeds whichever the host has into the
# sandbox, so removing only `timeout` leaves `gtimeout` behind on a machine with
# coreutils installed and the script correctly uses it — which is a different
# scenario, covered by test_gtimeout_is_used_when_timeout_is_absent below. Left
# half-scrubbed, these cases pass on CI and fail on a developer's Mac.
test_a_missing_timeout_binary_is_reported_as_a_local_tool_problem() {
  only_agents claude opencode
  stub_agent opencode
  unstub timeout
  unstub gtimeout
  outsider ask --host claude <<< "question"
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "neither 'timeout' nor 'gtimeout' is on PATH" "output"
  assert_contains "$STDOUT" "brew install coreutils" "output"
  assert_not_contains "$STDOUT" "exit code 127" "output"
  assert_not_contains "$STDOUT" "opencode failed" "output"
}

# Refusing is the deliberate choice over running unbounded: a hung agent CLI would
# hang the caller's turn, and the caller continues either way.
test_a_missing_timeout_binary_does_not_run_the_agent_unbounded() {
  only_agents claude opencode
  stub_agent opencode "SHOULD NOT RUN"
  unstub timeout
  unstub gtimeout
  outsider ask --host claude <<< "question"
  assert_eq 0 "$STATUS" "exit status"
  assert_not_contains "$STDOUT" "SHOULD NOT RUN" "output"
}

# gtimeout is the macOS-with-coreutils spelling, and has to be used when it is the
# only one present.
test_gtimeout_is_used_when_timeout_is_absent() {
  only_agents claude opencode
  stub_agent opencode
  unstub timeout
  stub gtimeout <<'EOF'
# Drop the duration argument and run the rest, the way real gtimeout would.
shift
exec "$@"
EOF
  outsider ask --host claude <<< "question"
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "ANSWER from opencode" "output"
  assert_not_contains "$STDOUT" "is on PATH" "output"
}

# `list` is the diagnostic mode, so a missing timeout has to be visible there
# rather than only at the moment an agent fails to run.
test_list_reports_a_missing_timeout_binary() {
  only_agents codex claude
  unstub timeout
  unstub gtimeout
  outsider list --host claude
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "timeout: MISSING" "list output"
}

test_list_does_not_mention_timeout_when_it_is_present() {
  only_agents codex claude
  outsider list --host claude
  assert_not_contains "$STDOUT" "timeout: MISSING" "list output"
}

test_an_unknown_mode_is_reported_without_failing() {
  only_agents claude opencode
  outsider frobnicate --host claude
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "Unknown mode: frobnicate" "output"
}

# ANSI escapes from an agent's TUI would otherwise land in the caller's report.
test_ansi_escapes_are_stripped_from_the_answer() {
  only_agents claude opencode
  stub opencode <<'EOF'
cat > /dev/null
printf '\033[1;32mCLEAN-TEXT\033[0m\n'
EOF
  outsider ask --host claude <<< "question"
  assert_contains "$STDOUT" "CLEAN-TEXT" "output"
  assert_not_contains "$STDOUT" "[1;32m" "output"
}

run_tests
