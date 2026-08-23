#!/usr/bin/env bash
# assert.sh — case runner and assertions for the bundled-script test suite.
#
# A test file sources this, defines `test_*` functions, and calls `run_tests`.
# Each case runs in its own subshell inside its own sandbox directory, so a
# failure or a stray `cd` cannot leak into the next one.
#
# Written for bash 3.2 (stock macOS): no associative arrays, no `mapfile`,
# no `${var,,}`, no `[[ -v ]]`.

# 77 is the case-was-skipped signal, matching autotools convention.
SKIP_EXIT=77

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && cd .. && pwd)}"
export REPO_ROOT

# --------------------------------------------------------------- assertions --
# Every assertion writes to stderr and exits the case subshell, so the first
# failure is the one reported and nothing after it runs.

fail() {
  echo "  assertion failed: $*" >&2
  exit 1
}

skip() {
  echo "  skipped: $*" >&2
  exit "$SKIP_EXIT"
}

assert_eq() {
  local expected="$1" actual="$2" what="${3:-value}"
  if [ "$expected" != "$actual" ]; then
    fail "$what
    expected: [$expected]
    actual:   [$actual]"
  fi
}

assert_ne() {
  local unexpected="$1" actual="$2" what="${3:-value}"
  if [ "$unexpected" = "$actual" ]; then
    fail "$what should not be [$unexpected]"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" what="${3:-output}"
  case "$haystack" in
    *"$needle"*) ;;
    *) fail "$what does not contain [$needle]
    actual:   [$haystack]" ;;
  esac
}

assert_not_contains() {
  local haystack="$1" needle="$2" what="${3:-output}"
  case "$haystack" in
    *"$needle"*) fail "$what unexpectedly contains [$needle]
    actual:   [$haystack]" ;;
  esac
}

assert_one_of() {
  local actual="$1"; shift
  local candidate
  for candidate in "$@"; do
    if [ "$candidate" = "$actual" ]; then return 0; fi
  done
  fail "value [$actual] is none of: $*"
}

assert_file() {
  [ -f "$1" ] || fail "expected a regular file at [$1]"
}

assert_no_file() {
  [ ! -e "$1" ] || fail "expected nothing at [$1], found $(ls -ld "$1")"
}

assert_symlink_to() {
  local path="$1" want="$2"
  [ -L "$path" ] || fail "[$path] is not a symlink"
  assert_eq "$want" "$(readlink "$path")" "symlink target of $path"
}

# ------------------------------------------------------------------- capture --
# `run` executes a command with stdout and stderr captured separately and the
# exit status recorded, without tripping the caller's `set -e`.
#
#   run some-script.sh --flag
#   assert_eq 2 "$STATUS"
#   assert_eq main "$(last_line "$STDOUT")"
STDOUT=""
STDERR=""
STATUS=0

run() {
  local out_file err_file
  out_file="$(mktemp "${TMPDIR:-/tmp}/assert-out.XXXXXX")"
  err_file="$(mktemp "${TMPDIR:-/tmp}/assert-err.XXXXXX")"
  STATUS=0
  "$@" >"$out_file" 2>"$err_file" || STATUS=$?
  STDOUT="$(cat "$out_file")"
  STDERR="$(cat "$err_file")"
  rm -f "$out_file" "$err_file"
  return 0
}

# The scripts under test put their machine-readable answer on the last stdout
# line and their commentary on stderr, so this is the value a caller consumes.
last_line() {
  printf '%s' "$1" | tail -n 1
}

# ------------------------------------------------------------------- runner --
# `setup` and `teardown`, if a test file defines them, run inside each case's
# subshell around the case body.

_TESTS_RUN=0
_TESTS_FAILED=0
_TESTS_SKIPPED=0
_FAILED_NAMES=""

_case_sandbox() {
  mktemp -d "${TMPDIR:-/tmp}/skilltest.XXXXXX"
}

run_tests() {
  local names name sandbox log rc
  names="$(declare -F | sed 's/^declare -f //' | grep '^test_' | sort)"

  if [ -z "$names" ]; then
    echo "  no test_* functions found in $0" >&2
    return 1
  fi

  for name in $names; do
    _TESTS_RUN=$((_TESTS_RUN + 1))
    sandbox="$(_case_sandbox)"
    log="$sandbox.log"

    rc=0
    (
      set -e
      # A sandbox-local TMPDIR keeps every temp file a script creates inside the
      # directory this case owns, so nothing survives the case.
      TMPDIR="$sandbox"
      export TMPDIR
      HOME="$sandbox/home"
      export HOME
      mkdir -p "$HOME"
      # The host environment must not reach a case. Every variable the scripts
      # under test consult is neutralized here, so a run is identical on a
      # laptop, inside an agent harness that exports CLAUDECODE, and on CI —
      # where XDG_CONFIG_HOME is set and three config cases failed because the
      # fixture wrote to $HOME/.config while the script read somewhere else.
      XDG_CONFIG_HOME="$HOME/.config"
      export XDG_CONFIG_HOME
      unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT CODEX_SANDBOX \
            CODEX_SANDBOX_NETWORK_DISABLED OPENCODE OPENCODE_BIN_PATH
      # A leaked GIT_DIR or GIT_WORK_TREE would point every fixture at the real
      # repository instead of the sandbox.
      unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY
      # OUTSIDER_* is configuration, and the environment outranks the config
      # file, so one exported by the developer would silently win.
      for _leaked in $(env | sed -n 's/^\(OUTSIDER_[A-Za-z0-9_]*\)=.*/\1/p'); do
        unset "$_leaked"
      done
      # Fixtures anchor stub directories here rather than at $PWD, so a stub dir
      # never lands inside a fixture repo and show up as an untracked change.
      SANDBOX="$sandbox"
      export SANDBOX
      cd "$sandbox"
      if declare -F setup >/dev/null; then setup; fi
      "$name"
      if declare -F teardown >/dev/null; then teardown; fi
    ) >"$log" 2>&1 || rc=$?

    if [ "$rc" -eq 0 ]; then
      echo "  ok       ${name#test_}"
    elif [ "$rc" -eq "$SKIP_EXIT" ]; then
      _TESTS_SKIPPED=$((_TESTS_SKIPPED + 1))
      echo "  skip     ${name#test_}"
      sed 's/^/           /' "$log"
    else
      _TESTS_FAILED=$((_TESTS_FAILED + 1))
      _FAILED_NAMES="$_FAILED_NAMES ${name#test_}"
      echo "  FAIL     ${name#test_} (exit $rc)"
      sed 's/^/           /' "$log"
    fi

    rm -rf "$sandbox" "$log"
  done

  echo "  -- $_TESTS_RUN run, $_TESTS_FAILED failed, $_TESTS_SKIPPED skipped"
  [ "$_TESTS_FAILED" -eq 0 ]
}
