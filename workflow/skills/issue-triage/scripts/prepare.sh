#!/usr/bin/env bash
# prepare.sh — the mechanical steps between fetch.sh and apply.sh, run on a run directory offline.
#
#   prepare.sh themes   <run dir> [--max 10]
#   prepare.sh lint     <run dir> [--stale-days 365] [--type-map "<label>=<type>,..."]
#   prepare.sh manifest <run dir> --marker <id> [--project owner/number --closed-status <name>]
#                       [--status <VERDICT|CLOSE|OPEN>=<name>]...
#   prepare.sh claims   <run dir>
#
# themes   themes.tsv  <theme>\t<issue numbers>: clusters and similar.tsv pairs kept together, an
#                      oversized group split by parent, packed up to --max issues per theme
# lint     lint.json   {"<n>": {"type": <type its labels name, or null>, "flags": [...]}}: a label
#                      names a type when it is the type's name or maps to it in --type-map. Flags:
#                      no-type, type-conflict, stale, dead-ref <key>, parent-closed, subissues-done
# manifest manifest.json from decisions.json (an array of decision objects, see
#                      references/acting.md) and lint.json: one row per issue in issues.json.
#                      A decision wins over lint; texts are expected at texts/<n>.<close|ask|note>.md;
#                      new_issues.json, when present, is copied in as the manifest's new_issues.
#                      Refuses a duplicate or not-planned close of a security decision, or of an
#                      issue labelled Security, that lacks "confirmed": true from the gate
# claims   claims.md   the numbered load-bearing claims of every close and security decision, and
#                      the issues they cite — the input for blind verification
# Last stdout line: themes <n> | lint <flagged> of <n> | manifest rows <n> closes <n> | claims <n>
# Writes only inside the run directory. Exit 2 on bad arguments or a missing input file.

set -euo pipefail

die() { local code="$1"; shift; echo "prepare.sh: $*" >&2; exit "$code"; }

CMD="${1:-}"; DIR="${2:-}"
[ -n "$CMD" ] && [ -n "$DIR" ] || die 2 "usage: prepare.sh themes|lint|manifest <run dir> [options]"
shift 2
[ -f "$DIR/issues.json" ] || die 2 "no issues.json in $DIR"
command -v jq >/dev/null 2>&1 || die 1 "jq is required"

need() { [ -f "$DIR/$1" ] || die 2 "no $1 in $DIR — run $2 first"; }

case "$CMD" in
  themes)
    MAX=10
    while [ $# -gt 0 ]; do
      case "$1" in --max) MAX="${2:-}"; shift 2 ;; *) die 2 "unknown argument: $1" ;; esac
    done
    printf '%s' "$MAX" | grep -qE '^[0-9]+$' || die 2 "--max takes a number"
    need clusters.tsv fetch.sh
    [ -f "$DIR/similar.tsv" ] || : > "$DIR/similar.tsv"
    # Groups: clusters joined by any similar pair, by union-find over both files.
    groups="$(awk -F'\t' '
      function find(x) { while (p[x] != x) { p[x] = p[p[x]]; x = p[x] } return x }
      function join(a, b) { a = find(a); b = find(b); if (a != b) p[a] = b }
      FNR == 1 { file++ }
      file == 1 { n = split($2, m, " "); for (i = 1; i <= n; i++) { if (!(m[i] in p)) { p[m[i]] = m[i]; order[++k] = m[i] } if (i > 1) join(m[1], m[i]) } }
      file == 2 { if (($1 in p) && ($2 in p)) join($1, $2) }
      END {
        for (i = 1; i <= k; i++) { r = find(order[i]); g[r] = g[r] (g[r] ? " " : "") order[i]; if (!(r in seen)) { seen[r] = 1; roots[++c] = r } }
        for (i = 1; i <= c; i++) print g[roots[i]]
      }' "$DIR/clusters.tsv" "$DIR/similar.tsv")"
    printf '%s\n' "$groups" | jq -R -s --argjson max "$MAX" --slurpfile issues "$DIR/issues.json" '
      ($issues[0] | map({key: (.number | tostring), value: .parent}) | from_entries) as $parent
      | [split("\n")[] | select(length > 0) | split(" ") | map(tonumber)]
      # An oversized group splits into its parent families, each chunked to $max.
      | map(if length <= $max then [.]
            else group_by(. as $n | $parent[$n | tostring] // $n)
                 | map(. as $f | [range(0; $f | length; $max) | $f[.:. + $max]][]) end)
      | flatten(1)
      # Pack whole groups into themes of at most $max, in order.
      | reduce .[] as $g ([]; if (length > 0 and ((.[-1] | length) + ($g | length)) <= $max)
                               then .[-1] += $g else . + [$g] end)
      | to_entries[] | "t\(.key + 1)\t\(.value | map(tostring) | join(" "))"' -r > "$DIR/themes.tsv"
    echo "themes $(wc -l < "$DIR/themes.tsv" | tr -d ' ')"
    ;;

  lint)
    DAYS=365; MAP=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --stale-days) DAYS="${2:-}"; shift 2 ;;
        --type-map) MAP="${2:-}"; shift 2 ;;
        *) die 2 "unknown argument: $1" ;;
      esac
    done
    printf '%s' "$DAYS" | grep -qE '^[0-9]+$' || die 2 "--stale-days takes a number"
    need refs.json fetch.sh
    need context.json fetch.sh
    cutoff="$(date -u -d "-$DAYS days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-"$DAYS"d +%Y-%m-%dT%H:%M:%SZ)"
    jq --slurpfile refs "$DIR/refs.json" --slurpfile ctx "$DIR/context.json" --arg cutoff "$cutoff" --arg map "$MAP" '
      ($ctx[0].types | map(.name)) as $types
      | ($types | map({key: ascii_downcase, value: .}) | from_entries) as $byname
      | ($map | split(",") | map(select(contains("=")) | split("=") | {key: (.[0] | ascii_downcase), value: .[1]})
         | from_entries) as $mapped
      | map(. as $i
          | ([$i.labels[] | ascii_downcase | $byname[.] // $mapped[.] // empty] | unique) as $named
          | { key: ($i.number | tostring),
              value: { type: (if ($named | length) == 1 and $i.type != $named[0] then $named[0] else null end),
                       flags: [ (if ($types | length) > 0 and $i.type == null and ($named | length) == 0 then "no-type" else empty end),
                                (if ($named | length) > 1 then "type-conflict \($named | join(","))" else empty end),
                                (if $i.updatedAt < $cutoff then "stale" else empty end),
                                ($i.refs[]? | select(. as $k | $refs[0] | has($k) and .[$k] == null) | "dead-ref \(.)"),
                                (if $i.parentState == "CLOSED" then "parent-closed #\($i.parent)" else empty end),
                                (if $i.subIssues.total > 0 and $i.subIssues.completed == $i.subIssues.total
                                 then "subissues-done \($i.subIssues.total)" else empty end) ] } })
      | from_entries' "$DIR/issues.json" > "$DIR/lint.json"
    echo "lint $(jq '[.[] | select(.type != null or (.flags | length) > 0)] | length' "$DIR/lint.json") of $(jq length "$DIR/lint.json")"
    ;;

  manifest)
    MARKER=""; PROJECT=""; CLOSED=""; STATUS='{}'
    while [ $# -gt 0 ]; do
      case "$1" in
        --marker) MARKER="${2:-}"; shift 2 ;;
        --project) PROJECT="${2:-}"; shift 2 ;;
        --closed-status) CLOSED="${2:-}"; shift 2 ;;
        --status) printf '%s' "${2:-}" | grep -q '=' || die 2 "--status takes <VERDICT|CLOSE|OPEN>=<name>"
                  STATUS="$(jq -c --arg k "${2%%=*}" --arg v "${2#*=}" '. + {($k): $v}' <<< "$STATUS")"; shift 2 ;;
        *) die 2 "unknown argument: $1" ;;
      esac
    done
    [ -n "$MARKER" ] || die 2 "--marker <run id> is required"
    [ -z "$PROJECT" ] || printf '%s' "$PROJECT" | grep -qE '^[^/ ]+/[0-9]+$' || die 2 "--project takes owner/number"
    [ "$STATUS" = '{}' ] || [ -n "$PROJECT" ] || die 2 "--status needs --project"
    need lint.json "prepare.sh lint"
    [ -f "$DIR/decisions.json" ] || echo '[]' > "$DIR/decisions.json"
    unconfirmed="$(jq -r --slurpfile issues "$DIR/issues.json" '
      ($issues[0] | map({key: (.number | tostring), value: (.labels | map(ascii_downcase) | index("security") != null)})
       | from_entries) as $labelled
      | .[] | select(.verdict == "CLOSE-DUPLICATE" or .verdict == "CLOSE-NOT-PLANNED")
      | select(.security == true or $labelled[.number | tostring] == true) | select(.confirmed != true)
      | "#\(.number)"' "$DIR/decisions.json" | tr '\n' ' ')"
    [ -z "$unconfirmed" ] || die 2 "security closes need the user's answer at the gate (\"confirmed\": true): $unconfirmed"
    repo="$(jq -r '.repo // empty' "$DIR/context.json" 2>/dev/null || true)"
    new='[]'
    [ ! -f "$DIR/new_issues.json" ] || new="$(jq -c . "$DIR/new_issues.json")" || die 2 "new_issues.json is not valid JSON"
    jq -n --slurpfile issues "$DIR/issues.json" --slurpfile lint "$DIR/lint.json" \
          --slurpfile dec "$DIR/decisions.json" --argjson new "$new" --argjson status "$STATUS" \
          --arg marker "$MARKER" --arg repo "$repo" --arg project "$PROJECT" --arg closed "$CLOSED" '
      ($dec[0] | map({key: (.number | tostring), value: .}) | from_entries) as $d
      | def reason: {"CLOSE-DONE": "completed", "CLOSE-OBSOLETE": "not_planned",
                     "CLOSE-NOT-PLANNED": "not_planned", "CLOSE-DUPLICATE": "duplicate"}[.];
        def statusfor($v): $status[$v] // (if ($v | startswith("CLOSE")) then $status.CLOSE else $status.OPEN end);
      { version: 1, repo: $repo, marker: $marker,
        project: (if $project == "" then null
                  else {owner: ($project | split("/")[0]), number: ($project | split("/")[1] | tonumber),
                        status_field: "Status", closed_status: (if $closed == "" then null else $closed end)} end),
        issues: [ $issues[0][] | (.number | tostring) as $k | ($d[$k] // {}) as $x | ($x.verdict // "KEEP") as $v
          | { number, type: ($x.type // $lint[0][$k].type),
              labels: (if ($x.labels // {}) == {} then null else $x.labels end),
              title: ($x.title // null), status: ($x.status // statusfor($v)),
              milestone: ($x.milestone // null), skip: (if $x.skip == true then true else null end),
              project: (if $x.project == false then false else null end),
              body: (if $x.note == true then {mode: "prepend", file: "texts/\(.number).note.md"} else null end),
              comment_file: (if ($v | startswith("CLOSE")) then "texts/\(.number).close.md"
                             elif $v == "STALE-ASK" or $v == "NEEDS-DISCUSSION" then "texts/\(.number).ask.md"
                             else null end) }
            + (if ($v | startswith("CLOSE")) then {state: "closed", reason: ($v | reason)}
                 + (if $v == "CLOSE-DUPLICATE" then {duplicate_of: $x.duplicate_of} else {} end) else {} end)
          | with_entries(select(.value != null)) ],
        new_issues: $new }
      | if .project == null then del(.project) else . end
      | if .new_issues == [] then del(.new_issues) else . end' > "$DIR/manifest.json"
    echo "manifest rows $(jq '.issues | length' "$DIR/manifest.json") closes $(jq '[.issues[] | select(.state == "closed")] | length' "$DIR/manifest.json")"
    ;;

  claims)
    need decisions.json "Phase 1"
    jq -r '[.[] | select((.verdict | startswith("CLOSE")) or .security == true) | . as $d
            | ($d.claims // [])[] | "[#\($d.number) \($d.verdict)] \(.)"]
           | to_entries[] | "\(.key + 1). \(.value)"' "$DIR/decisions.json" > "$DIR/claims.md"
    missing="$(jq -r '.[] | select(((.verdict | startswith("CLOSE")) or .security == true) and ((.claims // []) | length) == 0) | "#\(.number)"' "$DIR/decisions.json" | tr '\n' ' ')"
    cited="$(jq -r '[.[] | select((.verdict | startswith("CLOSE")) or .security == true)
            | .number, ((.claims // [])[] | scan("(?:^|[^&A-Za-z0-9/_.-])#([0-9]+)") | .[0] | tonumber)] | unique | map(tostring) | join(" ")' "$DIR/decisions.json")"
    printf '\nCited issues: %s\n' "$cited" >> "$DIR/claims.md"
    [ -z "$missing" ] || die 2 "decisions without claims: $missing"
    echo "claims $(grep -cE '^[0-9]+\. ' "$DIR/claims.md" || true)"
    ;;

  *) die 2 "unknown command: $CMD (themes, lint, manifest, claims)" ;;
esac
