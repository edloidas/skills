#!/bin/bash
# queue.sh [--owner <login>] [--repo <owner/name>] [--only review|created] [--limit <n>]
# Lists the viewer's open pull requests in one GitHub GraphQL call, in two
# sets: the ones waiting on the viewer's review (review requested from the
# viewer, or already reviewed by the viewer, never the viewer's own), and the
# ones the viewer created. --only keeps one set. Read-only.
#
# Output, one tab-separated line per pull request, sorted by repository then
# number, after a header line:
#   REF       owner/repo#N
#   AUTHOR    login
#   DRAFT     draft | ready
#   WHY       requested,reviewed (either or both) | created
#   MINE      my latest non-comment review state (APPROVED, CHANGES_REQUESTED,
#             COMMENTED, DISMISSED) or none; - on my own pull request
#   MOVED     yes when the head is not the commit my latest review was on, no
#             when it is, - when I have not reviewed or the pull request is mine
#   OTHERS    comments and reviews by other people, bots excluded, after my
#             latest review (since the PR opened when I have not reviewed); on
#             my own pull request, after the later of the head commit and my
#             latest comment or review
#   DECISION  reviewDecision: APPROVED | CHANGES_REQUESTED | REVIEW_REQUIRED | NONE
#   THREADS   unresolved review threads
#   CI        SUCCESS | FAILURE | PENDING | ERROR | NONE
#   MERGE     mergeStateStatus (CLEAN, DIRTY, BLOCKED, UNSTABLE, UNKNOWN, ...)
#   HEAD      first 9 characters of the head commit
#   UPDATED   updatedAt, ISO 8601
#   TITLE     title
#
# A search that returns --limit results, or a pull request whose reviews,
# comments or threads fill the fetched window, prints `WARN: ...` on stderr:
# the queue or that row's counts may be incomplete.
#
# Requires gh (authenticated) and jq.
# Exit codes: 0 = listed (possibly empty), 1 = gh or jq failed, 2 = usage

set -uo pipefail

USAGE="usage: queue.sh [--owner <login>] [--repo <owner/name>] [--only review|created] [--limit <n>]"
OWNER=""
REPO=""
ONLY=""
LIMIT=50
while [ $# -gt 0 ]; do
  case "$1" in
    --owner | --repo | --only | --limit)
      [ $# -ge 2 ] || { echo "$USAGE" >&2; exit 2; }
      case "$1" in
        --owner) OWNER="$2" ;;
        --repo) REPO="$2" ;;
        --only) ONLY="$2" ;;
        --limit) LIMIT="$2" ;;
      esac
      shift 2
      ;;
    *)
      echo "$USAGE" >&2
      exit 2
      ;;
  esac
done
case "$LIMIT" in
  '' | *[!0-9]* | 0 | 0*) echo "usage: --limit takes a positive number" >&2; exit 2 ;;
esac
[ -n "$OWNER" ] && [ -z "${OWNER##*[!A-Za-z0-9-]*}" ] && { echo "usage: --owner takes a login" >&2; exit 2; }
if [ -n "$REPO" ]; then
  case "$REPO" in
    */*/* | /* | */) echo "usage: --repo takes owner/name" >&2; exit 2 ;;
    */*) ;;
    *) echo "usage: --repo takes owner/name" >&2; exit 2 ;;
  esac
  [ -z "${REPO##*[!A-Za-z0-9._/-]*}" ] && { echo "usage: --repo takes owner/name" >&2; exit 2; }
fi
case "$ONLY" in
  '') WANT_REVIEW=true; WANT_CREATED=true ;;
  review) WANT_REVIEW=true; WANT_CREATED=false ;;
  created) WANT_REVIEW=false; WANT_CREATED=true ;;
  *) echo "usage: --only takes review or created" >&2; exit 2 ;;
esac

command -v gh > /dev/null 2>&1 || { echo "ERROR: gh not found" >&2; exit 1; }
command -v jq > /dev/null 2>&1 || { echo "ERROR: jq not found" >&2; exit 1; }

ERR=$(mktemp "${TMPDIR:-/tmp}/queue-err.XXXXXX") || exit 1
trap 'rm -f "$ERR"' EXIT

ME=$(gh api user --jq .login 2> "$ERR") || { echo "ERROR: gh api user failed: $(cat "$ERR")" >&2; exit 1; }
[ -n "$ME" ] || { echo "ERROR: could not resolve the viewer login" >&2; exit 1; }

SCOPE="is:pr is:open archived:false"
[ -n "$OWNER" ] && SCOPE="$SCOPE user:$OWNER"
[ -n "$REPO" ] && SCOPE="$SCOPE repo:$REPO"

QUERY='
fragment PR on PullRequest {
  number title url isDraft updatedAt headRefOid mergeStateStatus reviewDecision
  author { login }
  repository { nameWithOwner }
  commits(last: 1) { nodes { commit { committedDate statusCheckRollup { state } } } }
  mine: reviews(last: 20, author: $me) { nodes { state submittedAt commit { oid } } }
  reviews(last: 50) { nodes { author { login __typename } submittedAt } }
  comments(last: 50) { nodes { author { login __typename } createdAt } }
  reviewThreads(first: 100) { nodes { isResolved } }
}
query($requested: String!, $reviewed: String!, $created: String!, $me: String!, $n: Int!,
      $review: Boolean!, $own: Boolean!) {
  requested: search(query: $requested, type: ISSUE, first: $n) @include(if: $review) { nodes { ...PR } }
  reviewed: search(query: $reviewed, type: ISSUE, first: $n) @include(if: $review) { nodes { ...PR } }
  created: search(query: $created, type: ISSUE, first: $n) @include(if: $own) { nodes { ...PR } }
}'

RAW=$(gh api graphql -f query="$QUERY" \
  -F requested="$SCOPE review-requested:$ME -author:$ME" \
  -F reviewed="$SCOPE reviewed-by:$ME -author:$ME" \
  -F created="$SCOPE author:$ME" \
  -F me="$ME" -F n="$LIMIT" -F review="$WANT_REVIEW" -F own="$WANT_CREATED" 2> "$ERR") \
  || { echo "ERROR: gh api graphql failed: $(cat "$ERR")" >&2; exit 1; }

printf '%s' "$RAW" | jq -r --argjson n "$LIMIT" '
  (["requested", "reviewed", "created"][] as $s
    | select((.data[$s].nodes // [] | length) >= $n)
    | "WARN: the \($s) search returned \($n) results; raise --limit"),
  ((.data // {})[] | .nodes[]? | select(.number != null)
    | select((.reviews.nodes | length) >= 50 or (.comments.nodes | length) >= 50
             or ((.reviewThreads.nodes // []) | length) >= 100)
    | "WARN: \(.repository.nameWithOwner)#\(.number) fills the fetched reviews, comments or threads; OTHERS or THREADS may be low")
' | sort -u >&2

printf 'REF\tAUTHOR\tDRAFT\tWHY\tMINE\tMOVED\tOTHERS\tDECISION\tTHREADS\tCI\tMERGE\tHEAD\tUPDATED\tTITLE\n'
printf '%s' "$RAW" | jq -r --arg me "$ME" '
  def tagged($why): (.data[$why].nodes // []) | map(select(.number != null) | . + {why: $why});
  (tagged("requested") + tagged("reviewed") + tagged("created"))
  | group_by(.url)
  | map(.[0] + {why: (map(.why) | unique | sort_by({requested: 0, reviewed: 1, created: 2}[.]) | join(","))})
  | sort_by(.repository.nameWithOwner, .number)
  | .[]
  | (.why == "created") as $own
  | (.mine.nodes // [] | map(select(.state != "PENDING"))) as $mine
  | ($mine | map(select(.state != "COMMENTED")) | last // ($mine | last)) as $verdict
  | ($mine | map(.submittedAt) | max) as $lastMine
  | ([(.reviews.nodes // [])[] | {who: .author.login, bot: (.author.__typename == "Bot"), at: .submittedAt}]
     + [(.comments.nodes // [])[] | {who: .author.login, bot: (.author.__typename == "Bot"), at: .createdAt}]) as $activity
  | (if $own then
       ([.commits.nodes[0].commit.committedDate, $lastMine]
        + [$activity[] | select(.who == $me) | .at] | map(select(. != null)) | max)
     else $lastMine end) as $since
  | ($activity
     | map(select(.who != $me and .who != null and (.bot | not) and ($since == null or .at > $since)))
     | length) as $others
  | [
      "\(.repository.nameWithOwner)#\(.number)",
      (.author.login // "ghost"),
      (if .isDraft then "draft" else "ready" end),
      .why,
      (if $own then "-" else ($verdict.state // "none") end),
      (if $own or $verdict == null then "-" elif $verdict.commit.oid == .headRefOid then "no" else "yes" end),
      ($others | tostring),
      (.reviewDecision // "NONE"),
      ((.reviewThreads.nodes // []) | map(select(.isResolved | not)) | length | tostring),
      (.commits.nodes[0].commit.statusCheckRollup.state // "NONE"),
      (.mergeStateStatus // "UNKNOWN"),
      (.headRefOid[0:9]),
      .updatedAt,
      (.title | gsub("[\t\n]"; " "))
    ]
  | @tsv
' || { echo "ERROR: could not parse the GraphQL response" >&2; exit 1; }
