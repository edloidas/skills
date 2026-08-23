#!/usr/bin/env bash
# fixture.sh — throwaway git repos and stub binaries for script tests.
#
# Everything is built inside the current directory, which the case runner has
# already pointed at a fresh sandbox. Nothing here touches the real repo, the
# real $HOME, or the network.

# ----------------------------------------------------------------- git repos --

# A commit's identity, date, and signing are all pinned so a run is
# reproducible and never prompts for a GPG passphrase.
git_env() {
  GIT_AUTHOR_NAME="Test"
  GIT_AUTHOR_EMAIL="test@example.com"
  GIT_COMMITTER_NAME="Test"
  GIT_COMMITTER_EMAIL="test@example.com"
  export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
}

# Fixed clock. Callers that need two commits in the same second simply do not
# advance it — see `git_commit_same_second`.
FIXTURE_CLOCK=1700000000

_git_dates() {
  GIT_AUTHOR_DATE="$FIXTURE_CLOCK +0000"
  GIT_COMMITTER_DATE="$FIXTURE_CLOCK +0000"
  export GIT_AUTHOR_DATE GIT_COMMITTER_DATE
}

# init_repo [dir] [default-branch]
# A repo with no remote, no signing, and a deterministic default branch name.
# `git init -b` is 2.28+, so the branch is set through symbolic-ref instead.
init_repo() {
  local dir="${1:-repo}" branch="${2:-main}"
  git_env
  mkdir -p "$dir"
  git -C "$dir" init --quiet
  git -C "$dir" symbolic-ref HEAD "refs/heads/$branch"
  git -C "$dir" config user.name Test
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config commit.gpgsign false
  git -C "$dir" config tag.gpgsign false
  git -C "$dir" config core.hooksPath /dev/null
  git -C "$dir" config advice.detachedHead false
}

# commit <message> [file] [content]
# Advances the fixture clock by a minute first, so ordinary commits are
# distinguishable by timestamp and only the deliberate cases tie.
commit() {
  local msg="$1" file="${2:-file.txt}" content="${3:-$1}"
  FIXTURE_CLOCK=$((FIXTURE_CLOCK + 60))
  _git_dates
  mkdir -p "$(dirname "$file")"
  printf '%s\n' "$content" >> "$file"
  git add "$file"
  git commit --quiet -m "$msg"
}

# commit_same_second <message> [file] [content]
# Commits without advancing the clock. Two of these produce commits whose
# committer timestamps are identical, which is the tie that made a
# timestamp-ordered base detection pick the wrong branch.
commit_same_second() {
  local msg="$1" file="${2:-file.txt}" content="${3:-$1}"
  _git_dates
  mkdir -p "$(dirname "$file")"
  printf '%s\n' "$content" >> "$file"
  git add "$file"
  git commit --quiet -m "$msg"
}

# add_remote [default-branch]
# A bare repo alongside the work tree, wired up as `origin`, with every local
# branch pushed and refs/remotes/origin/HEAD pointing at the default branch —
# the state a real clone is in, and what base detection reads when `gh` is
# unavailable.
add_remote() {
  local branch="${1:-main}" bare="$PWD/../origin.git"
  git init --quiet --bare "$bare"
  git remote add origin "$bare"
  git push --quiet origin --all
  git fetch --quiet origin
  git symbolic-ref "refs/remotes/origin/HEAD" "refs/remotes/origin/$branch"
}

# push_branch <branch>
# Publishes one branch and refreshes its remote-tracking ref.
push_branch() {
  git push --quiet origin "$1:$1"
  git fetch --quiet origin
}

# ------------------------------------------------------------------- stubs ----
# `stub_path` replaces PATH with a sandbox-local pair of directories: one for
# stubs, one holding symlinks to a fixed list of core tools. That isolation is
# what makes "not installed" testable — a script probes with `command -v`, which
# walks PATH in order and skips non-executable matches, so a shadowing entry
# cannot hide a real binary further down. Removing the real directories can.
#
# Anything a script under test shells out to has to be either stubbed or listed
# in CORE_TOOLS; a missing entry surfaces as a loud failure, not a silent skip.
CORE_TOOLS="sh bash env printf true false expr test
git jq sed awk grep cut tr head tail sort uniq wc
cat ls mkdir rmdir rm mv cp ln readlink realpath dirname basename
mktemp find xargs date seq sleep timeout gtimeout tee diff chmod stat touch"

STUB_DIR=""
CORE_BIN=""

stub_path() {
  if [ -z "$STUB_DIR" ]; then
    STUB_DIR="${SANDBOX:-$PWD}/.stubs"
    CORE_BIN="${SANDBOX:-$PWD}/.corebin"
    mkdir -p "$STUB_DIR" "$CORE_BIN"
    local tool resolved
    for tool in $CORE_TOOLS; do
      resolved="$(command -v "$tool" 2>/dev/null)" || continue
      ln -sf "$resolved" "$CORE_BIN/$tool"
    done
    PATH="$STUB_DIR:$CORE_BIN"
    export PATH
  fi
  printf '%s' "$STUB_DIR"
}

# stub <name> <<'EOF' ... EOF
# Writes an executable stub from stdin. The body is a bash script; "$@" holds
# whatever the script under test passed.
stub() {
  local name="$1"
  # Called directly, not in a command substitution: `stub_path` exports PATH and
  # a subshell would drop the export while still looking like it worked.
  stub_path > /dev/null
  local dir="$STUB_DIR"
  {
    echo '#!/usr/bin/env bash'
    cat
  } > "$dir/$name"
  chmod +x "$dir/$name"
}

# stub_recording <name>
# A stub that appends its full argument list to `$PWD/<name>.calls` and exits 0,
# so a test can assert on how a script invoked it.
stub_recording() {
  local name="$1"
  stub "$name" <<EOF
printf '%s\n' "\$*" >> "${SANDBOX:-$PWD}/$name.calls"
exit 0
EOF
}

# calls_of <name>
# The recorded invocations of a recording stub, one per line, or empty if the
# stub was never called.
calls_of() {
  cat "${SANDBOX:-$PWD}/$1.calls" 2>/dev/null || true
}

# unstub <name>
# Makes a binary look uninstalled. Only meaningful once PATH is isolated, which
# `stub_path` guarantees.
unstub() {
  stub_path > /dev/null
  rm -f "$STUB_DIR/$1" "$CORE_BIN/$1"
}

# only_agents [name ...]
# Pins exactly which agent CLIs `run-outsider.sh` believes are installed: the
# named ones get a no-op stub, every other one is removed from PATH. Called with
# no names, every agent looks uninstalled.
#
# A named agent that a case wants to behave a particular way is re-stubbed
# afterwards with `stub` or `stub_agent`, which overwrites the no-op.
only_agents() {
  local keep=" $* " agent
  stub_path > /dev/null
  for agent in codex claude opencode pi; do
    case "$keep" in
      *" $agent "*)
        stub "$agent" <<'EOF'
cat > /dev/null
EOF
        ;;
      *) unstub "$agent" ;;
    esac
  done
}

# stub_gh_default_branch <branch>
# The only `gh` call base detection makes. Any other subcommand fails, so a
# script that grew a second call would surface rather than silently pass.
stub_gh_default_branch() {
  stub gh <<EOF
if [ "\$1" = "repo" ] && [ "\$2" = "view" ]; then
  printf '%s\n' "$1"
  exit 0
fi
echo "stub gh: unexpected invocation: \$*" >&2
exit 1
EOF
}

# no_gh
# `gh` absent — the state on a machine with no GitHub CLI, and the path where
# base detection has to fall back to refs/remotes/origin/HEAD.
no_gh() {
  unstub gh
}

# script <path-relative-to-repo-root>
# Absolute path to a bundled script, so a case can `run` it from any directory.
script() {
  printf '%s/%s' "$REPO_ROOT" "$1"
}
