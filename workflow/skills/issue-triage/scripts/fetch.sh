#!/usr/bin/env bash
# fetch.sh — read a repository's open issues once, resolve what they reference, and cluster them.
#
#   fetch.sh --repo <owner/repo> --out <dir> [--label <name>]... [--older-than <days>] [--numbers N,N] [--epic N]
#
# Writes to <dir>:
#   issues.json    one object per open issue in scope: body, labels, type, milestone, parent and
#                  its state, sub-issue counts, assignees, the last 5 comments, cross-references,
#                  and refs — every reference it makes, keyed as in refs.json
#   refs.json      every reference in a body or comment — #N, owner/repo#N, or an issue or pull
#                  request URL — and every cross-reference, resolved: kind, title, state, close reason, merged, author; null
#                  when it does not exist. Keyed N here, owner/repo#N for another repository
#   clusters.tsv   <cluster>\t<issue numbers>: issues joined by parent, cross-reference, mention,
#                  or a shared reference to another repository
#   context.json   the repository, its labels and issue types
#   similar.tsv    <a>\t<b>\t<score>: issues whose titles share most words, duplicate candidates
# Last stdout line: issues <n> refs <n> unresolved <n> foreign <n> clusters <n> similar <n>
# Read-only. Exit 1 on a gh or jq failure, 2 on bad arguments.

set -euo pipefail

die() { local code="$1"; shift; echo "fetch.sh: $*" >&2; exit "$code"; }

REPO=""; OUT=""; LABELS=""; OLDER=""; NUMBERS=""; EPIC=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --label) LABELS="$LABELS${LABELS:+,}${2:-}"; shift 2 ;;
    --older-than) OLDER="${2:-}"; shift 2 ;;
    --numbers) NUMBERS="${2:-}"; shift 2 ;;
    --epic) EPIC="${2:-}"; shift 2 ;;
    *) die 2 "unknown argument: $1" ;;
  esac
done
printf '%s' "$REPO" | grep -qE '^[^/ ]+/[^/ ]+$' || die 2 "--repo owner/name is required"
[ -n "$OUT" ] || die 2 "--out <dir> is required"
[ -z "$OLDER" ] || printf '%s' "$OLDER" | grep -qE '^[0-9]+$' || die 2 "--older-than takes a number of days"
command -v jq >/dev/null 2>&1 || die 1 "jq is required"
command -v gh >/dev/null 2>&1 || die 1 "gh is required"
[ -z "$EPIC" ] || printf '%s' "$EPIC" | grep -qE '^[0-9]+$' || die 2 "--epic takes an issue number"
mkdir -p "$OUT"
OWNER="${REPO%%/*}"; NAME="${REPO#*/}"
if [ -n "$EPIC" ]; then
  subs="$(gh api --paginate "repos/$REPO/issues/$EPIC/sub_issues" --jq '.[].number')" || die 1 "cannot read the sub-issues of #$EPIC"
  NUMBERS="$NUMBERS${NUMBERS:+,}$EPIC$(printf '%s' "$subs" | tr '\n' ',' | sed 's/^/,/; s/,$//')"
fi

# ------------------------------------------------------------------ issues --

: > "$OUT/pages.jsonl"
cursor=""
while :; do
  page="$(gh api graphql -f o="$OWNER" -f r="$NAME" ${cursor:+-f c="$cursor"} -f query='
    query($o:String!,$r:String!,$c:String){repository(owner:$o,name:$r){issues(states:OPEN,first:50,after:$c){
      pageInfo{hasNextPage endCursor}
      nodes{number title body createdAt updatedAt author{login} authorAssociation assignees(first:5){nodes{login}}
        labels(first:20){nodes{name}} issueType{name} milestone{title} parent{number state}
        subIssuesSummary{total completed}
        comments(last:5){totalCount nodes{author{login} authorAssociation createdAt body}}
        timelineItems(itemTypes:[CROSS_REFERENCED_EVENT],last:20){nodes{... on CrossReferencedEvent{
          source{__typename ... on Issue{number state repository{nameWithOwner}} ... on PullRequest{number state repository{nameWithOwner}}}}}}}}}}')" \
    || die 1 "cannot read issues of $REPO"
  printf '%s' "$page" | jq -c '.data.repository.issues.nodes[]' >> "$OUT/pages.jsonl"
  [ "$(printf '%s' "$page" | jq -r '.data.repository.issues.pageInfo.hasNextPage')" = true ] || break
  cursor="$(printf '%s' "$page" | jq -r '.data.repository.issues.pageInfo.endCursor')"
done

cutoff=""
if [ -n "$OLDER" ]; then
  cutoff="$(date -u -d "-$OLDER days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-"$OLDER"d +%Y-%m-%dT%H:%M:%SZ)"
fi

SELF="$(printf '%s' "$REPO" | tr '[:upper:]' '[:lower:]')"
jq -s --arg self "$SELF" --arg labels "$LABELS" --arg cutoff "$cutoff" --arg numbers "$NUMBERS" '
  ($labels | split(",") | map(select(length > 0))) as $want
  | ($numbers | split(",") | map(select(length > 0) | tonumber)) as $only
  | [ .[]
      | select(($only | length) == 0 or (.number as $n | $only | index($n)))
      | select([.labels.nodes[].name] as $have | all($want[]; . as $w | $have | index($w)))
      | select($cutoff == "" or .updatedAt < $cutoff)
      | { number, title, body: (.body // ""), createdAt, updatedAt, author: .author.login,
          authorRole: .authorAssociation,
          assignees: [.assignees.nodes[].login], labels: [.labels.nodes[].name], type: .issueType.name,
          milestone: .milestone.title, parent: .parent.number, parentState: .parent.state,
          subIssues: .subIssuesSummary,
          comments: { total: .comments.totalCount,
                      last: [.comments.nodes[] | {author: .author.login, role: .authorAssociation, createdAt, body}] },
          crossRefs: [.timelineItems.nodes[].source | select(. != null)
                      | {ref: (if (.repository.nameWithOwner | ascii_downcase) == $self then "\(.number)"
                               else "\(.repository.nameWithOwner)#\(.number)" end),
                         kind: (if .__typename == "PullRequest" then "pr" else "issue" end), state}] } ]
  | sort_by(.number)' "$OUT/pages.jsonl" > "$OUT/issues.json"
rm -f "$OUT/pages.jsonl"

# -------------------------------------------------------------------- refs --

# Every reference in a body or comment — `#N`, `owner/repo#N`, an issue or pull request URL — and
# every cross-reference. One to this repository is keyed `N`; one to another `owner/repo#N`.
REFS_JQ='
  def refkeys($self):
    def key($o; $r; $n): if ("\($o)/\($r)" | ascii_downcase) == $self then $n else "\($o)/\($r)#\($n)" end;
    [ (scan("(?:^|[^&A-Za-z0-9/_.-])#([0-9]+)") | .[0]),
      (scan("github\\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)/(?:issues|pull)/([0-9]+)") | key(.[0]; .[1]; .[2])),
      (scan("(?:^|[^A-Za-z0-9_./-])([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)#([0-9]+)") | key(.[0]; .[1]; .[2])) ]
    | unique;'

jq -r --arg self "$SELF" "$REFS_JQ"' .[] | ((.body, .comments.last[].body) | refkeys($self)[]), .crossRefs[].ref' \
  "$OUT/issues.json" | sort -u > "$OUT/mentions.txt"

ISSUE_FIELDS='__typename ... on Issue{title state stateReason author{login}} ... on PullRequest{title state merged author{login}}'
echo '{}' > "$OUT/refs.json"
batch=""; keys=""
resolve() {
  [ -n "$batch" ] || return 0
  # A number that does not exist makes GraphQL report an error and return null for that alias.
  gh api graphql -f query="query{$batch}" 2>/dev/null | jq -c '.data // {}' > "$OUT/batch.json" || true
  [ -s "$OUT/batch.json" ] || echo '{}' > "$OUT/batch.json"
  jq --slurpfile b "$OUT/batch.json" --arg keys "$keys" '
    ($keys | split(" ") | map(select(length > 0))) as $k
    | . + ([range(0; $k | length) as $i
            | ($b[0]["a\($i)"].issueOrPullRequest // null) as $v
            | {key: $k[$i], value: (if $v == null then null
                 else {kind: (if $v.__typename == "PullRequest" then "pr" else "issue" end), title: $v.title,
                       state: $v.state, reason: ($v.stateReason // null), merged: ($v.merged // null),
                       author: $v.author.login} end)}] | from_entries)' \
    "$OUT/refs.json" > "$OUT/refs.next" && mv "$OUT/refs.next" "$OUT/refs.json"
  batch=""; keys=""; count=0
}
count=0
while IFS= read -r k; do
  [ -n "$k" ] || continue
  case "$k" in
    *#*) repo="${k%#*}"; n="${k##*#}" ;;
    *) repo="$REPO"; n="$k" ;;
  esac
  batch="$batch a$count: repository(owner:\"${repo%%/*}\",name:\"${repo#*/}\"){issueOrPullRequest(number:$n){$ISSUE_FIELDS}}"
  keys="$keys $k"
  count=$((count + 1))
  if [ "$count" -ge 50 ]; then resolve; fi
done < "$OUT/mentions.txt"
resolve
rm -f "$OUT/mentions.txt" "$OUT/batch.json"
jq --arg self "$SELF" "$REFS_JQ"' map(.refs = ([(.body, .comments.last[].body) | refkeys($self)[]] + [.crossRefs[].ref] | unique))' \
  "$OUT/issues.json" > "$OUT/issues.next" && mv "$OUT/issues.next" "$OUT/issues.json"

# ----------------------------------------------------------------- context --

labels="$(gh label list -R "$REPO" --limit 1000 --json name,description)" || die 1 "cannot list labels"
types="$(gh api graphql -f o="$OWNER" -f r="$NAME" -f query='query($o:String!,$r:String!){repository(owner:$o,name:$r){issueTypes(first:50){nodes{name description}}}}' \
  --jq '[.data.repository.issueTypes.nodes[]?]' 2>/dev/null || echo '[]')"
jq -n --arg repo "$REPO" --argjson l "$labels" --argjson t "$types" '{repo: $repo, labels: $l, types: $t}' > "$OUT/context.json"

# ---------------------------------------------------------------- clusters --

# Edges between open issues in scope: parent, cross-reference, a mention either way, and a
# reference to the same issue in another repository.
jq -r --arg self "$SELF" --slurpfile all "$OUT/issues.json" "$REFS_JQ"'
  ([$all[0][].number]) as $open
  | [ .[] | {n: .number, r: [(.body, .comments.last[].body) | refkeys($self)[]]} ] as $mentions
  | ( .[] | .number as $a
      | ( [.parent], [.crossRefs[] | select(.kind == "issue" and (.ref | test("^[0-9]+$"))) | .ref | tonumber],
          [$mentions[] | select(.n == $a) | .r[] | select(test("^[0-9]+$")) | tonumber] )
      | .[] | select(. != null and . != $a) | select(. as $b | $open | index($b)) | "\($a) \(.)" ),
    ( [$mentions[] | .n as $n | .r[] | select(contains("#")) | {k: ., n: $n}] | group_by(.k)[]
      | select(length > 1) | "\(.[0].n) \(.[1:][].n)" )' \
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

# ----------------------------------------------------------------- similar --

# Pairs whose titles share most of their words: duplicate candidates nobody linked. A hint for
# batching, never an edge and never proof.
jq -r '
  def words: ascii_downcase | [scan("[a-z0-9]+") | select(length > 2)]
    - ["the","and","for","not","with","when","from","after","before","should","does","into","that","this","can","cannot","doesn","don","are","its","while"]
    | unique;
  [.[] | {n: .number, w: (.title | words)} | select(.w | length >= 2)] as $t
  | range(0; $t | length) as $i | range($i + 1; $t | length) as $j
  | ($t[$i].w - ($t[$i].w - $t[$j].w) | length) as $shared
  | ($shared / (($t[$i].w + $t[$j].w | unique) | length)) as $score
  | select($shared >= 2 and $score >= 0.4)
  | "\($t[$i].n)\t\($t[$j].n)\t\($score * 100 | floor)"' "$OUT/issues.json" > "$OUT/similar.tsv"

echo "issues $(jq length "$OUT/issues.json") refs $(jq length "$OUT/refs.json") unresolved $(jq '[.[] | select(. == null)] | length' "$OUT/refs.json") foreign $(jq '[keys[] | select(contains("#"))] | length' "$OUT/refs.json") clusters $(wc -l < "$OUT/clusters.tsv" | tr -d ' ') similar $(wc -l < "$OUT/similar.tsv" | tr -d ' ')"
