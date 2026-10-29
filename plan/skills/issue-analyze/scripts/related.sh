#!/bin/bash
# related.sh <owner/repo> <N>
# Reads the issues around one issue: its parent and siblings, the issues and
# pull requests that cross-reference it, and what blocks it and what it blocks.
# Two GraphQL calls, kept separate so a host without issue dependencies still
# returns the parent. Read-only.
#
# Output, one tab-separated line per related item:
#   RELATION  parent | sibling | blocker | dependent | mention
#   REF       #M in the same repository, owner/repo#M in another
#   KIND      issue | pr
#   STATE     OPEN | CLOSED | MERGED
#   TITLE
#   NOTE      parent: <closed>/<total> done; mention: closes when the pull
#             request will close <N>; otherwise empty
# then one line per call that did not run:
#   unavailable: <parent|blockedBy> — <GraphQL or gh message>
#
# Exit codes: 0 printed (unavailable calls included), 1 usage,
# 3 gh not authenticated, 4 gh or jq missing.

set -u

die() {
  echo "$2" >&2
  exit "$1"
}

command -v gh >/dev/null 2>&1 || die 4 "related: the gh CLI is not installed."
command -v jq >/dev/null 2>&1 || die 4 "related: jq is not installed."

REPO="${1:-}"
NUMBER="${2:-}"
case "$REPO" in
  */*) ;;
  *) die 1 "Usage: related.sh <owner/repo> <issue-number>" ;;
esac
case "$NUMBER" in
  ''|*[!0-9]*) die 1 "Usage: related.sh <owner/repo> <issue-number>" ;;
esac
OWNER="${REPO%%/*}"
NAME="${REPO#*/}"

PARENT_QUERY='query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) { issue(number: $number) {
    parent { number title state subIssues(first: 50) { nodes { number title state } } }
    timelineItems(first: 50, itemTypes: [CROSS_REFERENCED_EVENT]) { nodes {
      ... on CrossReferencedEvent { willCloseTarget source {
        ... on Issue { __typename number title state repository { nameWithOwner } }
        ... on PullRequest { __typename number title state repository { nameWithOwner } } } } } } } } }'

BLOCKED_QUERY='query($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) { issue(number: $number) {
    blockedBy(first: 10) { nodes { number title state repository { nameWithOwner } } }
    blocking(first: 10) { nodes { number title state repository { nameWithOwner } } } } } }'

# Sets RESPONSE to the parsed response, or prints an unavailable line and
# returns 1. gh exits 1 on any GraphQL error, so the response decides, not the
# exit code. An `errors` entry — `undefinedField` on an older GitHub Enterprise
# Server, a permission refusal, a rate limit — makes the whole call unavailable,
# and `data` is read only from a response with no `errors`.
call() {
  local label="$1" query="$2" err_file err msg
  err_file="$(mktemp "${TMPDIR:-/tmp}/related.XXXXXX")"
  RESPONSE="$(gh api graphql -f owner="$OWNER" -f name="$NAME" -F number="$NUMBER" \
    -f query="$query" 2>"$err_file")"
  err="$(cat "$err_file")"
  rm -f "$err_file"
  if ! printf '%s' "$RESPONSE" | jq -e 'type == "object"' >/dev/null 2>&1; then
    case "$err" in
      *"HTTP 401"*|*"gh auth login"*|*"Bad credentials"*|*"Requires authentication"*)
        die 3 "Run \`gh auth login\` first." ;;
    esac
    msg="$(printf '%s' "${err:-no response}" | head -n 1)"
    UNAVAILABLE="${UNAVAILABLE}unavailable: $label — ${msg#gh: }
"
    return 1
  fi
  if printf '%s' "$RESPONSE" | jq -e '(.errors // []) | length > 0' >/dev/null; then
    msg="$(printf '%s' "$RESPONSE" | jq -r '
      ([.errors[] | select(.extensions.code == "undefinedField")] + .errors)[0].message')"
    UNAVAILABLE="${UNAVAILABLE}unavailable: $label — $msg
"
    return 1
  fi
  return 0
}

UNAVAILABLE=""

if call parent "$PARENT_QUERY"; then
  printf '%s' "$RESPONSE" | jq -r --arg repo "$REPO" --argjson n "$NUMBER" '
    def ref($r; $m): if $r == $repo then "#\($m)" else "\($r)#\($m)" end;
    .data.repository.issue as $i
    | (if $i.parent then
         ($i.parent.subIssues.nodes) as $kids
         | ["parent", "#\($i.parent.number)", "issue", $i.parent.state, $i.parent.title,
            "\([$kids[] | select(.state == "CLOSED")] | length)/\($kids | length) done"],
           ($kids[] | select(.number != $n)
            | ["sibling", "#\(.number)", "issue", .state, .title, ""])
       else empty end),
      ([$i.timelineItems.nodes[] | select(.source.number != null)]
       | unique_by([.source.repository.nameWithOwner, .source.number])[]
       | ["mention", ref(.source.repository.nameWithOwner; .source.number),
          (if .source.__typename == "PullRequest" then "pr" else "issue" end),
          .source.state, .source.title, (if .willCloseTarget then "closes" else "" end)])
    | @tsv'
fi

if call blockedBy "$BLOCKED_QUERY"; then
  printf '%s' "$RESPONSE" | jq -r --arg repo "$REPO" '
    def ref: if .repository.nameWithOwner == $repo then "#\(.number)"
             else "\(.repository.nameWithOwner)#\(.number)" end;
    .data.repository.issue as $i
    | ($i.blockedBy.nodes[] | ["blocker", ref, "issue", .state, .title, ""]),
      ($i.blocking.nodes[] | ["dependent", ref, "issue", .state, .title, ""])
    | @tsv'
fi

printf '%s' "$UNAVAILABLE"
