#!/bin/bash
# create-issue.sh [--started-at ISO8601] (--project <title>... | --no-project) -- <gh issue create args...>
# Runs gh issue create once. If gh reports failure after creating the issue,
# reconcile recent issues by exact title, author, and creation window, then reuse it.
# Refuses before creating anything when the project decision is missing, or when the
# repository has issue types and no --type was passed. Adds the created issue to every
# --project, in the issue's own repository.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STARTED_AT=""
PROJECTS=()
NO_PROJECT=""
while [[ "$#" -gt 0 && "$1" != "--" ]]; do
  case "$1" in
    --started-at)
      if [[ -z "${2:-}" ]]; then
        echo "ERROR: --started-at requires an ISO8601 timestamp" >&2
        exit 2
      fi
      STARTED_AT="$2"
      shift 2
      ;;
    --project)
      if [[ -z "${2:-}" ]]; then
        echo "ERROR: --project requires a project title" >&2
        exit 2
      fi
      PROJECTS=(${PROJECTS[@]+"${PROJECTS[@]}"} "$2")
      shift 2
      ;;
    --no-project)
      NO_PROJECT=1
      shift
      ;;
    *)
      echo "ERROR: Unknown wrapper option: $1 (gh issue create arguments go after --)" >&2
      exit 2
      ;;
  esac
done

if [[ "${1:-}" = "--" ]]; then
  shift
fi

if [[ "$#" -eq 0 ]]; then
  echo "ERROR: Expected gh issue create arguments" >&2
  exit 2
fi

if [[ "${#PROJECTS[@]}" -eq 0 && -z "$NO_PROJECT" ]]; then
  echo "ERROR: No project decision. Pass --project \"<title>\" (repeatable) or --no-project before --; nothing was created." >&2
  exit 2
fi
if [[ "${#PROJECTS[@]}" -gt 0 && -n "$NO_PROJECT" ]]; then
  echo "ERROR: --project and --no-project are mutually exclusive; nothing was created." >&2
  exit 2
fi

if [[ -z "$STARTED_AT" ]]; then
  STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
fi

ARGS=("$@")
TITLE=""
REPO=""
HAS_TYPE=""
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
    --type|--type=*)
      HAS_TYPE=1
      ;;
  esac
  i=$((i + 1))
done

if [[ -z "$HAS_TYPE" ]]; then
  if TYPES=$(bash "$SCRIPT_DIR/issue-types.sh" ${REPO:+"$REPO"} 2>/dev/null); then
    if [[ -n "$TYPES" ]]; then
      echo "ERROR: This repository has issue types; pass --type with one of the following. Nothing was created." >&2
      printf '%s\n' "$TYPES" | sed 's/^/  /' >&2
      exit 2
    fi
  else
    echo "WARNING: Could not check issue types; creating without --type" >&2
  fi
fi

add_to_projects() {
  local url="$1" number repo project failed=""
  if [[ "${#PROJECTS[@]}" -eq 0 ]]; then
    return 0
  fi
  number="${url##*/}"
  repo="${url#https://*/}"
  repo="${repo%/issues/*}"
  if [[ ! "$number" =~ ^[0-9]+$ || "$repo" != */* ]]; then
    echo "ERROR: Issue created, but its URL could not be parsed ($url); add it to the project manually. Do not create it again." >&2
    exit 3
  fi
  for project in "${PROJECTS[@]}"; do
    bash "$SCRIPT_DIR/add-to-project.sh" --repo "$repo" "$number" "$project" >&2 || failed="$failed '$project'"
  done
  if [[ -n "$failed" ]]; then
    echo "ERROR: Issue created at $url but not added to:$failed. Add it with add-to-project.sh --repo $repo $number <title>; do not create it again." >&2
    exit 3
  fi
}

OUT_FILE=$(mktemp "${TMPDIR:-/tmp}/issue-create-out.XXXXXX")
ERR_FILE=$(mktemp "${TMPDIR:-/tmp}/issue-create-err.XXXXXX")

set +e
gh issue create "${ARGS[@]}" >"$OUT_FILE" 2>"$ERR_FILE"
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  cat "$OUT_FILE"
  CREATED_URL=$(grep -o 'https://[^[:space:]]*/issues/[0-9]*' "$OUT_FILE" | tail -1 || true)
  rm -f "$OUT_FILE" "$ERR_FILE"
  add_to_projects "$CREATED_URL"
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
  add_to_projects "$REUSE_URL"
  exit 0
fi

cat "$ERR_FILE" >&2
echo "ERROR: gh issue create failed; checked recent issues and found no matching issue to reuse. Do not retry without manual reconciliation." >&2
rm -f "$OUT_FILE" "$ERR_FILE"
exit "$STATUS"
