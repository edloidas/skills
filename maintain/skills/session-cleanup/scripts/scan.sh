#!/usr/bin/env bash
# scan.sh — read-only report of what agent and dev sessions left behind on this
# machine: a memory summary, then leftover processes, git branches and
# worktrees, and session files. It changes nothing; apply.sh acts on its output.
#
# Usage:
#   scan.sh [processes|git|files|all] [--no-gh] [--min-age-days N] [dir ...]
#   scan.sh --print-roots          the file roots apply.sh may delete under
#
# <dir> is a parent of git clones (each child with a .git directory is scanned)
# or a clone itself. Default: the parent of the current clone, else the cwd.
#
# Output is TAB-separated. Header rows: scan, dir, memory, tmpfs, top, note.
# Then a `kind owner age size risk id detail` row per candidate, where risk is
#   safe   removable in a batch
#   named  removable only when its id is named explicitly
#   never  reported, never touched
# and a closing `summary` row.
#
# Environment (defaults in brackets):
#   SESSION_CLEANUP_PROC            [/proc]
#   SESSION_CLEANUP_CATALOG         [<skill>/assets/catalog.tsv]
#   SESSION_CLEANUP_SCRATCH_ROOTS   [/tmp/claude-<uid>, $TMPDIR/claude-<uid>] colon-separated
#   SESSION_CLEANUP_STATE_DIR       [${XDG_STATE_HOME:-~/.local/state}/orchestrate]
#   CLAUDE_CONFIG_DIR               [~/.claude] where session transcripts live
#
# Exit codes: 0 report printed, 2 usage error.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
ME="${EUID:-$(id -u)}"
PROC="${SESSION_CLEANUP_PROC:-/proc}"
CATALOG="${SESSION_CLEANUP_CATALOG:-$HERE/../assets/catalog.tsv}"
USER_CATALOG="${XDG_CONFIG_HOME:-$HOME/.config}/session-cleanup/catalog.tsv"
STATE_DIR="${SESSION_CLEANUP_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/orchestrate}"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
TAB="$(printf '\t')"
US="$(printf '\037')"  # field separator that IFS does not collapse when a field is empty

KIND=all
GH=on
MIN_AGE_DAYS=1
DIRS=""

scratch_roots() {
  if [ -n "${SESSION_CLEANUP_SCRATCH_ROOTS:-}" ]; then
    printf '%s\n' "$SESSION_CLEANUP_SCRATCH_ROOTS" | tr ':' '\n'
    return
  fi
  printf '%s\n' "/tmp/claude-$ME"
  if [ -n "${TMPDIR:-}" ] && [ "${TMPDIR%/}" != "/tmp" ]; then
    printf '%s\n' "${TMPDIR%/}/claude-$ME"
  fi
}

file_roots() {
  scratch_roots
  printf '%s\n' "$STATE_DIR"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    processes|git|files|all) KIND="$1" ;;
    --no-gh) GH=off ;;
    --min-age-days)
      shift
      case "${1:-}" in ''|*[!0-9]*) echo "scan: --min-age-days needs a number" >&2; exit 2 ;; esac
      MIN_AGE_DAYS="$1" ;;
    --print-roots) file_roots; exit 0 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    -*) echo "scan: unknown flag '$1'" >&2; exit 2 ;;
    *)
      [ -d "$1" ] || { echo "scan: not a directory: $1" >&2; exit 2; }
      DIRS="$DIRS$(cd "$1" && pwd)
" ;;
  esac
  shift
done

if [ -z "$DIRS" ]; then
  common="$(git rev-parse --git-common-dir 2>/dev/null)" || common=""
  if [ -n "$common" ]; then
    main_top="$(cd "$common/.." && pwd)"
    DIRS="$(dirname "$main_top")
"
  else
    DIRS="$(pwd)
"
  fi
fi

want() { [ "$KIND" = all ] || [ "$KIND" = "$1" ]; }

NOW="$(date +%s)"
MIN_AGE_MIN=$((MIN_AGE_DAYS * 1440))

hsize() {  # KiB -> human
  local kb="${1:-0}" t
  if [ "$kb" -ge 1048576 ]; then t=$((kb * 10 / 1048576)); printf '%d.%dG' $((t / 10)) $((t % 10))
  elif [ "$kb" -ge 1024 ]; then printf '%dM' $((kb / 1024))
  else printf '%dK' "$kb"; fi
}

hage() {  # seconds -> human
  local s="${1:-0}"
  if [ "$s" -ge 86400 ]; then printf '%dd' $((s / 86400))
  elif [ "$s" -ge 3600 ]; then printf '%dh' $((s / 3600))
  else printf '%dm' $((s / 60)); fi
}

mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo "$NOW"; }
size_kb() { du -sk "$1" 2>/dev/null | awk '{print $1}'; }

row() {  # kind owner age size risk id detail
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$@"
}

PROC_OK=0
[ -r "$PROC/meminfo" ] && PROC_OK=1

# Paths held open (cwd or file descriptor) by any process we may inspect. Only
# Linux exposes this cheaply; elsewhere liveness falls back to recency alone.
LIVE_REFS=""
if [ -d "$PROC" ]; then
  LIVE_REFS="$(ls -l "$PROC"/[0-9]*/cwd "$PROC"/[0-9]*/fd 2>/dev/null | sed -n 's/^.* -> //p' | sort -u)"
fi

held_open() {  # path -> 0 if a process has its cwd or an fd at or under it
  [ -n "$LIVE_REFS" ] || return 1
  printf '%s\n' "$LIVE_REFS" | awk -v p="$1" '$0 == p || index($0, p "/") == 1 { found = 1; exit } END { exit !found }'
}

recent() {  # dir -> 0 if anything in it changed within MIN_AGE_DAYS
  [ -n "$(find "$1" -mmin "-$MIN_AGE_MIN" -print 2>/dev/null | head -n 1)" ]
}

printf 'scan\tkind=%s\tgh=%s\tmin_age_days=%s\tproc=%s\n' "$KIND" "$GH" "$MIN_AGE_DAYS" \
  "$([ "$PROC_OK" -eq 1 ] && echo present || echo absent)"
printf '%s' "$DIRS" | while IFS= read -r d; do [ -n "$d" ] && printf 'dir\t%s\n' "$d"; done

# ------------------------------------------------------------------ memory ----

PS_FILE="$(mktemp "${TMPDIR:-/tmp}/session-scan.XXXXXX")"
trap 'rm -f "$PS_FILE"' EXIT
ps -A -ww -o pid=,ppid=,uid=,etime=,rss=,lstart=,command= > "$PS_FILE" 2>/dev/null

if [ "$PROC_OK" -eq 1 ]; then
  awk '
    function h(kb) { if (kb >= 1048576) return sprintf("%.1fG", kb / 1048576); if (kb >= 1024) return sprintf("%dM", kb / 1024); return kb "K" }
    /^MemTotal:/ { t = $2 } /^MemAvailable:/ { a = $2 } /^SwapTotal:/ { st = $2 } /^SwapFree:/ { sf = $2 } /^Shmem:/ { sh = $2 }
    END { printf "memory\ttotal=%s\tavailable=%s\tswap=%s\tshmem=%s\n", h(t), h(a), (st == 0 ? "none" : h(st - sf) "/" h(st)), h(sh) }
  ' "$PROC/meminfo"
  tmp_is_tmpfs=0
  if [ -r "$PROC/mounts" ]; then
    for m in $(awk '$3 == "tmpfs" && ($2 == "/tmp" || $2 == "/dev/shm") { print $2 }' "$PROC/mounts"); do
      [ "$m" = /tmp ] && tmp_is_tmpfs=1
      df -k "$m" 2>/dev/null | awk -v m="$m" 'NR == 2 {
        printf "tmpfs\t%s\tused=%dM\tsize=%dM\t(counts against RAM)\n", m, $3 / 1024, $2 / 1024 }'
    done
  fi
  [ "$tmp_is_tmpfs" -eq 0 ] && printf 'tmpfs\t/tmp\tnot tmpfs (disk-backed)\n'
else
  total="not measured"
  if command -v sysctl >/dev/null 2>&1; then
    bytes="$(sysctl -n hw.memsize 2>/dev/null)" && [ -n "$bytes" ] && total="$(hsize $((bytes / 1024)))"
  fi
  printf 'memory\ttotal=%s\tavailable=not measured\tswap=not measured\tshmem=not measured\n' "$total"
  printf 'note\tno %s/meminfo: available memory, swap and tmpfs not measured; process liveness for files falls back to age only\n' "$PROC"
fi

sort -k5,5nr "$PS_FILE" | head -n 5 | awk '{
  cmd = $0; for (i = 0; i < 10; i++) sub(/^[ \t]*[^ \t]+/, "", cmd); sub(/^[ \t]+/, "", cmd)
  rss = $5; h = (rss >= 1048576) ? sprintf("%.1fG", rss / 1048576) : sprintf("%dM", rss / 1024)
  printf "top\t%s\t%s\t%s\n", h, $1, substr(cmd, 1, 100) }'

printf 'kind\towner\tage\tsize\trisk\tid\tdetail\n'

# --------------------------------------------------------------- processes ----

scan_processes() {
  local cats="$CATALOG"
  [ -r "$USER_CATALOG" ] && cats="$CATALOG $USER_CATALOG"
  # shellcheck disable=SC2086
  cat $cats | awk -v me="$ME" -v self="$$ $PPID" -v psfile="$PS_FILE" '
    function lc(s) { return tolower(s) }
    function base(c,   b) { b = c; sub(/ .*/, "", b); sub(/.*\//, "", b); return b }
    function secs(e,   d, p, n) {
      d = 0; if (index(e, "-")) { d = substr(e, 1, index(e, "-") - 1); e = substr(e, index(e, "-") + 1) }
      n = split(e, p, ":")
      if (n == 3) return d * 86400 + p[1] * 3600 + p[2] * 60 + p[3]
      if (n == 2) return d * 86400 + p[1] * 60 + p[2]
      return d * 86400 + p[1]
    }
    function hs(kb) { if (kb >= 1048576) return sprintf("%.1fG", kb / 1048576); if (kb >= 1024) return sprintf("%dM", kb / 1024); return kb "K" }
    function ha(s) { if (s >= 86400) return int(s / 86400) "d"; if (s >= 3600) return int(s / 3600) "h"; return int(s / 60) "m" }
    function cls(p, any,   i) {
      for (i = 1; i <= nc; i++) {
        if (!any && cpol[i] == "idle-under") continue
        if (lc(cmd[p]) ~ cpat[i]) return i
      }
      return 0
    }
    function root(p,   q, k, pp) {
      q = p
      for (k = 0; k < 64; k++) {
        pp = ppid[q]
        if (pp == "") return ""
        if (pp == 1 || (pp in anch)) return q
        if (!(pp in ppid)) return ""
        q = pp
      }
      return ""
    }
    function busy(i,   p) {
      for (p in cmd) if (uid[p] == me && lc(cmd[p]) ~ lc(cpar[i])) return 1
      return 0
    }
    function under(r) { return (ppid[r] == 1) ? "pid 1" : anch[ppid[r]] " pid " ppid[r] }
    function emit(order, p, label, risk, detail) {
      n_out++
      o_key[n_out] = order "\t" p
      o_row[n_out] = "process\t" label "\t" ha(age[p]) "\t" hs(rss[p]) "\t" risk "\t" p "@" start[p] "\t" detail
      o_sig[n_out] = (risk == "never") ? label "|" gensig(cmd[p]) : ""
    }
    function gensig(c) { gsub(/[0-9]+/, "", c); return c }
    BEGIN { FS = "\t"; ns = split(self, sp, " "); for (i = 1; i <= ns; i++) isself[sp[i]] = 1 }
    /^[ \t]*#/ || /^[ \t]*$/ { next }
    $1 == "anchor"  { na++; apat[na] = lc($3); alab[na] = $2; next }
    $1 == "process" { nc++; clab[nc] = $2; cpat[nc] = lc($3); cpol[nc] = $4; cpar[nc] = $5; next }
    $1 == "branch"  { next }
    END {
      while ((getline line < psfile) > 0) {
        split(line, f, " ")
        p = f[1]; if (p == "") continue
        c = line; for (i = 0; i < 10; i++) sub(/^[ \t]*[^ \t]+/, "", c); sub(/^[ \t]+/, "", c)
        ppid[p] = f[2]; uid[p] = f[3]; age[p] = secs(f[4]); rss[p] = f[5] + 0
        start[p] = f[6] "-" f[7] "-" f[8] "-" f[9] "-" f[10]; cmd[p] = c
        haschild[f[2]] = 1
      }
      for (p in cmd) for (i = 1; i <= na; i++) if (lc(cmd[p]) ~ apat[i]) { anch[p] = alab[i]; break }
      for (p in cmd) {
        if (uid[p] != me || (p in isself) || (p in anch) || p == 1) continue
        r = root(p); rc = (r != "") ? cls(r, 0) : 0
        own = cls(p, 1)
        if (rc > 0) {
          risk = "safe"; why = ""
          if (cpol[rc] == "busy" && busy(rc)) { risk = "named"; why = ", busy: a client matching it is running" }
          if (cpol[rc] == "age" && age[r] < cpar[rc] * 86400) { risk = "named"; why = ", younger than " cpar[rc] "d" }
          label = (own > 0 && cpol[own] != "idle-under") ? clab[own] : "child of " clab[rc]
          emit((risk == "safe") ? 1 : 2, p, label, risk, "orphaned tree, root " r " under " under(r) why ": " substr(cmd[p], 1, 100))
          continue
        }
        if (own == 0) continue
        if (cpol[own] == "idle-under") {
          if (lc(cmd[ppid[p]]) ~ lc(cpar[own]) && !(p in haschild) && age[p] > 3600)
            emit(2, p, clab[own], "named", "idle under " base(cmd[ppid[p]]) " pid " ppid[p] ", no child process: " substr(cmd[p], 1, 100))
          continue
        }
        owner = (r != "") ? base(cmd[r]) " pid " r : "unknown"
        if (cpol[own] == "age" && age[p] >= cpar[own] * 86400) {
          emit(2, p, clab[own], "named", "live (root " owner "), older than " cpar[own] "d: " substr(cmd[p], 1, 100))
          continue
        }
        emit(3, p, clab[own], "never", "live (root " owner "): " substr(cmd[p], 1, 100))
      }
      for (i = 1; i <= n_out; i++) if (o_sig[i] != "") cnt[o_sig[i]]++
      for (i = 1; i <= n_out; i++) {
        extra = (o_sig[i] != "" && cnt[o_sig[i]] > 1) ? " [x" cnt[o_sig[i]] " same command]" : ""
        print o_key[i] "\t" o_row[i] extra
      }
    }
  ' | sort -t "$TAB" -k1,1n -k2,2n | cut -f3-
}

# --------------------------------------------------------------------- git ----

branch_label() {  # branch name -> catalog label, or empty
  cat "$CATALOG" "$USER_CATALOG" 2>/dev/null | awk -F'\t' -v b="$1" '
    $1 == "branch" && tolower(b) ~ tolower($3) { print $2; exit }'
}

scan_repo() {
  local repo="$1" name default upstream merged_prs="" checked_out wt line
  name="$(basename "$repo")"
  default="$(git -C "$repo" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"
  if [ -z "$default" ]; then
    for b in main master; do
      git -C "$repo" show-ref --verify -q "refs/heads/$b" && { default="$b"; break; }
    done
  fi

  if [ "$GH" = on ] && command -v gh >/dev/null 2>&1 \
     && git -C "$repo" remote get-url origin 2>/dev/null | grep -q github; then
    merged_prs="$(cd "$repo" && gh pr list --state merged --limit 200 \
      --json number,headRefOid --jq '.[] | "\(.headRefOid) \(.number)"' 2>/dev/null)"
  fi

  checked_out="$(git -C "$repo" worktree list --porcelain | sed -n 's|^branch refs/heads/||p')"

  # Worktrees: blocks separated by blank lines; the first block is the main one.
  git -C "$repo" worktree list --porcelain | awk -v RS= -v ORS='\n' 'NR > 1 {
      path = ""; br = ""; head = ""; prunable = ""; locked = 0
      n = split($0, l, "\n")
      for (i = 1; i <= n; i++) {
        if (l[i] ~ /^worktree /) path = substr(l[i], 10)
        else if (l[i] ~ /^HEAD /) head = substr(l[i], 6)
        else if (l[i] ~ /^branch /) { br = substr(l[i], 8); sub(/^refs\/heads\//, "", br) }
        else if (l[i] ~ /^prunable/) { prunable = substr(l[i], 10); if (prunable == "") prunable = "gitdir missing" }
        else if (l[i] ~ /^locked/) locked = 1
      }
      printf "%s\037%s\037%s\037%s\037%s\n", path, br, head, prunable, locked
    }' > "$PS_FILE.wt"
  while IFS="$US" read -r path br head prunable locked; do
    [ -n "$path" ] || continue
    local id="$repo|$path" owner="$name" age size risk detail ref dirty uniq gitdir
    owner="$name${br:+ ($br)}"
    if [ -n "$prunable" ]; then
      row worktree "$owner" "-" "-" safe "$id" "prunable: $prunable"
      continue
    fi
    if [ "$locked" = 1 ]; then
      row worktree "$owner" "-" "-" never "$id" "locked"
      continue
    fi
    gitdir="$(git -C "$path" rev-parse --absolute-git-dir 2>/dev/null)"
    if [ -n "$gitdir" ] && [ -e "$gitdir/index" ]; then age=$((NOW - $(mtime "$gitdir/index"))); else age=$((NOW - $(mtime "$path"))); fi
    size="$(hsize "$(size_kb "$path")")"
    dirty="$(git -C "$path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    if held_open "$path"; then
      risk=never; detail="in use: a process has its cwd or a file open inside it"
    elif [ "$dirty" -gt 0 ]; then
      risk=named; detail="dirty: $dirty uncommitted change(s) — removing it discards them"
    elif [ -z "$br" ] && [ -n "$default" ] \
         && uniq="$(git -C "$repo" cherry "$default" "$head" 2>/dev/null | grep -c '^+')" && [ "$uniq" -gt 0 ] \
         && [ -z "$(git -C "$repo" branch -a --contains "$head" 2>/dev/null)" ]; then
      risk=named; detail="detached HEAD with $uniq commit(s) on no branch — removing it orphans them"
    elif [ "$age" -lt $((MIN_AGE_DAYS * 86400)) ]; then
      risk=named; detail="clean, but active within ${MIN_AGE_DAYS}d"
    else
      risk=safe; detail="clean${br:+, branch $br is kept}"
    fi
    row worktree "$owner" "$(hage "$age")" "$size" "$risk" "$id" "$detail"
  done < "$PS_FILE.wt"
  rm -f "$PS_FILE.wt"

  if [ -z "$default" ]; then
    printf 'note\t%s: no origin/HEAD, main or master — branches not checked\n' "$name"
    return
  fi

  git -C "$repo" for-each-ref --format='%(refname:short)%1f%(upstream:short)%1f%(upstream:track)%1f%(committerdate:unix)%1f%(objectname)' refs/heads \
  | while IFS="$US" read -r br up track cdate oid; do
    [ "$br" = "${default#origin/}" ] && continue
    printf '%s\n' "$checked_out" | grep -Fxq "$br" && continue
    local uniq label pr age id risk detail pushed
    id="$repo|$br"; age="$(hage $((NOW - cdate)))"
    uniq="$(git -C "$repo" cherry "$default" "$br" 2>/dev/null | grep -c '^+')"
    if [ "$uniq" -eq 0 ]; then
      # A branch just cut from an old default tip also has no unique patch, so
      # its last activity comes from the reflog, not the tip's commit date.
      local touched
      touched="$(git -C "$repo" reflog show -1 --date=unix --format=%gd "refs/heads/$br" 2>/dev/null \
        | sed -n 's/.*@{\([0-9]*\)}$/\1/p')"
      [ -n "$touched" ] && [ "$touched" -gt "$cdate" ] || touched="$cdate"
      if [ $((NOW - touched)) -lt $((MIN_AGE_DAYS * 86400)) ]; then
        row branch "$name" "$age" "-" named "$id" "no commits beyond $default, but active within ${MIN_AGE_DAYS}d"
      else
        row branch "$name" "$age" "-" safe "$id" "merged: every commit has an equivalent patch on $default"
      fi
      continue
    fi
    pr="$(printf '%s\n' "$merged_prs" | awk -v o="$oid" '$1 == o { print $2; exit }')"
    if [ -n "$pr" ]; then
      row branch "$name" "$age" "-" safe "$id" "PR #$pr merged at this tip ($uniq commit(s) squashed into $default)"
      continue
    fi
    label="$(branch_label "$br")"
    [ -n "$label" ] || continue
    pushed="unpushed"
    if [ -n "$up" ] && [ "$(git -C "$repo" rev-list --count "$up..$br" 2>/dev/null)" = 0 ]; then pushed="pushed"; fi
    [ "$track" = "[gone]" ] && pushed="remote branch deleted"
    row branch "$name" "$age" "-" named "$id" "$label: $uniq commit(s) not on $default, $pushed"
  done
}

scan_git() {
  local d c
  printf '%s' "$DIRS" | while IFS= read -r d; do
    [ -n "$d" ] || continue
    if [ -d "$d/.git" ]; then scan_repo "$d"; fi
    for c in "$d"/*/; do
      c="${c%/}"
      [ -d "$c/.git" ] && scan_repo "$c"
    done
  done
  if [ "$GH" = on ] && ! command -v gh >/dev/null 2>&1; then
    printf 'note\tgh not installed: squash-merged branches are not detected, only patch-equivalent ones\n'
  fi
}

# ------------------------------------------------------------------- files ----

scan_files() {
  local root dir slug uuid age size risk detail
  scratch_roots | while IFS= read -r root; do
    [ -d "$root" ] || continue
    for dir in "$root"/*/????????-????-????-????-????????????/; do
      dir="${dir%/}"
      [ -d "$dir" ] || continue
      uuid="$(basename "$dir")"; slug="$(basename "$(dirname "$dir")")"
      age=$((NOW - $(mtime "$dir"))); size="$(hsize "$(size_kb "$dir")")"
      if held_open "$dir"; then
        risk=never; detail="live session: a process holds it open"
      elif recent "$dir"; then
        risk=never; detail="changed within ${MIN_AGE_DAYS}d — may belong to a live session"
      elif [ -f "$CLAUDE_DIR/projects/$slug/$uuid.jsonl" ] \
           && [ $((NOW - $(mtime "$CLAUDE_DIR/projects/$slug/$uuid.jsonl"))) -lt $((MIN_AGE_DAYS * 86400)) ]; then
        risk=never; detail="session transcript active within ${MIN_AGE_DAYS}d"
      else
        risk=safe; detail="session scratch idle ${MIN_AGE_DAYS}d+"
        [ -d "$PROC" ] || detail="$detail (liveness by age only: no $PROC)"
      fi
      row file "scratchpad $slug" "$(hage "$age")" "$size" "$risk" "$dir" "$detail"
    done
  done

  [ -d "$STATE_DIR" ] || return 0
  for dir in "$STATE_DIR"/*/*/; do
    dir="${dir%/}"
    [ -f "$dir/run.json" ] || continue
    local status
    if command -v jq >/dev/null 2>&1; then
      status="$(jq -r '.status // empty' "$dir/run.json" 2>/dev/null)"
    else
      status="$(sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([a-z]*\)".*/\1/p' "$dir/run.json" | head -n 1)"
    fi
    [ "$status" = closed ] || continue
    age=$((NOW - $(mtime "$dir/run.json")))
    row file "orchestrate $(basename "$(dirname "$dir")")" "$(hage "$age")" "$(hsize "$(size_kb "$dir")")" safe "$dir" "orchestrate run closed"
  done
}

# -------------------------------------------------------------------- main ----

ROWS_FILE="$PS_FILE.rows"
trap 'rm -f "$PS_FILE" "$ROWS_FILE"' EXIT
: > "$ROWS_FILE"
want processes && scan_processes >> "$ROWS_FILE"
want git && scan_git >> "$ROWS_FILE"
want files && scan_files >> "$ROWS_FILE"

grep -v '^note' "$ROWS_FILE"
grep '^note' "$ROWS_FILE"

awk -F'\t' '
  $1 == "note" { next }
  { n[$5]++; k[$1 "/" $5]++ }
  END {
    printf "summary\tsafe=%d\tnamed=%d\tnever=%d", n["safe"], n["named"], n["never"]
    split("process branch worktree file", ks, " ")
    for (i = 1; i <= 4; i++) printf "\t%s=%d/%d/%d", ks[i], k[ks[i] "/safe"], k[ks[i] "/named"], k[ks[i] "/never"]
    printf "\n"
  }' "$ROWS_FILE"
