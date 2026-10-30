#!/usr/bin/env bash
# collect-traces.sh — copy each run's trace out of the eval's kept temp directory into
# <out>/traces/<case>/<run>.jsonl, then delete that temp directory.
#
#   bash tools/skill-eval/scripts/collect-traces.sh <out-dir>
#
# `--keep-temp` leaves each run's workspace sealed read-only; without this step they pile up.
# Only a directory named claude-eval-* that the result points at is ever removed.
set -uo pipefail

out="${1:-}"
[ -n "$out" ] && [ -f "$out/aggregate-result.json" ] || { echo "usage: collect-traces.sh <out-dir with aggregate-result.json>" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

copied=0
missing=0
while IFS="$(printf '\t')" read -r case_name run trace; do
  [ -n "$case_name" ] || continue
  if [ -z "$trace" ]; then
    continue
  fi
  kept="$(dirname "$(dirname "$trace")")"
  case "$(basename "$kept")" in
    claude-eval-*) chmod -R u+rwx "$kept" 2>/dev/null ;;
    *) kept="" ;;
  esac
  if [ -f "$trace" ]; then
    mkdir -p "$out/traces/$case_name"
    cp "$trace" "$out/traces/$case_name/$run.jsonl"
    copied=$((copied + 1))
  else
    missing=$((missing + 1))
  fi
  [ -n "$kept" ] && rm -rf "$kept"
done <<EOF2
$(jq -r '.cases[] | .name as $n | (.arms.with // []) | to_entries[] | [$n, (.key + 1 | tostring), (.value.tracePath // "")] | @tsv' "$out/aggregate-result.json")
EOF2

echo "Collected $copied trace(s), $missing missing, into $out/traces"
