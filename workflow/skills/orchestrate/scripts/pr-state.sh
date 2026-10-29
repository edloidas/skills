#!/bin/bash
# pr-state.sh <pr-number> [<owner/repo>] [--budget <minutes>] [--wait <minutes>]
# Reduces a pull request's review state to a few lines, so an orchestrator can
# poll it without reading reviews, threads, or check logs. Read-only gh queries.
# Needs gh (authenticated) and jq.
#
# Output, one KEY=VALUE per line, VERDICT always last:
#   STATE=<OPEN|MERGED|CLOSED> HEAD=<sha7> BASE=<branch>
#   HEAD_MIN=<minutes since this head arrived>
#   CI=<pass|fail|pending|none>        none = no checks reported on the head
#   BOT=<none|requested|reviewed> BOT_MIN=<minutes since the latest unanswered bot request, or ->
#   THREADS=<unresolved bot-rooted threads> HUMAN_THREADS=<unresolved threads a person rooted>
#   MERGEABLE=<MERGEABLE|CONFLICTING|UNKNOWN>
#   VERDICT=merged | closed | act | wait | timeout | done
#
# The head arrived at the latest of: PR creation, the head commit's committer
# date, the last force-push, and the first check suite on the head. The last two
# record the push itself; a commit date alone runs ahead of a slow push.
#
# BOT counts only what concerns this head. A bot request made before the head
# arrived was for an earlier head. A request is answered by a review of this head
# from the same bot, submitted after it. Logins differ by surface (request
# `Copilot`, review `copilot-pull-request-reviewer[bot]`), so they match by prefix.
#
# act     = failing CI, unresolved bot threads, or a conflict. Human threads never
#           make act: no unattended worker resolves them, so they are the caller's
#           to surface.
# wait    = CI running; a requested bot inside its budget (--budget, default 5
#           minutes from its request); within one minute of the head arriving with
#           no bot or no CI yet; within two with mergeability still UNKNOWN.
# timeout = a requested bot has not reviewed this head within the budget.
# done    = nothing pending and nothing to work.
# act wins over wait, and CI pending wins over timeout: CI has no budget here.
# STALE checks, and COMPLETED checks with no conclusion, are ignored.
#
# --wait <minutes> re-checks once a minute while the verdict is wait, for at most
# that many minutes, and prints the last check. VERDICT=wait on return means the
# wait ran out.
#
# Exit codes: 0 = answered, 1 = gh or jq failed, 2 = usage

usage() {
  echo "usage: pr-state.sh <pr-number> [<owner/repo>] [--budget <minutes>] [--wait <minutes>]" >&2
  exit 2
}

N="" REPO="" BUDGET=5 WAIT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --budget)
      BUDGET="${2:-}"
      case "$BUDGET" in '' | *[!0-9]*) usage ;; esac
      shift 2
      ;;
    --wait)
      WAIT="${2:-}"
      case "$WAIT" in '' | *[!0-9]*) usage ;; esac
      shift 2
      ;;
    *)
      if [ -z "$N" ]; then N="$1"; elif [ -z "$REPO" ]; then REPO="$1"; else usage; fi
      shift
      ;;
  esac
done
case "$N" in
  '' | *[!0-9]*) usage ;;
esac

for tool in gh jq; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    echo "ERROR: $tool is not installed" >&2
    exit 1
  fi
done

if [ -z "$REPO" ]; then
  REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null) || REPO=""
  if [ -z "$REPO" ]; then
    echo "ERROR: could not resolve the repository; pass <owner/repo>" >&2
    exit 1
  fi
fi
case "$REPO" in
  */*) ;;
  *) usage ;;
esac

if [ -n "$WAIT" ]; then
  waited=0
  while :; do
    out=$(bash "$0" "$N" "$REPO" --budget "$BUDGET") || exit $?
    if [ "$(printf '%s\n' "$out" | tail -n 1)" != VERDICT=wait ] || [ "$waited" -ge "$WAIT" ]; then
      printf '%s\n' "$out"
      exit 0
    fi
    sleep 60
    waited=$((waited + 1))
  done
fi

fail() {
  echo "ERROR: $1 for #$N failed" >&2
  exit 1
}

US=$(printf '\037')
pr=$(gh pr view "$N" --repo "$REPO" --json state,headRefOid,baseRefName,mergeable,createdAt,commits,statusCheckRollup --jq '
  . as $p
  | [ .state, .headRefOid, .baseRefName, .mergeable, .createdAt,
      ( [ (.commits // [])[] | select(.oid == $p.headRefOid) | .committedDate ] | first // "" ),
      ( [ (.statusCheckRollup // [])[]
          | if .__typename == "StatusContext" then .state
            elif .status != "COMPLETED" then "PENDING"
            else (.conclusion // "IGNORED") end
          | select(. != "STALE" and . != "IGNORED") ]
        | if length == 0 then "none"
          elif any(.[]; . == "FAILURE" or . == "ERROR" or . == "TIMED_OUT" or . == "CANCELLED"
                   or . == "ACTION_REQUIRED" or . == "STARTUP_FAILURE") then "fail"
          elif any(.[]; . == "PENDING" or . == "EXPECTED" or . == "QUEUED" or . == "IN_PROGRESS"
                   or . == "WAITING" or . == "REQUESTED") then "pending"
          else "pass" end ) ]
  | join("\u001f")') || fail "gh pr view"

IFS="$US" read -r state head base mergeable created committed ci <<EOF2
$pr
EOF2

if [ -z "$head" ]; then
  echo "ERROR: gh pr view $N returned no head commit" >&2
  exit 1
fi

# One line per event: R <bot login> <time> for a bot review request, P <time> for a force-push.
events=$(gh api --paginate "repos/$REPO/issues/$N/timeline" --jq '.[]
  | if .event == "review_requested" and .requested_reviewer.type == "Bot"
      then "R \(.requested_reviewer.login) \(.created_at)"
    elif .event == "head_ref_force_pushed" then "P \(.created_at)"
    else empty end') || fail "timeline query"
suite=$(gh api "repos/$REPO/commits/$head/check-suites" \
  --jq '[.check_suites[].created_at] | min // ""') || fail "check suites query"
reviews=$(gh api --paginate "repos/$REPO/pulls/$N/reviews" \
  --jq ".[] | select(.user.type == \"Bot\" and .commit_id == \"$head\") | \"V \(.user.login) \(.submitted_at)\"") ||
  fail "reviews query"

head_at=$(printf '%s\n' "$created" "$committed" "$suite" \
  "$(printf '%s\n' "$events" | awk '$1 == "P" { print $2 }')" | grep . | sort | tail -n 1)
case "$head_at" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;;
  *)
    echo "ERROR: unexpected timestamp '$head_at' for #$N" >&2
    exit 1
    ;;
esac

minutes_since() {
  jq -rn --arg t "$1" '(now - ($t | fromdateiso8601)) / 60 | floor'
}

# Prints: <none|requested|reviewed> <time of the latest unanswered request, or ->
bot_state=$(printf '%s\n%s\n' "$events" "$reviews" | awk -v h="$head_at" '
  function norm(s) { s = tolower(s); sub(/\[bot\]$/, "", s); return s }
  $1 == "V" { nv++; vl[nv] = norm($2); vt[nv] = $3; next }
  $1 == "R" && $3 >= h { nr++; rl[nr] = norm($2); rt[nr] = $3 }
  END {
    last = ""
    for (i = 1; i <= nr; i++) {
      answered = 0
      for (j = 1; j <= nv; j++)
        if ((index(vl[j], rl[i]) == 1 || index(rl[i], vl[j]) == 1) && vt[j] >= rt[i]) answered = 1
      if (!answered && rt[i] > last) last = rt[i]
    }
    if (last != "") print "requested", last
    else if (nv > 0) print "reviewed", "-"
    else print "none", "-"
  }')
bot="${bot_state%% *}"
bot_at="${bot_state#* }"

head_min=$(minutes_since "$head_at") || fail "time arithmetic"
bot_min=-
if [ "$bot" = requested ]; then
  bot_min=$(minutes_since "$bot_at") || fail "time arithmetic"
fi

threads=$(gh api graphql -F owner="${REPO%%/*}" -F name="${REPO#*/}" -F number="$N" -f query='
  query($owner: String!, $name: String!, $number: Int!) {
    repository(owner: $owner, name: $name) {
      pullRequest(number: $number) {
        reviewThreads(first: 100) {
          pageInfo { hasNextPage }
          nodes { isResolved comments(first: 1) { nodes { author { __typename } } } }
        }
      }
    }
  }' --jq '.data.repository.pullRequest.reviewThreads
    | [ .nodes[] | select(.isResolved | not) | .comments.nodes[0].author.__typename ] as $open
    | if .pageInfo.hasNextPage then "100+ 100+"
      else "\([$open[] | select(. == "Bot")] | length) \([$open[] | select(. != "Bot")] | length)" end') ||
  fail "review threads query"
bot_threads="${threads%% *}"
human_threads="${threads#* }"

echo "STATE=$state HEAD=$(printf '%s' "$head" | cut -c1-7) BASE=$base"
echo "HEAD_MIN=$head_min"
echo "CI=$ci"
echo "BOT=$bot BOT_MIN=$bot_min"
echo "THREADS=$bot_threads HUMAN_THREADS=$human_threads"
echo "MERGEABLE=$mergeable"

if [ "$state" = MERGED ]; then
  verdict=merged
elif [ "$state" = CLOSED ]; then
  verdict=closed
elif [ "$ci" = fail ] || [ "$bot_threads" != 0 ] || [ "$mergeable" = CONFLICTING ]; then
  verdict=act
elif [ "$ci" = pending ]; then
  verdict=wait
elif [ "$bot" = requested ]; then
  if [ "$bot_min" -ge "$BUDGET" ]; then verdict=timeout; else verdict=wait; fi
elif [ "$head_min" -lt 1 ] && { [ "$bot" = none ] || [ "$ci" = none ]; }; then
  verdict=wait
elif [ "$mergeable" = UNKNOWN ] && [ "$head_min" -lt 2 ]; then
  verdict=wait
else
  verdict=done
fi
echo "VERDICT=$verdict"
