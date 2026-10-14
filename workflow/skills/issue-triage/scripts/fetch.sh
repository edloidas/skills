#!/usr/bin/env bash
# fetch.sh — read a repository's open issues once, resolve what they reference, and cluster them.
#
#   fetch.sh --repo <owner/repo> --out <dir> [--label <name>]... [--older-than <days>] [--numbers N,N]
#
# Writes to <dir>:
#   issues.json    one object per open issue in scope: body, labels, type, milestone, parent,
#                  sub-issue counts, assignees, the last 5 comments, and cross-references
#   refs.json      every #N mentioned in a body or comment, resolved: kind, state, close reason,
#                  merged, author — null when the number does not exist
#   context.json   the repository's labels and issue types
#   clusters.tsv   <cluster>\t<issue numbers>: issues joined by parent, cross-reference or mention
# Last stdout line: issues <n> refs <n> unresolved <n> clusters <n>
# Read-only. Exit 1 on a gh or jq failure, 2 on bad arguments.

set -euo pipefail

die() { local code="$1"; shift; echo "fetch.sh: $*" >&2; exit "$code"; }

REPO=""; OUT=""; LABELS=""; OLDER=""; NUMBERS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --label) LABELS="$LABELS${LABELS:+,}${2:-}"; shift 2 ;;
    --older-than) OLDER="${2:-}"; shift 2 ;;
    --numbers) NUMBERS="${2:-}"; shift 2 ;;
    *) die 2 "unknown argument: $1" ;;
  esac
done
printf '%s' "$REPO" | grep -qE '^[^/ ]+/[^/ ]+$' || die 2 "--repo owner/name is required"
[ -n "$OUT" ] || die 2 "--out <dir> is required"
[ -z "$OLDER" ] || printf '%s' "$OLDER" | grep -qE '^[0-9]+$' || die 2 "--older-than takes a number of days"
command -v jq >/dev/null 2>&1 || die 1 "jq is required"
command -v gh >/dev/null 2>&1 || die 1 "gh is required"
mkdir -p "$OUT"
OWNER="${REPO%%/*}"; NAME="${REPO#*/}"

# ------------------------------------------------------------------ issues --

: > "$OUT/pages.jsonl"
cursor=""
while :; do
  page="$(gh api graphql -f o="$OWNER" -f r="$NAME" ${cursor:+-f c="$cursor"} -f query='
    query($o:String!,$r:String!,$c:String){repository(owner:$o,name:$r){issues(states:OPEN,first:50,after:$c){
      pageInfo{hasNextPage endCursor}
      nodes{number title body createdAt updatedAt author{login} assignees(first:5){nodes{login}}
        labels(first:20){nodes{name}} issueType{name} milestone{title} parent{number state}
        subIssuesSummary{total completed}
        comments(last:5){totalCount nodes{author{login} createdAt body}}
        timelineItems(itemTypes:[CROSS_REFERENCED_EVENT],last:20){nodes{... on CrossReferencedEvent{
          source{__typename ... on Issue{number state} ... on PullRequest{number state}}}}}}}}}')" \
    || die 1 "cannot read issues of $REPO"
  printf '%s' "$page" | jq -c '.data.repository.issues.nodes[]' >> "$OUT/pages.jsonl"
  [ "$(printf '%s' "$page" | jq -r '.data.repository.issues.pageInfo.hasNextPage')" = true ] || break
  cursor="$(printf '%s' "$page" | jq -r '.data.repository.issues.pageInfo.endCursor')"
done

cutoff=""
if [ -n "$OLDER" ]; then
  cutoff="$(date -u -d "-$OLDER days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-"$OLDER"d +%Y-%m-%dT%H:%M:%SZ)"
fi

jq -s --arg labels "$LABELS" --arg cutoff "$cutoff" --arg numbers "$NUMBERS" '
  ($labels | split(",") | map(select(length > 0))) as $want
  | ($numbers | split(",") | map(select(length > 0) | tonumber)) as $only
  | [ .[]
      | select(($only | length) == 0 or (.number as $n | $only | index($n)))
      | select([.labels.nodes[].name] as $have | all($want[]; . as $w | $have | index($w)))
      | select($cutoff == "" or .updatedAt < $cutoff)
      | { number, title, body: (.body // ""), createdAt, updatedAt, author: .author.login,
          assignees: [.assignees.nodes[].login], labels: [.labels.nodes[].name], type: .issueType.name,
          milestone: .milestone.title, parent: .parent.number, subIssues: .subIssuesSummary,
          comments: { total: .comments.totalCount,
                      last: [.comments.nodes[] | {author: .author.login, createdAt, body}] },
          crossRefs: [.timelineItems.nodes[].source | select(. != null)
                      | {number, kind: (if .__typename == "PullRequest" then "pr" else "issue" end), state}] } ]
  | sort_by(.number)' "$OUT/pages.jsonl" > "$OUT/issues.json"
rm -f "$OUT/pages.jsonl"

# -------------------------------------------------------------------- refs --

jq -r '.[] | .body, .comments.last[].body' "$OUT/issues.json" \
  | grep -oE '(^|[^&A-Za-z0-9/])#[0-9]+' | grep -oE '[0-9]+' | sort -n | uniq > "$OUT/mentions.txt" || true

echo '{}' > "$OUT/refs.json"
batch=""
resolve() {
  [ -n "$batch" ] || return 0
  local q
  q="query(\$o:String!,\$r:String!){repository(owner:\$o,name:\$r){$batch}}"
  # A number that does not exist makes GraphQL report an error and return null for that alias.
  gh api graphql -f o="$OWNER" -f r="$NAME" -f query="$q" 2>/dev/null | jq -c '.data.repository // {}' > "$OUT/batch.json" || true
  [ -s "$OUT/batch.json" ] || echo '{}' > "$OUT/batch.json"
  jq --slurpfile b "$OUT/batch.json" '. + ($b[0] | with_entries(.key |= ltrimstr("n")
      | .value |= (if . == null then null
                   else {kind: (if .__typename == "PullRequest" then "pr" else "issue" end), title, state,
                         reason: (.stateReason // null), merged: (.merged // null), author: .author.login} end)))' \
    "$OUT/refs.json" > "$OUT/refs.next" && mv "$OUT/refs.next" "$OUT/refs.json"
  batch=""
}
count=0
while IFS= read -r n; do
  [ -n "$n" ] || continue
  batch="$batch n$n: issueOrPullRequest(number:$n){__typename ... on Issue{title state stateReason author{login}} ... on PullRequest{title state merged author{login}}}"
  count=$((count + 1))
  if [ $((count % 50)) -eq 0 ]; then resolve; fi
done < "$OUT/mentions.txt"
resolve
# Mentions GraphQL did not return at all are unresolved too.
jq -R -s --slurpfile r "$OUT/refs.json" 'split("\n") | map(select(length > 0)) as $all
  | $r[0] + ([$all[] | select(. as $k | $r[0] | has($k) | not) | {key: ., value: null}] | from_entries)' \
  "$OUT/mentions.txt" > "$OUT/refs.next" && mv "$OUT/refs.next" "$OUT/refs.json"
rm -f "$OUT/mentions.txt" "$OUT/batch.json"

# ----------------------------------------------------------------- context --

labels="$(gh label list -R "$REPO" --limit 1000 --json name,description)" || die 1 "cannot list labels"
types="$(gh api graphql -f o="$OWNER" -f r="$NAME" -f query='query($o:String!,$r:String!){repository(owner:$o,name:$r){issueTypes(first:50){nodes{name description}}}}' \
  --jq '[.data.repository.issueTypes.nodes[]?]' 2>/dev/null || echo '[]')"
jq -n --argjson l "$labels" --argjson t "$types" '{labels: $l, types: $t}' > "$OUT/context.json"

# ---------------------------------------------------------------- clusters --

# Edges between open issues in scope: parent, cross-reference, and a #N mention either way.
jq -r --slurpfile all "$OUT/issues.json" '
  ([$all[0][].number]) as $open
  | .[] | .number as $a
  | ( [.parent], [.crossRefs[] | select(.kind == "issue") | .number],
      [(.body, .comments.last[].body) | scan("(?:^|[^&A-Za-z0-9/])#([0-9]+)") | .[0] | tonumber] )
  | .[] | select(. != null and . != $a) | select(. as $b | $open | index($b)) | "\($a) \(.)"' \
  "$OUT/issues.json" > "$OUT/edges.txt"

jq -r '.[].number' "$OUT/issues.json" | awk -v edges="$OUT/edges.txt" '
  function find(x) { while (p[x] != x) { p[x] = p[p[x]]; x = p[x] } return x }
  { p[$1] = $1; order[++n] = $1 }
  END {
    while ((getline line < edges) > 0) {
      split(line, e, " ")
      if ((e[1] in p) && (e[2] in p)) { a = find(e[1]); b = find(e[2]); if (a != b) p[a] = b }
    }
    for (i = 1; i <= n; i++) { r = find(order[i]); members[r] = members[r] (members[r] ? " " : "") order[i]; if (!(r in seen)) { seen[r] = 1; roots[++k] = r } }
    for (i = 1; i <= k; i++) printf "c%d\t%s\n", i, members[roots[i]]
  }' > "$OUT/clusters.tsv"
rm -f "$OUT/edges.txt"

echo "issues $(jq length "$OUT/issues.json") refs $(jq length "$OUT/refs.json") unresolved $(jq '[.[] | select(. == null)] | length' "$OUT/refs.json") clusters $(wc -l < "$OUT/clusters.tsv" | tr -d ' ')"
