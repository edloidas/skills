#!/bin/bash
# fetch-issue.sh <N | #N | https://github.com/<owner>/<repo>/issues/<N>>
# Fetches one issue, its comments, its sub-issues, and the viewer's login in a
# single GraphQL call, and prints one JSON object. Read-only.
#
# A bare number resolves against the current directory's repository; a URL
# uses its own owner/repo, so an issue in another repository works too.
#
# Output fields: repo, login, number, title, body, state (open | closed),
# closed (boolean), url, labels [name], assignees [login],
# comments [{author, body, createdAt}] (the last 100), commentsTotal,
# subIssues [{number, title, body, state}] or null when this host has no
# sub-issues, subIssuesTotal, unavailable [string].
#
# Exit codes: 0 printed, 1 usage, 2 issue or repository not found,
# 3 gh not authenticated, 4 gh or jq missing, 5 any other gh failure.

set -u

die() {
  echo "$2" >&2
  exit "$1"
}

command -v gh >/dev/null 2>&1 || die 4 "fetch-issue: the gh CLI is not installed."
command -v jq >/dev/null 2>&1 || die 4 "fetch-issue: jq is not installed."

[ "$#" -eq 1 ] && [ -n "$1" ] || die 1 "Usage: fetch-issue.sh <issue-number | issue URL>"

is_auth_error() {
  case "$1" in
    *"HTTP 401"*|*"gh auth login"*|*"Bad credentials"*|*"Requires authentication"*) return 0 ;;
  esac
  return 1
}

ARG="${1#\#}"
REPO=""
NUMBER=""

case "$ARG" in
  http://*|https://*)
    path="${ARG#*://}"
    path="${path#*/}"
    path="${path%%[?#]*}"
    path="${path%/}"
    owner="${path%%/*}"; rest="${path#*/}"
    name="${rest%%/*}"; rest="${rest#*/}"
    kind="${rest%%/*}"; NUMBER="${rest#*/}"
    case "$kind" in
      issues) ;;
      *) die 1 "fetch-issue: not an issue URL: $1" ;;
    esac
    REPO="$owner/$name"
    ;;
  *)
    NUMBER="$ARG"
    ;;
esac

case "$NUMBER" in
  ''|*[!0-9]*) die 1 "fetch-issue: not an issue number or URL: $1" ;;
esac

if [ -z "$REPO" ]; then
  err_file="$(mktemp "${TMPDIR:-/tmp}/fetch-issue.XXXXXX")"
  REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>"$err_file")"
  err="$(cat "$err_file")"; rm -f "$err_file"
  if [ -z "$REPO" ]; then
    is_auth_error "$err" && die 3 "Run \`gh auth login\` first."
    die 5 "Provide a full GitHub URL or run from inside a git repository."
  fi
fi

OWNER="${REPO%%/*}"
NAME="${REPO#*/}"

SUB_FIELDS='subIssues(first: 50) { totalCount nodes { number title body state } }'

query_for() {
  printf '%s' 'query($owner: String!, $name: String!, $number: Int!) {
  viewer { login }
  repository(owner: $owner, name: $name) {
    issue(number: $number) {
      number title body state url
      labels(first: 50) { nodes { name } }
      assignees(first: 20) { nodes { login } }
      comments(last: 100) { totalCount nodes { author { login } body createdAt } }
      '"$1"'
    }
  }
}'
}

# gh exits 1 on any GraphQL error but still prints the response, so the
# response decides, not the exit code.
run_query() {
  local err_file
  err_file="$(mktemp "${TMPDIR:-/tmp}/fetch-issue.XXXXXX")"
  RESPONSE="$(gh api graphql -f owner="$OWNER" -f name="$NAME" -F number="$NUMBER" \
    -f query="$(query_for "$1")" 2>"$err_file")"
  GH_ERR="$(cat "$err_file")"
  rm -f "$err_file"
  if ! printf '%s' "$RESPONSE" | jq -e 'type == "object"' >/dev/null 2>&1; then
    is_auth_error "$GH_ERR" && die 3 "Run \`gh auth login\` first."
    die 5 "fetch-issue: gh failed: ${GH_ERR:-no output}"
  fi
}

error_codes() {
  printf '%s' "$RESPONSE" | jq -r '[.errors[]? | (.extensions.code // .type // "")] | join(" ")'
}

UNAVAILABLE='[]'
run_query "$SUB_FIELDS"
codes="$(error_codes)"

case " $codes " in
  *" undefinedField "*)
    msg="$(printf '%s' "$RESPONSE" | jq -r '[.errors[] | select(.extensions.code == "undefinedField") | .message] | first')"
    UNAVAILABLE="$(jq -cn --arg m "subIssues — $msg" '[$m]')"
    run_query ""
    codes="$(error_codes)"
    ;;
esac

case " $codes " in
  *" NOT_FOUND "*)
    if printf '%s' "$RESPONSE" | jq -e '.data.repository == null' >/dev/null 2>&1; then
      die 2 "Repository $REPO not found."
    fi
    die 2 "Issue #$NUMBER not found in $REPO."
    ;;
esac

if [ -n "$codes" ]; then
  die 5 "fetch-issue: $(printf '%s' "$RESPONSE" | jq -r '[.errors[].message] | join("; ")')"
fi

printf '%s' "$RESPONSE" | jq --arg repo "$REPO" --argjson unavailable "$UNAVAILABLE" '
  .data.viewer.login as $login
  | .data.repository.issue
  | {
      repo: $repo,
      login: $login,
      number, title, body,
      state: (.state | ascii_downcase),
      closed: (.state == "CLOSED"),
      url,
      labels: [.labels.nodes[].name],
      assignees: [.assignees.nodes[].login],
      comments: [.comments.nodes[] | {author: (.author.login // "ghost"), body, createdAt}],
      commentsTotal: .comments.totalCount,
      subIssues: (if .subIssues then [.subIssues.nodes[] | {number, title, body, state: (.state | ascii_downcase)}] else null end),
      subIssuesTotal: (.subIssues.totalCount // 0),
      unavailable: $unavailable
    }'
