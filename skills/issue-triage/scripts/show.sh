#!/usr/bin/env bash
# show.sh — print issues as plain text for a worker or a judge to read.
#
#   show.sh <run dir> N [N ...]
#
# Per issue: title, state, type, labels, milestone, assignees, parent, the lint line, the body,
# every comment, and each reference it makes resolved through refs.json. An issue in issues.json
# with no more comments than were fetched is printed offline; any other — a long thread, a closed
# or cited issue — is read with gh. Read-only. Exit 1 on a gh failure, 2 on bad arguments.

set -euo pipefail

die() { local code="$1"; shift; echo "show.sh: $*" >&2; exit "$code"; }

DIR="${1:-}"
[ -n "$DIR" ] && [ $# -ge 2 ] || die 2 "usage: show.sh <run dir> N [N ...]"
shift
[ -f "$DIR/context.json" ] || die 2 "no context.json in $DIR — run fetch.sh first"
command -v jq >/dev/null 2>&1 || die 1 "jq is required"
REPO="$(jq -r .repo "$DIR/context.json")"
[ -f "$DIR/lint.json" ] && LINT="$DIR/lint.json" || LINT=/dev/null

for n in "$@"; do
  printf '%s' "$n" | grep -qE '^[0-9]+$' || die 2 "not an issue number: $n"
  local_issue="$(jq -c --argjson n "$n" '.[] | select(.number == $n)' "$DIR/issues.json" 2>/dev/null || true)"
  if [ -n "$local_issue" ] && [ "$(jq '.comments.total <= (.comments.last | length)' <<< "$local_issue")" = true ]; then
    issue="$(jq -c '. + {state: "OPEN", comments: .comments.last}' <<< "$local_issue")"
  else
    issue="$(gh issue view "$n" -R "$REPO" --json number,title,state,stateReason,body,labels,assignees,milestone,author,createdAt,updatedAt,comments \
      --jq '{number, title, state, reason: .stateReason, body, createdAt, updatedAt, author: .author.login,
             labels: [.labels[].name], assignees: [.assignees[].login], milestone: .milestone.title,
             comments: [.comments[] | {author: .author.login, role: .authorAssociation, createdAt, body}]}')" \
      || die 1 "cannot read #$n in $REPO"
    [ -z "$local_issue" ] || issue="$(jq -c --argjson l "$local_issue" '. + {type: $l.type, parent: $l.parent, refs: $l.refs}' <<< "$issue")"
  fi
  jq -r --slurpfile refs "$DIR/refs.json" --slurpfile lint <(cat "$LINT" 2>/dev/null || echo '{}') '
    ($lint[0][.number | tostring] // null) as $l
    | "#### #\(.number) \(.title)",
      "state \(.state)\(if .reason then " (\(.reason | ascii_downcase))" else "" end) · type \(.type // "none") · labels \((.labels // []) | join(", ") | if . == "" then "none" else . end) · milestone \(.milestone // "none")",
      "author \(.author)\(if .authorRole then " (\(.authorRole | ascii_downcase))" else "" end) · assignees \((.assignees // []) | join(", ") | if . == "" then "none" else . end) · parent \(if .parent then "#\(.parent)" else "none" end) · created \(.createdAt[0:10]) · updated \(.updatedAt[0:10])",
      (if $l then "lint: type \($l.type // "-") · owner \($l.owner // "-") · \($l.flags | join(", ") | if . == "" then "no flags" else . end)" else empty end),
      "",
      (.body // "" | if . == "" then "(no body)" else . end),
      "",
      (.comments[] | "-- \(.author)\(if .role then " (\(.role | ascii_downcase))" else "" end), \(.createdAt[0:10]):\n\(.body)\n"),
      (if ((.refs // []) | length) > 0 then
         "References:", (.refs[] | . as $k | ($refs[0][$k]) as $r
           | if $r == null then "  \($k): does not exist or cannot be read"
             else "  \($k): \($r.kind) \($r.state | ascii_downcase)\(if $r.merged then " (merged)" elif $r.reason then " (\($r.reason | ascii_downcase))" else "" end) — \($r.title) — @\($r.author)" end)
       else empty end),
      ""' <<< "$issue"
done
