#!/bin/zsh
# reap-stale.sh
# Find and (optionally) kill stale dev/agent processes owned by the current user:
# orphaned dev servers (Vite / Vite+), editor LSP servers (oxlint), and MCP
# servers (playwright, context7, obsidian, ...).
#
# Staleness rule: a matching process is STALE only when the root of its process
# tree (the ancestor whose PPID is 1 / launchd) is itself abandoned dev tooling.
# That catches dev servers, LSPs, and MCP servers whose launching shell, editor,
# or agent session has exited and left them reparented to launchd. Matches that
# still trace up to a live terminal, app, or agent session are reported as LIVE
# and never killed -- an MCP server attached to a running app must not be reaped
# just because a duplicate exists.
#
# Usage:
#   reap-stale.sh                # report only (dry run)
#   reap-stale.sh --apply        # kill the orphaned matches (prompts once)
#   reap-stale.sh --apply --yes  # kill the orphaned matches without prompting
#
# Output: a human-readable report to stdout. Exit code is always 0.

emulate -L zsh
setopt no_nomatch

APPLY=0 YES=0
for a in "$@"; do
  case "$a" in
    --apply)   APPLY=1 ;;
    --yes|-y)  YES=1 ;;
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
    *) print -u2 "reap-stale: unknown flag '$a'"; exit 2 ;;
  esac
done

me=$(id -un)
self=$$

# --- one snapshot of the process table into maps ---------------------------
typeset -A PARENT CMD ET USR
while read -r pid pp et us cmd; do
  [[ -z $pid ]] && continue
  PARENT[$pid]=$pp; ET[$pid]=$et; USR[$pid]=$us; CMD[$pid]=$cmd
done < <(ps -axww -o pid=,ppid=,etime=,user=,command=)

# --- classifier: print a label if the command is dev tooling we manage -----
classify() {
  local c=${1:l}
  if { [[ $c == *vite-plus* ]] && [[ $c == *" dev"* ]]; } \
     || [[ $c == "vp dev"* || $c == *"/vp dev"* || $c == *" vp dev"* ]]; then
    print -r -- "vite dev server"
  elif [[ $c == *oxlint* && $c == *"--lsp"* ]]; then
    print -r -- "oxlint LSP"
  elif [[ $c == *-mcp* || $c == *"/mcp-"* || $c == *"mcp-obsidian"* \
       || $c == *"playwright-mcp"* || $c == *"@playwright/mcp"* \
       || $c == *"context7-mcp"* || $c == *"/mcp "* || $c == *" mcp "* ]]; then
    print -r -- "MCP server"
  elif [[ $c == *"next dev"* || $c == *storybook* || $c == *"webpack-dev-server"* \
       || $c == *nodemon* || $c == *vitest* ]]; then
    print -r -- "dev server"
  fi
}

# --- tree root: ancestor whose parent is launchd (PID 1); fail if unknown --
root_of() {
  local p=$1 pp i=0
  while (( i++ < 64 )); do
    pp=${PARENT[$p]}
    [[ -z $pp ]] && return 1
    [[ $pp == 1 ]] && { print -r -- "$p"; return 0; }
    p=$pp
  done
  return 1
}

is_stale() {  # arg: pid -> 0 if the tree root is abandoned dev tooling
  local root
  root=$(root_of "$1") || return 1
  [[ -n "$(classify "${CMD[$root]}")" ]]
}

owner_name() {  # short name of the live owner at the tree root
  local r oc
  r=$(root_of "$1") || { print -r -- "?"; return; }
  oc=${CMD[$r]:l}
  case $oc in
    *cmux*)       print -r -- "cmux" ;;
    *claude.app*) print -r -- "Claude.app" ;;
    *claude*)     print -r -- "claude (CLI)" ;;
    *code\ helper*|*vscode*|*/code*) print -r -- "VS Code" ;;
    *)            print -r -- "${${CMD[$r]%% *}:t}" ;;
  esac
}

# --- scan -------------------------------------------------------------------
typeset -a STALE LIVE
typeset pid='' label=''  # assignment form: bare `typeset pid` would echo the leftover loop value
for pid in ${(k)CMD}; do
  [[ ${USR[$pid]} == "$me" ]] || continue
  [[ $pid == $self ]] && continue
  label=$(classify "${CMD[$pid]}")
  [[ -n $label ]] || continue
  if is_stale "$pid"; then STALE+=("$pid"); else LIVE+=("$pid"); fi
done

fmt() { printf "  PID %-6s %-10s %-16s %s\n" "$1" "${ET[$1]}" "$(classify "${CMD[$1]}")" "${CMD[$1]:0:88}"; }

print -r -- "Stale dev/agent process scan -- user: $me"
print -r -- ""
if (( ${#STALE} )); then
  print -r -- "ORPHANED (abandoned tooling, reparented to launchd -- safe to reap):"
  for pid in ${(on)STALE}; do fmt "$pid"; done
else
  print -r -- "ORPHANED: none."
fi

if (( ${#LIVE} )); then
  print -r -- ""
  print -r -- "LIVE (traces up to a running session/app -- left alone):"
  for pid in ${(on)LIVE}; do
    printf "  PID %-6s %-10s %-16s (owner: %s)\n" "$pid" "${ET[$pid]}" "$(classify "${CMD[$pid]}")" "$(owner_name "$pid")"
  done
  # flag likely-duplicate live servers (identical command modulo numbers)
  typeset -A SIGCOUNT
  typeset sig
  for pid in $LIVE; do sig=${${CMD[$pid]//[0-9]/}// /}; (( SIGCOUNT[$sig]++ )); done
  typeset -a dups
  for pid in $LIVE; do sig=${${CMD[$pid]//[0-9]/}// /}; (( SIGCOUNT[$sig] >= 2 )) && dups+=("$pid"); done
  if (( ${#dups} )); then
    print -r -- ""
    print -r -- "NOTE: possible duplicate live servers (same command running 2+ times): ${(on)dups}"
    print -r -- "      Restart the owning app to collapse them; don't blind-kill a live one."
  fi
fi

print -r -- ""
if (( ${#STALE} == 0 )); then
  print -r -- "Nothing to reap."
  exit 0
fi
if (( APPLY == 0 )); then
  print -r -- "Dry run. Re-run with --apply to kill the ${#STALE} orphaned process(es) (add --yes to skip the prompt)."
  exit 0
fi
if (( YES == 0 )); then
  printf "Kill %d orphaned process(es)? [y/N] " ${#STALE}
  read -r ans
  [[ $ans == [yY]* ]] || { print -r -- "Aborted."; exit 0; }
fi

kill ${(on)STALE} 2>/dev/null
sleep 1
typeset -a surv
for pid in $STALE; do kill -0 "$pid" 2>/dev/null && surv+=("$pid"); done
if (( ${#surv} )); then kill -9 ${surv} 2>/dev/null; sleep 1; fi
typeset gone=0
for pid in $STALE; do kill -0 "$pid" 2>/dev/null || (( gone++ )); done
print -r -- "Reaped $gone/${#STALE} orphaned process(es)."
exit 0
