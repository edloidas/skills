#!/bin/bash
# create-issue.sh [--started-at ISO8601] -- <gh issue create args...>
# Runs gh issue create once. If gh reports failure after creating the issue,
# reconcile recent issues by exact title, author, and creation window, then reuse it.

set -e

STARTED_AT=""
if [[ "${1:-}" = "--started-at" ]]; then
  if [[ -z "${2:-}" ]]; then
    echo "ERROR: --started-at requires an ISO8601 timestamp" >&2
    exit 2
  fi
  STARTED_AT="$2"
  shift 2
fi

if [[ "${1:-}" = "--" ]]; then
  shift
fi

if [[ "$#" -eq 0 ]]; then
  echo "ERROR: Expected gh issue create arguments" >&2
  exit 2
fi

if [[ -z "$STARTED_AT" ]]; then
  STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
fi

ARGS=("$@")
TITLE=""
REPO=""
i=0
while [[ "$i" -lt "$#" ]]; do
  arg="${ARGS[$i]}"
  case "$arg" in
    --title)
      next=$((i + 1))
      TITLE="${ARGS[$next]:-}"
      ;;
    --title=*)
      TITLE="${arg#--title=}"
      ;;
    --repo|-R)
      next=$((i + 1))
      REPO="${ARGS[$next]:-}"
      ;;
    --repo=*|-R=*)
      REPO="${arg#*=}"
      ;;
  esac
  i=$((i + 1))
done

OUT_FILE=$(mktemp "${TMPDIR:-/tmp}/issue-create-out.XXXXXX")
ERR_FILE=$(mktemp "${TMPDIR:-/tmp}/issue-create-err.XXXXXX")

set +e
gh issue create "${ARGS[@]}" >"$OUT_FILE" 2>"$ERR_FILE"
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUT_FILE"
  rm -f "$OUT_FILE" "$ERR_FILE"
  exit 0
fi

ENDED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
LOGIN=$(gh api user --jq '.login' 2>/dev/null || true)

REUSE_URL=""
if [[ -n "$TITLE" && -n "$LOGIN" ]]; then
  LIST_ARGS=(issue list --author "$LOGIN" --state all --limit 30 --json number,title,url,createdAt)
  if [[ -n "$REPO" ]]; then
    LIST_ARGS=("${LIST_ARGS[@]}" --repo "$REPO")
  fi

  ISSUES=$(gh "${LIST_ARGS[@]}" 2>/dev/null || true)
  if [[ -n "$ISSUES" ]]; then
    REUSE_URL=$(printf '%s' "$ISSUES" | jq -r \
      --arg title "$TITLE" \
      --arg started "$STARTED_AT" \
      --arg ended "$ENDED_AT" \
      '[.[] | select(.title == $title and .createdAt >= $started and .createdAt <= $ended)]
       | sort_by(.createdAt)
       | reverse
       | if length == 1 then .[0].url else empty end' 2>/dev/null || true)
  fi
fi

if [[ -n "$REUSE_URL" ]]; then
  echo "WARNING: gh issue create failed after creating an issue; reusing $REUSE_URL" >&2
  echo "$REUSE_URL"
  rm -f "$OUT_FILE" "$ERR_FILE"
  exit 0
fi

cat "$ERR_FILE" >&2
echo "ERROR: gh issue create failed; checked recent issues and found no matching issue to reuse. Do not retry without manual reconciliation." >&2
rm -f "$OUT_FILE" "$ERR_FILE"
exit "$STATUS"
