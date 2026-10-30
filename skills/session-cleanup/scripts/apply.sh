#!/usr/bin/env bash
# apply.sh — act on a report written by scan.sh. Destructive: kills processes,
# removes git worktrees and branches, deletes session files.
#
# Usage:
#   apply.sh <processes|git|files|all> <report.tsv> [--only <id>]...
#
# Only rows of the report are candidates, and each one is re-checked against a
# fresh scan.sh run with the report's own dirs and flags before anything happens:
#   - a row missing from the fresh scan is skipped (it changed or went away)
#   - risk `never` is always refused
#   - risk `named` needs its id passed with --only
#   - risk `safe` is acted on, unless --only is given and does not name it, or
#     the report showed the row as anything but `safe` and its id is not named
#   - a file row must sit exactly two levels under a known root
#   - an --only id that is no row of the requested kind is a `fail ... unknown id`
#
# Processes get SIGTERM, then SIGKILL for survivors after a second. Right before
# each signal the PID's start time is read again and compared with the id
# (`<pid>@<start>`), so a PID reused since the scan is never signalled.
# Worktrees go through `git worktree remove` (`--force` only for a named dirty
# one) or `git worktree prune`; branches through `git branch -D`.
#
# Output: one `done|skip|fail <kind> <id> <reason>` line per row, then
# `applied N, skipped N, failed N`. Exit codes: 0 nothing failed, 1 a row
# failed, 2 usage error.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
TAB="$(printf '\t')"

usage() { echo "usage: apply.sh <processes|git|files|all> <report.tsv> [--only <id>]..." >&2; exit 2; }

[ "$#" -ge 2 ] || usage
KIND="$1"; REPORT="$2"; shift 2
case "$KIND" in processes|git|files|all) ;; *) usage ;; esac
[ -r "$REPORT" ] || { echo "apply: cannot read report: $REPORT" >&2; exit 2; }

ONLY=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --only) [ -n "${2:-}" ] || usage; ONLY="$ONLY$2
"; shift 2 ;;
    *) usage ;;
  esac
done

named() { [ -n "$ONLY" ] && printf '%s' "$ONLY" | grep -Fxq -- "$1"; }

selected() {  # row kind -> 0 if the requested kind covers it
  case "$KIND:$1" in
    all:*|processes:process|git:branch|git:worktree|files:file) return 0 ;;
  esac
  return 1
}

# Re-run the scan the report came from: same dirs, same gh and age settings.
set --
[ "$KIND" = all ] || set -- "$KIND"
if awk -F'\t' '$1 == "scan" && $3 == "gh=off" { f = 1 } END { exit !f }' "$REPORT"; then set -- "$@" --no-gh; fi
age="$(awk -F'\t' '$1 == "scan" { sub(/^min_age_days=/, "", $4); print $4; exit }' "$REPORT")"
case "$age" in ''|*[!0-9]*) ;; *) set -- "$@" --min-age-days "$age" ;; esac
while IFS="$TAB" read -r tag dir; do
  [ "$tag" = dir ] && [ -d "$dir" ] && set -- "$@" "$dir"
done < "$REPORT"

FRESH="$(mktemp "${TMPDIR:-/tmp}/session-apply.XXXXXX")"
trap 'rm -f "$FRESH"' EXIT
bash "$HERE/scan.sh" "$@" > "$FRESH" || { echo "apply: fresh scan failed" >&2; exit 1; }
ROOTS="$(bash "$HERE/scan.sh" --print-roots)"

under_root() {  # path -> 0 if it is <root>/<a>/<b> for a known root, no dot segments
  case "/$1/" in */../*|*/./*) return 1 ;; esac
  printf '%s\n' "$ROOTS" | while IFS= read -r root; do
    [ -n "$root" ] || continue
    rest="${1#"$root"/}"
    [ "$rest" != "$1" ] || continue
    case "$rest" in */*/*|'') ;; */*) echo yes; break ;; esac
  done | grep -q yes
}

DONE=0; SKIPPED=0; FAILED=0
KILL_IDS=""
say() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"; }
skip() { say skip "$1" "$2" "$3"; SKIPPED=$((SKIPPED + 1)); }
ok() { say done "$1" "$2" "$3"; DONE=$((DONE + 1)); }
bad() { say fail "$1" "$2" "$3"; FAILED=$((FAILED + 1)); }

ROWS="$(awk -F'\t' 'NF == 7 && ($1 == "process" || $1 == "branch" || $1 == "worktree" || $1 == "file")' "$REPORT")"

# A mistyped id would otherwise match nothing and vanish from the tally.
while IFS= read -r want; do
  [ -n "$want" ] || continue
  printf '%s\n' "$ROWS" | awk -F'\t' -v i="$want" -v k="$KIND" '$6 == i && (k == "all" ||
      (k == "processes" && $1 == "process") || (k == "git" && ($1 == "branch" || $1 == "worktree")) ||
      (k == "files" && $1 == "file")) { f = 1 } END { exit !f }' \
    || bad "$KIND" "$want" "unknown id: no $KIND row in the report has it"
done <<EOF
$ONLY
EOF

while IFS="$TAB" read -r kind owner age size risk id detail; do
  [ -n "$kind" ] || continue
  selected "$kind" || continue
  if [ -n "$ONLY" ] && ! named "$id"; then continue; fi

  if [ "$kind" = file ] && ! under_root "$id"; then
    skip "$kind" "$id" "refused: outside the known roots"
    continue
  fi

  fresh="$(awk -F'\t' -v k="$kind" -v i="$id" '$1 == k && $6 == i { print $5 "\t" $7; exit }' "$FRESH")"
  frisk="${fresh%%"$TAB"*}"; fdetail="${fresh#*"$TAB"}"
  if [ -z "$fresh" ]; then skip "$kind" "$id" "not in a fresh scan: changed or gone"; continue; fi
  if [ "$frisk" = never ]; then skip "$kind" "$id" "refused: $fdetail"; continue; fi
  if [ "$frisk" = named ] && ! named "$id"; then skip "$kind" "$id" "needs its id named with --only: $fdetail"; continue; fi
  # The user approved what the report showed; a row that became safe since was not shown as safe.
  if [ "$risk" != safe ] && ! named "$id"; then skip "$kind" "$id" "was $risk in the report; name its id with --only"; continue; fi

  case "$kind" in
    process)
      KILL_IDS="$KILL_IDS $id" ;;
    worktree)
      repo="${id%%|*}"; path="${id#*|}"
      case "$fdetail" in
        prunable*) if git -C "$repo" worktree prune 2>/dev/null; then ok "$kind" "$id" "pruned"; else bad "$kind" "$id" "git worktree prune failed"; fi ;;
        *)
          force=""; [ "$frisk" = named ] && force="--force"
          if err="$(git -C "$repo" worktree remove $force "$path" 2>&1)"; then ok "$kind" "$id" "removed"; else bad "$kind" "$id" "$err"; fi ;;
      esac ;;
    branch)
      repo="${id%%|*}"; br="${id#*|}"
      if err="$(git -C "$repo" branch -D "$br" 2>&1)"; then ok "$kind" "$id" "deleted"; else bad "$kind" "$id" "$err"; fi ;;
    file)
      if rm -rf -- "$id"; then ok "$kind" "$id" "deleted"; else bad "$kind" "$id" "rm failed"; fi ;;
  esac
done <<EOF
$ROWS
EOF

start_of() {  # pid -> its start time in the id's `Day-Mon-D-HH:MM:SS-YYYY` form, empty when gone
  ps -o lstart= -p "$1" 2>/dev/null | awk 'NF >= 5 { printf "%s-%s-%s-%s-%s", $1, $2, $3, $4, $5; exit }'
}

if [ -n "$KILL_IDS" ]; then
  TERMED=""
  for id in $KILL_IDS; do
    now="$(start_of "${id%%@*}")"
    if [ -z "$now" ]; then ok process "$id" "already gone"
    elif [ "$now" != "${id#*@}" ]; then skip process "$id" "pid reused: now started $now"
    else kill -TERM "${id%%@*}" 2>/dev/null; TERMED="$TERMED $id"
    fi
  done
  if [ -n "$TERMED" ]; then
    sleep 1
    for id in $TERMED; do
      [ "$(start_of "${id%%@*}")" = "${id#*@}" ] && kill -KILL "${id%%@*}" 2>/dev/null
    done
    sleep 1
    for id in $TERMED; do
      now="$(start_of "${id%%@*}")"
      if [ "$now" = "${id#*@}" ]; then bad process "$id" "still running after SIGKILL"
      elif [ -n "$now" ]; then ok process "$id" "killed (pid reused since, not signalled again)"
      else ok process "$id" "killed"
      fi
    done
  fi
fi

echo "applied $DONE, skipped $SKIPPED, failed $FAILED"
[ "$FAILED" -eq 0 ]
