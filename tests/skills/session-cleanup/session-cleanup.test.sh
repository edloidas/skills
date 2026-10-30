#!/usr/bin/env bash
# scan.sh and apply.sh — the scan decides what is safe to remove and apply.sh
# deletes and kills on that word, so the cases that matter are the ones where a
# live process, uncommitted work, or a path outside the known roots must be
# left alone.

. "$(dirname "$0")/../../lib/assert.sh"
. "$(dirname "$0")/../../lib/fixture.sh"

SCAN="skills/session-cleanup/scripts/scan.sh"
APPLY="skills/session-cleanup/scripts/apply.sh"

scan() { run bash "$(script "$SCAN")" "$@"; }
apply() { run bash "$(script "$APPLY")" "$@"; }

setup() {
  mkdir -p "$SANDBOX/proc" "$SANDBOX/scratch" "$SANDBOX/state" "$SANDBOX/ps"
  printf 'MemTotal: 8000000 kB\nMemAvailable: 1000000 kB\nSwapTotal: 0 kB\nSwapFree: 0 kB\nShmem: 1600000 kB\n' \
    > "$SANDBOX/proc/meminfo"
  SESSION_CLEANUP_PROC="$SANDBOX/proc"
  SESSION_CLEANUP_SCRATCH_ROOTS="$SANDBOX/scratch"
  SESSION_CLEANUP_STATE_DIR="$SANDBOX/state"
  export SESSION_CLEANUP_PROC SESSION_CLEANUP_SCRATCH_ROOTS SESSION_CLEANUP_STATE_DIR
  : > "$SANDBOX/ps/table"
  # `ps` prints whatever the case wrote to ps/table, in the column order
  # scan.sh asks for: pid ppid uid etime rss lstart(5 words) command.
  # apply.sh's `ps -o lstart= -p <pid>` gets that row's start time while the PID
  # is really alive, or ps/reused-start when a case wrote one.
  stub ps <<EOF
case " \$* " in
  *" -p "*)
    for pid; do :; done
    kill -0 "\$pid" 2>/dev/null || exit 1
    if [ -f "$SANDBOX/ps/reused-start" ]; then cat "$SANDBOX/ps/reused-start"; exit 0; fi
    awk -v p="\$pid" '\$1 == p { print \$6, \$7, \$8, \$9, \$10 }' "$SANDBOX/ps/table" ;;
  *) cat "$SANDBOX/ps/table" ;;
esac
EOF
}

teardown() {
  [ -n "${SLEEPER:-}" ] && kill -KILL "$SLEEPER" 2>/dev/null
  return 0
}

# A real process for the kill path, started in a subshell that exits at once so
# it is reparented and reaped elsewhere: a child of this shell would linger as a
# zombie that `kill -0` still finds.
start_sleeper() {
  SLEEPER="$( (sleep 300 >/dev/null 2>&1 & echo $!) )"
}

# proc <pid> <ppid> <etime> <command...> — one row of the stubbed process table,
# owned by the user running the test.
proc() {
  local pid="$1" ppid="$2" etime="$3"; shift 3
  printf '%s %s %s %s 20480 Thu Oct 29 10:00:00 2026 %s\n' "$pid" "$ppid" "$EUID" "$etime" "$*" \
    >> "$SANDBOX/ps/table"
}

process_row() {  # pid -> the scan's process row for it, or empty
  printf '%s\n' "$STDOUT" | awk -F'\t' -v p="$1" '$1 == "process" && index($6, p "@") == 1'
}

risk_of() { printf '%s' "$1" | cut -f5; }

# ---------------------------------------------------------------- processes ---

test_orphan_under_pid_1_is_safe_with_its_children() {
  proc 1 0 10-00:00:00 /sbin/init
  proc 400 1 02:00:00 node /work/node_modules/.bin/vite-plus dev
  proc 401 400 02:00:00 node /work/node_modules/esbuild/bin/esbuild --service
  scan processes
  assert_eq 0 "$STATUS" "exit status"
  assert_eq safe "$(risk_of "$(process_row 400)")" "vite risk"
  assert_contains "$(process_row 400)" "under pid 1"
  assert_eq safe "$(risk_of "$(process_row 401)")" "child risk"
  assert_contains "$(process_row 401)" "child of vite dev server"
}

# On Linux with a systemd user instance, orphans land under `systemd --user`,
# not PID 1. A PID-1-only root test reported every one of them as live.
test_orphan_under_systemd_user_subreaper_is_safe() {
  proc 1 0 10-00:00:00 /sbin/init
  proc 900 1 10-00:00:00 /usr/lib/systemd/systemd --user --deserialize=18
  proc 950 900 05:00:00 node /home/u/.npm/_npx/x/node_modules/.bin/playwright-mcp
  scan processes
  assert_eq safe "$(risk_of "$(process_row 950)")" "playwright risk"
  assert_contains "$(process_row 950)" "under systemd --user pid 900"
}

test_live_process_is_never_a_candidate() {
  proc 1 0 10-00:00:00 /sbin/init
  proc 900 1 10-00:00:00 /usr/lib/systemd/systemd --user
  proc 910 900 3-00:00:00 /usr/libexec/gnome-terminal-server
  proc 911 910 3-00:00:00 /usr/bin/zsh
  proc 912 911 01:00:00 node /work/node_modules/.bin/vite-plus dev
  scan processes
  assert_eq never "$(risk_of "$(process_row 912)")" "live vite risk"
  assert_contains "$(process_row 912)" "live (root gnome-terminal-server pid 910)"
  assert_eq "" "$(process_row 911)" "unrelated shell row"
}

test_busy_gradle_daemon_needs_a_name() {
  proc 1 0 10-00:00:00 /sbin/init
  proc 700 1 01:00:00 java -cp gradle-launcher.jar org.gradle.launcher.daemon.bootstrap.GradleDaemon 8.10
  proc 710 1 00:30 java -cp gradle-wrapper.jar org.gradle.wrapper.GradleWrapperMain build
  scan processes
  assert_eq named "$(risk_of "$(process_row 700)")" "daemon risk"
  assert_contains "$(process_row 700)" "busy"
}

test_orphaned_process_is_killed() {
  start_sleeper
  proc 1 0 10-00:00:00 /sbin/init
  proc "$SLEEPER" 1 02:00:00 bash -c until false\; do sleep 30\; done
  scan processes
  printf '%s\n' "$STDOUT" > report.tsv
  assert_eq safe "$(risk_of "$(process_row "$SLEEPER")")" "sleeper risk"
  apply processes report.tsv
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "done	process	$SLEEPER@Thu-Oct-29-10:00:00-2026	killed"
  assert_contains "$STDOUT" "applied 1, skipped 0, failed 0"
  if kill -0 "$SLEEPER" 2>/dev/null; then fail "sleeper $SLEEPER is still running"; fi
}

# The fresh scan still lists the row, but by the time of the signal the PID
# belongs to a process started at another time: it must not be signalled.
test_reused_pid_is_not_killed() {
  start_sleeper
  proc 1 0 10-00:00:00 /sbin/init
  proc "$SLEEPER" 1 02:00:00 bash -c until false\; do sleep 30\; done
  scan processes
  printf '%s\n' "$STDOUT" > report.tsv
  printf 'Fri Oct 30 11:00:00 2026\n' > ps/reused-start
  apply processes report.tsv
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "skip	process	$SLEEPER@Thu-Oct-29-10:00:00-2026	pid reused: now started Fri-Oct-30-11:00:00-2026"
  assert_contains "$STDOUT" "applied 0, skipped 1, failed 0"
  kill -0 "$SLEEPER" 2>/dev/null || fail "sleeper $SLEEPER was killed"
}

# ------------------------------------------------------------------- memory ---

test_meminfo_summary_is_reported() {
  scan processes
  assert_contains "$STDOUT" "memory	total=7.6G	available=976M	swap=none	shmem=1.5G"
}

# macOS has no /proc: the summary must say what it could not measure rather
# than print zeros or nothing.
test_missing_proc_degrades_with_not_measured() {
  SESSION_CLEANUP_PROC="$SANDBOX/no-such-proc"
  scan processes
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "available=not measured	swap=not measured	shmem=not measured"
  assert_contains "$STDOUT" "not measured; process liveness for files falls back to age only"
}

# ---------------------------------------------------------------------- git ---

clones() {
  mkdir -p clones
  init_repo clones/app
  cd clones/app
  commit "initial"
  add_remote main
  cd "$SANDBOX"
}

git_row() {  # kind id-suffix -> row
  printf '%s\n' "$STDOUT" | awk -F'\t' -v k="$1" -v s="$2" '$1 == k && substr($6, length($6) - length(s) + 1) == s'
}

# A rebase merge rewrites the SHA, so the branch tip is never an ancestor of
# main and `git branch --merged` misses it. `git cherry` matches by patch.
test_rebase_merged_branch_is_found_by_cherry() {
  clones
  cd clones/app
  git checkout --quiet -b triage/12
  commit "fix" fix.txt
  git checkout --quiet main
  FIXTURE_CLOCK=$((FIXTURE_CLOCK + 600)); _git_dates
  git cherry-pick --quiet triage/12 >/dev/null
  git push --quiet origin main
  if git merge-base --is-ancestor triage/12 main; then fail "fixture: branch must not be an ancestor"; fi
  cd "$SANDBOX"
  scan git --no-gh clones
  assert_eq safe "$(risk_of "$(git_row branch '|triage/12')")" "branch risk"
  assert_contains "$(git_row branch '|triage/12')" "merged: every commit has an equivalent patch on origin/main"
}

# A branch cut a minute ago from an old main has no unique patch and an old tip
# date, and must not be batch-deleted as "merged".
test_fresh_branch_off_old_tip_is_named_not_safe() {
  clones
  ( unset GIT_COMMITTER_DATE; git -C clones/app branch agent/next )
  scan git --no-gh clones
  assert_eq named "$(risk_of "$(git_row branch '|agent/next')")" "branch risk"
  assert_contains "$(git_row branch '|agent/next')" "active within 1d"
}

test_dirty_worktree_is_named_and_refused_by_batch_apply() {
  clones
  git -C clones/app worktree add --quiet -b agent-1 "$SANDBOX/clones/app/.wt/agent-1"
  printf 'unsaved\n' > clones/app/.wt/agent-1/work.txt
  scan git --no-gh --min-age-days 0 clones
  printf '%s\n' "$STDOUT" > report.tsv
  assert_eq named "$(risk_of "$(git_row worktree '/.wt/agent-1')")" "worktree risk"
  assert_contains "$(git_row worktree '/.wt/agent-1')" "dirty: 1 uncommitted change(s)"

  apply git report.tsv
  assert_eq 0 "$STATUS" "exit status"
  assert_contains "$STDOUT" "needs its id named with --only"
  assert_contains "$STDOUT" "applied 0, skipped 1, failed 0"
  assert_file clones/app/.wt/agent-1/work.txt
}

test_clean_worktree_is_removed_and_its_branch_kept() {
  clones
  git -C clones/app worktree add --quiet -b agent-2 "$SANDBOX/clones/app/.wt/agent-2"
  scan git --no-gh --min-age-days 0 clones
  printf '%s\n' "$STDOUT" > report.tsv
  assert_eq safe "$(risk_of "$(git_row worktree '/.wt/agent-2')")" "worktree risk"
  apply git report.tsv
  assert_contains "$STDOUT" "applied 1, skipped 0, failed 0"
  assert_no_file clones/app/.wt/agent-2
  git -C clones/app show-ref --verify -q refs/heads/agent-2 || fail "branch agent-2 was deleted"
}

# Without /proc nothing says whether a shell sits in the worktree, so a clean
# old worktree cannot be batch-removed on age alone.
test_clean_worktree_without_proc_is_named() {
  clones
  git -C clones/app worktree add --quiet -b agent-3 "$SANDBOX/clones/app/.wt/agent-3"
  SESSION_CLEANUP_PROC="$SANDBOX/no-such-proc"
  scan git --no-gh --min-age-days 0 clones
  assert_eq named "$(risk_of "$(git_row worktree '/.wt/agent-3')")" "worktree risk"
  assert_contains "$(git_row worktree '/.wt/agent-3')" "cannot tell whether a process holds it open"
}

# The batch approves what the user saw. A row the report showed as named that
# a fresh scan now calls safe was never approved as part of the batch.
test_row_named_in_the_report_is_not_batch_applied_when_it_turns_safe() {
  clones
  git -C clones/app worktree add --quiet -b agent-5 "$SANDBOX/clones/app/.wt/agent-5"
  scan git --no-gh --min-age-days 0 clones
  printf '%s\n' "$STDOUT" | awk -F'\t' -v OFS='\t' '$1 == "worktree" { $5 = "named" } { print }' > report.tsv
  apply git report.tsv
  assert_contains "$STDOUT" "was named in the report; name its id with --only"
  assert_contains "$STDOUT" "applied 0, skipped 1, failed 0"
  [ -d clones/app/.wt/agent-5 ] || fail "worktree agent-5 was removed"
}

test_mistyped_only_id_fails_in_the_tally() {
  clones
  git -C clones/app worktree add --quiet -b agent-4 "$SANDBOX/clones/app/.wt/agent-4"
  scan git --no-gh --min-age-days 0 clones
  printf '%s\n' "$STDOUT" > report.tsv
  apply git report.tsv --only "$SANDBOX/clones/app|$SANDBOX/clones/app/.wt/agent-44"
  assert_eq 1 "$STATUS" "exit status"
  assert_contains "$STDOUT" "unknown id: no git row in the report has it"
  assert_contains "$STDOUT" "applied 0, skipped 0, failed 1"
  [ -d clones/app/.wt/agent-4 ] || fail "worktree agent-4 was removed"
}

# -------------------------------------------------------------------- files ---

session_dir() {  # slug uuid -> creates an idle session scratch dir, returns path
  local d="$SANDBOX/scratch/$1/$2"
  mkdir -p "$d/scratchpad"
  printf 'x\n' > "$d/scratchpad/notes.txt"
  find "$d" -exec touch -t 202001010000 {} +
  printf '%s' "$d"
}

test_file_outside_known_roots_is_refused() {
  mkdir -p elsewhere/keep
  printf 'precious\n' > elsewhere/keep/data.txt
  printf 'scan\tkind=files\tgh=off\tmin_age_days=1\tproc=present\n' > report.tsv
  printf 'file\tscratchpad x\t9d\t4K\tsafe\t%s\tforged\n' "$SANDBOX/elsewhere/keep" >> report.tsv
  apply files report.tsv
  assert_contains "$STDOUT" "refused: outside the known roots"
  assert_file elsewhere/keep/data.txt
}

test_idle_scratchpad_is_deleted_and_recent_one_kept() {
  old="$(session_dir -home-u-repo 11111111-2222-3333-4444-555555555555)"
  new="$SANDBOX/scratch/-home-u-repo/66666666-7777-8888-9999-000000000000"
  mkdir -p "$new"
  printf 'y\n' > "$new/fresh.txt"
  scan files
  printf '%s\n' "$STDOUT" > report.tsv
  apply files report.tsv
  assert_contains "$STDOUT" "applied 1, skipped 1, failed 0"
  assert_no_file "$old"
  assert_file "$new/fresh.txt"
}

test_closed_orchestrate_run_is_safe_and_open_one_unlisted() {
  mkdir -p state/proj/20260101-0000 state/proj/20260102-0000
  printf '{"status": "closed", "units": [{"status": "done"}]}\n' > state/proj/20260101-0000/run.json
  printf '{"status": "running"}\n' > state/proj/20260102-0000/run.json
  scan files
  assert_contains "$STDOUT" "safe	$SANDBOX/state/proj/20260101-0000	orchestrate run closed"
  assert_not_contains "$STDOUT" "20260102-0000"
}

run_tests
