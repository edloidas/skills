#!/usr/bin/env bash
set -euo pipefail

# agent-config.sh — inspect and wire a repository's agent instruction files.
#
# One real instruction file at the repo root, every other host filename a
# relative symlink pointing at it, so all agents read the same document.
#
# Subcommands:
#   status              Report the state of every known instruction file
#   link <name> ...     Point <name> at the canonical file as a relative symlink
#
# Exit codes:
#   0  success / everything consistent
#   1  usage or operational error
#   2  cannot determine a canonical instruction file
#   3  status found drift (missing, broken, or misdirected links)

usage() {
  cat <<'USAGE'
Usage:
  agent-config.sh status [--canonical <file>]
  agent-config.sh link <name> [<name> ...] [--canonical <file>] [--dry-run] [--force]

Known link names:
  AGENTS.md                          Codex, OpenCode, pi, Cursor, Amp, Jules
  GEMINI.md                          Gemini CLI
  .github/copilot-instructions.md    GitHub Copilot

Flags:
  --canonical <file>  Real instruction file to link against (default: auto-detect
                      CLAUDE.md, then AGENTS.md)
  --dry-run           Print the plan and exit without writing
  --force             Move an existing regular file to <name>.bak before linking
  -h, --help          This message
USAGE
}

KNOWN_NAMES=(
  "CLAUDE.md"
  "AGENTS.md"
  "GEMINI.md"
  ".github/copilot-instructions.md"
)

CANONICAL=""
DRY_RUN=0
FORCE=0
COMMAND=""
TARGETS=()

die() {
  echo "error: $*" >&2
  exit 1
}

# Auto-detect the real instruction file. CLAUDE.md wins when both are regular
# files only if the other is a symlink; two independent regular files are a
# conflict the caller has to resolve.
detect_canonical() {
  local claude_real=0 agents_real=0
  [ -f "CLAUDE.md" ] && [ ! -L "CLAUDE.md" ] && claude_real=1
  [ -f "AGENTS.md" ] && [ ! -L "AGENTS.md" ] && agents_real=1

  if [ "$claude_real" -eq 1 ] && [ "$agents_real" -eq 1 ]; then
    echo "error: CLAUDE.md and AGENTS.md are both regular files" >&2
    echo "       Decide which one is authoritative, then re-run with --canonical <file>." >&2
    exit 2
  fi

  if [ "$claude_real" -eq 1 ]; then
    echo "CLAUDE.md"
  elif [ "$agents_real" -eq 1 ]; then
    echo "AGENTS.md"
  else
    echo "error: no regular CLAUDE.md or AGENTS.md at the repo root" >&2
    echo "       Write the instruction file first, then re-run." >&2
    exit 2
  fi
}

# Relative path from <name>'s directory back to the repo root, e.g.
# ".github/copilot-instructions.md" -> "../CLAUDE.md"
relative_target() {
  local name="$1" dir prefix=""
  dir=$(dirname "$name")
  if [ "$dir" != "." ]; then
    local IFS='/'
    # shellcheck disable=SC2086
    for _ in $dir; do prefix="../$prefix"; done
  fi
  printf '%s%s\n' "$prefix" "$CANONICAL"
}

# Classifies one instruction file.
#   0  consistent
#   1  drift — broken, misdirected, or a duplicate regular file
#   2  missing
describe() {
  local name="$1" want
  want=$(relative_target "$name")

  if [ "$name" = "$CANONICAL" ]; then
    printf '  %-32s canonical (real file)\n' "$name"
    return 0
  fi

  if [ -L "$name" ]; then
    local actual
    actual=$(readlink "$name")
    if [ ! -e "$name" ]; then
      printf '  %-32s BROKEN symlink -> %s\n' "$name" "$actual"
      return 1
    fi
    if [ "$actual" != "$want" ]; then
      printf '  %-32s symlink -> %s (expected %s)\n' "$name" "$actual" "$want"
      return 1
    fi
    printf '  %-32s symlink -> %s\n' "$name" "$actual"
    return 0
  fi

  if [ -e "$name" ]; then
    printf '  %-32s REGULAR FILE (duplicates the canonical file)\n' "$name"
    return 1
  fi

  printf '  %-32s missing\n' "$name"
  return 2
}

# AGENTS.md and CLAUDE.md are two halves of the same document, so whichever is not
# canonical has to be a link. GEMINI.md and copilot-instructions.md are opt-in.
is_required() {
  case "$1" in
    CLAUDE.md|AGENTS.md) [ "$1" != "$CANONICAL" ] ;;
    *) return 1 ;;
  esac
}

cmd_status() {
  local drift=0 optional_missing=0 name rc
  echo "Canonical instruction file: $CANONICAL"
  echo
  echo "Instruction files:"
  for name in "${KNOWN_NAMES[@]}"; do
    rc=0
    describe "$name" || rc=$?
    case "$rc" in
      1) drift=1 ;;
      2) if is_required "$name"; then drift=1; else optional_missing=1; fi ;;
    esac
  done
  echo
  if [ "$optional_missing" -eq 1 ]; then
    echo "Optional hosts left unlinked. GEMINI.md and .github/copilot-instructions.md"
    echo "are only worth creating if the repo is actually used with those agents."
    echo
  fi
  if [ "$drift" -eq 1 ]; then
    echo "Drift found."
    return 3
  fi
  echo "Every required instruction file is consistent."
  return 0
}

cmd_link() {
  local name want action blocked=0

  [ "${#TARGETS[@]}" -gt 0 ] || die "link needs at least one name (see --help)"

  echo "Canonical instruction file: $CANONICAL"
  echo

  for name in "${TARGETS[@]}"; do
    [ "$name" != "$CANONICAL" ] || die "$name is the canonical file; it cannot link to itself"
    want=$(relative_target "$name")

    if [ -L "$name" ]; then
      if [ "$(readlink "$name")" = "$want" ] && [ -e "$name" ]; then
        action="identical"
      else
        action="relink"
      fi
    elif [ -e "$name" ]; then
      if [ "$FORCE" -eq 1 ]; then
        action="backup+link"
      else
        action="blocked"
      fi
    else
      action="link"
    fi

    printf '  %-32s %s -> %s\n' "$name" "$action" "$want"

    if [ "$action" = "blocked" ]; then
      blocked=1
      echo "    $name is a regular file. Merge its content into $CANONICAL and delete it," >&2
      echo "    or re-run with --force to move it to $name.bak first." >&2
      continue
    fi

    [ "$DRY_RUN" -eq 0 ] || continue

    case "$action" in
      identical) ;;
      backup+link)
        mv "$name" "$name.bak"
        ln -s "$want" "$name"
        ;;
      relink)
        rm "$name"
        ln -s "$want" "$name"
        ;;
      link)
        mkdir -p "$(dirname "$name")"
        ln -s "$want" "$name"
        ;;
    esac
  done

  if [ "$DRY_RUN" -eq 1 ]; then
    echo
    echo "Dry run — nothing written."
  fi

  [ "$blocked" -eq 0 ] || return 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    status|link)
      [ -z "$COMMAND" ] || die "only one subcommand at a time"
      COMMAND="$1"
      ;;
    --canonical)
      shift
      [ $# -gt 0 ] || die "--canonical needs a file"
      CANONICAL="$1"
      ;;
    --dry-run) DRY_RUN=1 ;;
    --force) FORCE=1 ;;
    -h|--help) usage; exit 0 ;;
    -*) die "unknown flag: $1" ;;
    *) TARGETS+=("$1") ;;
  esac
  shift
done

[ -n "$COMMAND" ] || { usage; exit 1; }

if [ -n "$CANONICAL" ]; then
  [ -f "$CANONICAL" ] || die "--canonical file not found: $CANONICAL"
  [ ! -L "$CANONICAL" ] || die "--canonical file is a symlink: $CANONICAL"
else
  CANONICAL=$(detect_canonical)
fi

case "$COMMAND" in
  status) cmd_status ;;
  link) cmd_link ;;
esac
