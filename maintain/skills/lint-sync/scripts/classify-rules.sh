#!/usr/bin/env bash
# Classify active ESLint rules against a Biome or Oxc mapping.
# Usage: classify-rules.sh <biome|oxc> <eslint-rules.json> <target-rules.json> [--refs <dir>]
#   eslint-rules.json  output of get-eslint-rules.sh  ({ rules: [{ name, ... }] })
#   target-rules.json  output of get-biome-rules.sh or get-oxlint-rules.sh  ({ rules: ["cat/rule"] })
# Outputs JSON: { target, mapping, counts, summary, DISABLE, REVIEW, ENABLE_TARGET, ESLINT_ONLY, TYPE_AWARE }
set -euo pipefail

usage() {
  echo "Usage: classify-rules.sh <biome|oxc> <eslint-rules.json> <target-rules.json> [--refs <dir>]" >&2
  exit 2
}

[ "$#" -ge 3 ] || usage
TARGET="$1"
ESLINT_JSON="$2"
TARGET_JSON="$3"
shift 3
REFS="$(cd "$(dirname "$0")/../references" 2>/dev/null && pwd || true)"
if [ "$#" -gt 0 ]; then
  [ "$1" = "--refs" ] && [ "$#" -eq 2 ] || usage
  REFS="$2"
fi

case "$TARGET" in
  biome) MAPPING="$REFS/biome-eslint-mapping.json"; FIELD="biome"; VERSION_KEY="biomeVersion" ;;
  oxc) MAPPING="$REFS/oxc-eslint-mapping.json"; FIELD="oxlint"; VERSION_KEY="oxlintVersion" ;;
  *) usage ;;
esac
TYPE_AWARE="$REFS/type-aware-rules.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required" >&2
  exit 1
fi
for f in "$ESLINT_JSON" "$TARGET_JSON" "$MAPPING" "$TYPE_AWARE"; do
  if [ ! -f "$f" ]; then
    echo "Error: file not found: $f" >&2
    exit 1
  fi
done

# Lookup order: exact key, then "plugin/rule" as "eslint-plugin-plugin/rule",
# then "@scope/plugin/rule" collapsed to "@scope/rule".
# Biome matches the active rule by its name only: a rule promoted out of
# nursery/ keeps its name while its category changes. Oxc matches the full
# name, with a leading "eslint/" treated as optional.
jq -n \
  --arg target "$TARGET" --arg field "$FIELD" --arg vkey "$VERSION_KEY" \
  --slurpfile eslint "$ESLINT_JSON" \
  --slurpfile active "$TARGET_JSON" \
  --slurpfile map "$MAPPING" \
  --slurpfile ta "$TYPE_AWARE" '
  ($map[0].rules) as $rules
  | ($ta[0].rules) as $typeaware
  | (if $target == "biome"
      then [$active[0].rules[] | split("/") | last]
      else [$active[0].rules[] | sub("^eslint/"; "")]
     end) as $act
  | def key($t): if $target == "biome" then ($t | split("/") | last) else ($t | sub("^eslint/"; "")) end;
    def lookup($n):
      if $rules[$n] then {key: $n, m: $rules[$n]}
      elif ($n | test("^[^@/][^/]*/")) and $rules["eslint-plugin-" + $n] then
        {key: ("eslint-plugin-" + $n), m: $rules["eslint-plugin-" + $n]}
      elif ($n | test("^@[^/]+/[^/]+/[^/]+$")) then
        ($n | split("/")) as $p | ("\($p[0])/\($p[2])") as $k
        | if $rules[$k] then {key: $k, m: $rules[$k]} else null end
      else null end;
    def is_type_aware($n):
      ($n | startswith("@typescript-eslint/")) and (($n | ltrimstr("@typescript-eslint/")) as $s | $typeaware | any(.[]; . == $s));
  [ $eslint[0].rules[] | .name as $n | lookup($n) as $l
    | if $l == null then
        {bucket: (if is_type_aware($n) then "TYPE_AWARE" else "ESLINT_ONLY" end), eslint: $n}
      else
        ($l.m[$field]) as $t
        | key($t) as $k | ($act | any(.[]; . == $k)) as $on
        | {
            bucket: (if ($on | not) then "ENABLE_TARGET"
                     elif $l.m.relationship == "inspired" then "REVIEW"
                     else "DISABLE" end),
            eslint: $n, target: $t, relationship: $l.m.relationship,
            typeAware: ($l.m.typeAware // false)
          }
      end
  ] as $rows
  | ["DISABLE", "REVIEW", "ENABLE_TARGET", "ESLINT_ONLY", "TYPE_AWARE"] as $b
  | (reduce $b[] as $k ({}; .[$k] = [$rows[] | select(.bucket == $k) | del(.bucket)])) as $groups
  | ($groups | with_entries(.value |= length)) as $counts
  | {
      target: $target,
      mapping: {version: $map[0]._meta[$vkey], updatedAt: $map[0]._meta.updatedAt},
      counts: $counts,
      summary: ("\($rows | length) active ESLint rules -> " + ([$b[] | "\($counts[.]) \(.)"] | join(", ")))
    } + $groups
'
