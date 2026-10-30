#!/usr/bin/env bash
# run-suite.sh — run one suite of skill cases through `claude plugin eval`, then collect the
# traces and write summary.md beside the JSON result.
#
#   bash tools/skill-eval/scripts/run-suite.sh <suite> [--runs N] [--model M] [--case GLOB] [--jobs N] [--out DIR]
#
# <suite> is a tag on the cases (routing, ambient). Every run is a real model call.
# Exit codes: the eval's own (0 all cases passed, 1 below threshold or load failure,
# 2 partial), or 1 on a usage or dependency error before anything ran.
set -uo pipefail

usage() { sed -n '5p' "$0" | sed 's/^# *//' >&2; exit 1; }

[ "$#" -ge 1 ] || usage
suite="$1"; shift
runs=3
model=""
case_glob=""
jobs=1
out=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --runs) runs="${2:?--runs needs a number}"; shift 2 ;;
    --model) model="${2:?--model needs a name}"; shift 2 ;;
    --case) case_glob="${2:?--case needs a glob}"; shift 2 ;;
    --jobs) jobs="${2:?--jobs needs a number}"; shift 2 ;;
    --out) out="${2:?--out needs a directory}"; shift 2 ;;
    *) usage ;;
  esac
done

for tool in claude jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "$tool is required" >&2; exit 1; }
done

here="$(cd "$(dirname "$0")" && pwd)"
tool_dir="$(cd "$here/.." && pwd)"
repo="$(cd "$tool_dir/../.." && pwd)"
[ -n "$out" ] || out="$tool_dir/results/$(date -u +%Y%m%dT%H%M%SZ)-$suite"
mkdir -p "$out"

# The plugin under test is the repo root. Cases run read-only (their allowed_tools), with no
# subagents, one arm only: a no-plugin baseline cannot load the skills these cases grade.
set -- "$repo" --eval-dir tools/skill-eval/cases --tag "$suite" --runs "$runs" \
  --ablation none --scaffold --trust-plugin --no-publish --keep-temp \
  --disallow-tools Agent --concurrency "$jobs" --output-dir "$out"
[ -n "$model" ] && set -- "$@" --model "$model"
[ -n "$case_glob" ] && set -- "$@" --case "$case_glob"

echo "Running suite '$suite' ($runs run(s) per case) -> $out"
claude plugin eval "$@"
status=$?

if [ ! -f "$out/aggregate-result.json" ]; then
  echo "No aggregate-result.json was written; nothing to summarize (eval exit $status)." >&2
  exit "$status"
fi

bash "$here/collect-traces.sh" "$out"
bash "$here/summarize.sh" "$out" "$suite" > "$out/summary.md"
cat "$out/summary.md"
exit "$status"
