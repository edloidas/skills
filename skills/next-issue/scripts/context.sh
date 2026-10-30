#!/bin/bash
# context.sh
# Gathers where the work currently is, for next-issue Phase 1. Run from inside
# the repository. Read-only: it does not fetch, so base history is as of the
# last fetch.
#
# Output, header lines first:
#   login: <login>
#   repo: <owner/repo>
#   default-branch: <branch>
#   branch: <current branch, empty when detached>
#   base-ref: origin/<default> | <default> | none
#   current: <N> <OPEN|CLOSED> | none        (from issue-<N>, <N>-*, <type>/<N>-*)
# then tab-separated sections, each under a `== <name> ==` line:
#   open-prs         number, author, head, base, closing issue numbers (comma-joined)
#   recently-closed  number, closedAt, title (10, newest update first)
#   base-log         the last 15 non-merge commits, `<sha> <subject>`
#   hot-paths        count, path two levels deep, from the last 8 non-merge
#                    commits, release commits skipped
#   refs             one line per resolved number in recently-closed, the base
#                    log's `#<N>`, and current:
#                    number, issue|pr, state, issue number (the PR's closing
#                    issue for a pr), parent number, parent state, parent title
#                    (`-` where there is none)
# and last, one line per check that did not run:
#   unavailable: <what> — <why>
#
# Exit codes: 0 printed, 3 gh not authenticated, 4 gh or jq missing,
# 5 not inside a GitHub repository.

set -u

die() {
  echo "$2" >&2
  exit "$1"
}

command -v gh >/dev/null 2>&1 || die 4 "next-issue needs the gh CLI."
command -v jq >/dev/null 2>&1 || die 4 "next-issue needs jq."

LOGIN="$(gh api user --jq .login 2>/dev/null)" || LOGIN=""
[ -n "$LOGIN" ] || die 3 "Run gh auth login first."

REPO_LINE="$(gh repo view --json nameWithOwner,defaultBranchRef \
  --jq '.nameWithOwner + " " + .defaultBranchRef.name' 2>/dev/null)" || REPO_LINE=""
[ -n "$REPO_LINE" ] || die 5 "Not inside a GitHub repository."
REPO="${REPO_LINE%% *}"
DEFAULT="${REPO_LINE#* }"
OWNER="${REPO%%/*}"
NAME="${REPO#*/}"

TAB="$(printf '\t')"
UNAVAILABLE=""
unavailable() {
  UNAVAILABLE="${UNAVAILABLE}unavailable: $1 — $2
"
}

BRANCH="$(git branch --show-current 2>/dev/null)" || BRANCH=""

CURRENT=""
case "$BRANCH" in
  issue-[0-9]*) CURRENT="${BRANCH#issue-}" ;;
  [0-9]*-*) CURRENT="${BRANCH%%-*}" ;;
  */[0-9]*-*) CURRENT="${BRANCH#*/}"; CURRENT="${CURRENT%%-*}" ;;
esac
CURRENT="${CURRENT%%[!0-9]*}"

BASE_REF="none"
if git rev-parse --verify --quiet "refs/remotes/origin/$DEFAULT" >/dev/null 2>&1; then
  BASE_REF="origin/$DEFAULT"
elif git rev-parse --verify --quiet "refs/heads/$DEFAULT" >/dev/null 2>&1; then
  BASE_REF="$DEFAULT"
else
  unavailable "base history" "neither origin/$DEFAULT nor $DEFAULT resolves"
fi

PRS="$(gh pr list --repo "$REPO" --state open --limit 100 \
  --json number,author,headRefName,baseRefName,closingIssuesReferences \
  --jq '.[]|[.number,.author.login,.headRefName,.baseRefName,([.closingIssuesReferences[].number]|join(","))]|@tsv' 2>&1)" \
  || { unavailable "open PRs" "$(printf '%s' "$PRS" | head -n 1)"; PRS=""; }

CLOSED="$(gh issue list --repo "$REPO" --state closed --limit 10 \
  --search "reason:completed sort:updated-desc" --json number,title,closedAt \
  --jq '.[]|[.number,.closedAt,.title]|@tsv' 2>&1)" \
  || { unavailable "recently closed" "$(printf '%s' "$CLOSED" | head -n 1)"; CLOSED=""; }

LOG=""
HOT=""
if [ "$BASE_REF" != "none" ]; then
  LOG="$(git log --oneline --no-merges -15 "$BASE_REF" 2>&1)" \
    || { unavailable "base history" "$(printf '%s' "$LOG" | head -n 1)"; LOG=""; }
  # `@@@` marks each commit's subject line, so a release commit's files can
  # be dropped with it.
  HOT="$(git log --no-merges --name-only --format='@@@%s' -8 "$BASE_REF" | awk '
    /^@@@/ {
      s = tolower(substr($0, 4))
      skip = (s ~ /(^|: )(release|bump version)/ || s ~ /^v?[0-9]+\.[0-9]+\.[0-9]+$/)
      next
    }
    NF && !skip {
      n = split($0, p, "/")
      if (n == 1) path = p[1]
      else if (n == 2) path = p[1]
      else path = p[1] "/" p[2]
      count[path]++
    }
    END { for (k in count) printf "%d\t%s\n", count[k], k }
  ' | sort -k1,1nr -k2,2)"
fi

# Numbers to resolve: recently closed, `#<N>` in commit subjects (a squash
# merge appends a PR number, so these may be pull requests), and current.
NUMBERS="$( {
  printf '%s\n' "$CLOSED" | cut -f1
  printf '%s\n' "$LOG" | grep -o '#[0-9][0-9]*' | tr -d '#'
  printf '%s\n' "$CURRENT"
} | grep -E '^[0-9]+$' | sort -n -u)"

REFS=""
CURRENT_STATE=""
if [ -n "$NUMBERS" ]; then
  aliases=""
  for n in $NUMBERS; do
    aliases="$aliases
  r$n: issueOrPullRequest(number: $n) {
    ... on Issue { number state parent { number title state } }
    ... on PullRequest { number state closingIssuesReferences(first: 5) {
      nodes { number state parent { number title state } } } } }"
  done
  query="query(\$owner: String!, \$name: String!) { repository(owner: \$owner, name: \$name) {$aliases
} }"
  err_file="$(mktemp "${TMPDIR:-/tmp}/next-issue-context.XXXXXX")"
  RESPONSE="$(gh api graphql -f owner="$OWNER" -f name="$NAME" -f query="$query" 2>"$err_file")"
  err="$(cat "$err_file")"
  rm -f "$err_file"

  # gh exits 1 on any GraphQL error, so the response decides. `undefinedField`
  # means this host has no sub-issues: no parents at all. A `NOT_FOUND` on one
  # alias means that number is gone: drop it and keep the rest of `data`.
  if ! printf '%s' "$RESPONSE" | jq -e 'type == "object"' >/dev/null 2>&1; then
    unavailable "parents" "$(printf '%s' "${err:-no response}" | head -n 1)"
  elif printf '%s' "$RESPONSE" | jq -e '[.errors[]? | select(.extensions.code == "undefinedField")] | length > 0' >/dev/null; then
    unavailable "parents" "$(printf '%s' "$RESPONSE" | jq -r '[.errors[] | select(.extensions.code == "undefinedField")][0].message')"
  else
    other="$(printf '%s' "$RESPONSE" | jq -r '[.errors[]? | select((.type // .extensions.code) != "NOT_FOUND") | .message] | first // empty')"
    [ -z "$other" ] || unavailable "parents" "$other"
    REFS="$(printf '%s' "$RESPONSE" | jq -r '
      def p: if .parent then [(.parent.number|tostring), .parent.state, .parent.title] else ["-", "-", "-"] end;
      (.data.repository // {}) | to_entries[] | .value | select(. != null)
      | if .closingIssuesReferences then
          (if (.closingIssuesReferences.nodes | length) == 0
           then [(.number|tostring), "pr", .state, "-", "-", "-", "-"]
           else (. as $pr | .closingIssuesReferences.nodes[]
                 | [($pr.number|tostring), "pr", $pr.state, (.number|tostring)] + p) end)
        else [(.number|tostring), "issue", .state, (.number|tostring)] + p end
      | @tsv' | sort -u | sort -t "$TAB" -k1,1n -k4,4n)"
    if [ -n "$CURRENT" ]; then
      CURRENT_STATE="$(printf '%s\n' "$REFS" | awk -F '\t' -v n="$CURRENT" '$1 == n && $2 == "issue" { print $3; exit }')"
    fi
  fi
fi

printf 'login: %s\n' "$LOGIN"
printf 'repo: %s\n' "$REPO"
printf 'default-branch: %s\n' "$DEFAULT"
printf 'branch: %s\n' "$BRANCH"
printf 'base-ref: %s\n' "$BASE_REF"
if [ -n "$CURRENT" ]; then
  printf 'current: %s %s\n' "$CURRENT" "${CURRENT_STATE:-UNKNOWN}"
else
  printf 'current: none\n'
fi
section() {
  printf '== %s ==\n' "$1"
  [ -z "$2" ] || printf '%s\n' "$2"
}
section open-prs "$PRS"
section recently-closed "$CLOSED"
section base-log "$LOG"
section hot-paths "$HOT"
section refs "$REFS"
printf '%s' "$UNAVAILABLE"
