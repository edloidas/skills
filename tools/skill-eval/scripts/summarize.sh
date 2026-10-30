#!/usr/bin/env bash
# summarize.sh — turn one suite result into the Markdown summary: environment, one row per
# case with its pass rate, and what each run actually did, read from its trace.
#
#   bash tools/skill-eval/scripts/summarize.sh <out-dir> [suite]   # prints Markdown to stdout
#
# Reads <out-dir>/aggregate-result.json, <out-dir>/traces/<case>/<run>.jsonl, and each case's
# case.yaml (for expected_outcome) under the result's suite.root. Never calls a model.
set -uo pipefail

out="${1:-}"
[ -n "$out" ] && [ -f "$out/aggregate-result.json" ] || { echo "usage: summarize.sh <out-dir with aggregate-result.json>" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
agg="$out/aggregate-result.json"
suite="${2:-}"

# One run's observation: the route `do` printed, the skills the Skill tool loaded, and the
# `do` playbook it opened. Each comes from the trace, never from what the run says about itself.
observe() {
  local trace="$1" route skills playbook parts=""
  [ -f "$trace" ] || { printf 'no trace'; return; }
  route="$(jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' "$trace" 2>/dev/null \
    | grep -m1 -o 'Route:[^—]*' | sed 's/^Route://; s/[`*]//g; s/^[[:space:]]*//; s/[[:space:].]*$//')"
  skills="$(jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Skill") | .input.skill' "$trace" 2>/dev/null \
    | sed 's/^edloidas://' | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
  playbook="$(jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="Read") | .input.file_path // empty' "$trace" 2>/dev/null \
    | grep -m1 -o 'skills/do/references/[a-z-]*\.md' | sed 's|.*/||')"
  [ -n "$route" ] && parts="route: $route"
  [ -n "$skills" ] && parts="${parts:+$parts · }skill: $skills"
  [ -n "$playbook" ] && parts="${parts:+$parts · }read: $playbook"
  printf '%s' "${parts:-no skill, no route}"
}

# Cases cap max_turns on purpose: the route is decided in the first few turns, and a run
# that reaches the cap afterwards is scored on its graders like any other.
TURN_CAP="Reached maximum number of turns"

cell() { printf '%s' "$1" | tr '\n' ' ' | sed 's/|/\\|/g'; }

root="$(jq -r '.suite.root' "$agg")"
traces="$(find "$out/traces" -name '*.jsonl' -type f 2>/dev/null | sort)"
models=""
if [ -n "$traces" ]; then
  models="$(printf '%s\n' "$traces" | while IFS= read -r t; do
      jq -r 'select(.type=="system" and .subtype=="init") | .model' "$t" 2>/dev/null
    done | sort -u | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
fi

jq -r --arg suite "$suite" '"# Skill eval: \(if $suite != "" then $suite else (.cases[0].name // "empty" | split("-")[0]) end)\n",
  "- Claude Code: \(.claudeVersion)",
  "- Started: \(.startedAt) · duration \(.durationSeconds)s · cost $\(.costUsd * 100 | round / 100)",
  "- Runs per case: \([.cases[].arms.with | length] | max // 0) · ablation: \(.suite.ablation)\(if .partial then " · PARTIAL: \(.partialReason)" else "" end)"' "$agg"
echo "- Model: ${models:-unknown (no traces collected)}"
jq -r '[.cases[].arms.with[]?] as $r
  | "- Cases fully passing: \(.aggregates.casesPassed) of \(.aggregates.casesTotal) · runs passing: \([$r[] | select(.passed)] | length) of \($r | length)"' "$agg"
echo
echo "| Case | Prompt | Expected | Pass | Observed per run |"
echo "| ---- | ------ | -------- | ---- | ---------------- |"

ncases="$(jq '.cases | length' "$agg")"
i=0
while [ "$i" -lt "$ncases" ]; do
  name="$(jq -r ".cases[$i].name" "$agg")"
  dir="$(jq -r ".cases[$i].dir" "$agg")"
  prompt="$(jq -r ".cases[$i].promptMarkdown" "$agg")"
  expected="$(sed -n 's/^expected_outcome:[[:space:]]*//p' "$root/$dir/case.yaml" 2>/dev/null | head -1 | sed 's/^"\(.*\)"$/\1/')"
  nruns="$(jq ".cases[$i].arms.with | length" "$agg")"
  npass="$(jq "[.cases[$i].arms.with[] | select(.passed)] | length" "$agg")"
  nerr="$(jq --arg cap "$TURN_CAP" "[.cases[$i].arms.with[] | select(.error != null and (.error | contains(\$cap) | not))] | length" "$agg")"
  ncap="$(jq --arg cap "$TURN_CAP" "[.cases[$i].arms.with[] | select(.error != null and (.error | contains(\$cap)))] | length" "$agg")"
  pass="$npass/$nruns"
  [ "$nerr" -gt 0 ] && pass="$pass ($nerr error)"
  [ "$ncap" -gt 0 ] && pass="$pass ($ncap at turn cap)"
  observed=""
  r=1
  while [ "$r" -le "$nruns" ]; do
    obs="$(observe "$out/traces/$name/$r.jsonl")"
    observed="${observed:+$observed<br>}$r: $obs"
    r=$((r + 1))
  done
  printf '| %s | %s | %s | %s | %s |\n' "$(cell "$name")" "$(cell "$prompt")" "$(cell "${expected:-?}")" "$pass" "$(cell "$observed")"
  i=$((i + 1))
done

failures="$(jq -r --arg cap "$TURN_CAP" '.cases[] | .name as $n | .arms.with | to_entries[]
  | (.key + 1) as $k
  | (if .value.error != null and (.value.error | contains($cap) | not) then "- \($n) run \($k): error: \(.value.error)" else empty end),
    (.value.graders[]? | select(.passed | not) | "- \($n) run \($k): \(.name): \(.explanation)")' "$agg")"
if [ -n "$failures" ]; then
  echo
  echo "## Failed graders"
  echo
  printf '%s\n' "$failures"
fi
