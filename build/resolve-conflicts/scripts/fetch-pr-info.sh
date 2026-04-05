#!/bin/bash
# fetch-pr-info.sh
# Fetches PR metadata from GitHub. Accepts PR number, PR URL, issue number, or issue URL.
# If given an issue, attempts to find a linked PR.
#
# Usage: fetch-pr-info.sh <input>
#
# Input formats:
#   123                                          # PR or issue number
#   https://github.com/owner/repo/pull/123       # PR URL
#   https://github.com/owner/repo/issues/123     # Issue URL
#   owner/repo#123                               # Shorthand
#
# Output format (key=value, one per line):
#   type=pr
#   number=123
#   title=Fix something important
#   head=issue-123
#   base=master
#   url=https://github.com/owner/repo/pull/123
#   mergeable_state=dirty|clean|unknown
#
# Exit codes:
#   0 = success, PR found
#   1 = input parsing failed
#   2 = gh CLI not authenticated or not installed
#   3 = PR/issue not found
#   4 = issue has no linked PR
#   5 = PR has no conflicts (mergeable_state is clean)

set -e

INPUT="$1"

if [[ -z "$INPUT" ]]; then
    echo "ERROR: No input provided" >&2
    echo "Usage: fetch-pr-info.sh <PR number|PR URL|issue number|issue URL>" >&2
    exit 1
fi

# Check gh is available and authenticated
if ! command -v gh &> /dev/null; then
    echo "ERROR: gh CLI not installed" >&2
    exit 2
fi

if ! command -v jq &> /dev/null; then
    echo "ERROR: jq not installed" >&2
    exit 2
fi

if ! gh auth status > /dev/null 2>&1; then
    echo "ERROR: gh CLI not authenticated. Run 'gh auth login'" >&2
    exit 2
fi

# Parse input to determine type and number
REPO=""
NUMBER=""
INPUT_TYPE=""

# GitHub PR URL: https://github.com/owner/repo/pull/123
if [[ "$INPUT" =~ github\.com/([^/]+/[^/]+)/pull/([0-9]+) ]]; then
    REPO="${BASH_REMATCH[1]}"
    NUMBER="${BASH_REMATCH[2]}"
    INPUT_TYPE="pr"
# GitHub issue URL: https://github.com/owner/repo/issues/123
elif [[ "$INPUT" =~ github\.com/([^/]+/[^/]+)/issues/([0-9]+) ]]; then
    REPO="${BASH_REMATCH[1]}"
    NUMBER="${BASH_REMATCH[2]}"
    INPUT_TYPE="issue"
# Shorthand: owner/repo#123
elif [[ "$INPUT" =~ ^([^/]+/[^#]+)#([0-9]+)$ ]]; then
    REPO="${BASH_REMATCH[1]}"
    NUMBER="${BASH_REMATCH[2]}"
    INPUT_TYPE="unknown"
# Plain number: could be PR or issue
elif [[ "$INPUT" =~ ^[0-9]+$ ]]; then
    NUMBER="$INPUT"
    INPUT_TYPE="unknown"
else
    echo "ERROR: Cannot parse input: $INPUT" >&2
    echo "Expected: PR number, PR URL, issue number, or issue URL" >&2
    exit 1
fi

# Build repo args for gh commands
REPO_ARGS=()
if [[ -n "$REPO" ]]; then
    REPO_ARGS=(--repo "$REPO")
fi

# Try to fetch as PR first (unless we know it's an issue)
PR_JSON=""
if [[ "$INPUT_TYPE" != "issue" ]]; then
    PR_JSON=$(gh pr view "$NUMBER" "${REPO_ARGS[@]}" --json number,title,headRefName,baseRefName,url,mergeable,state 2>/dev/null || true)
fi

# If not a PR (or PR fetch failed), try as issue and find linked PR
if [[ -z "$PR_JSON" || "$PR_JSON" == "null" ]]; then
    # Verify the issue exists
    ISSUE_JSON=$(gh issue view "$NUMBER" "${REPO_ARGS[@]}" --json number,title 2>/dev/null || true)

    if [[ -z "$ISSUE_JSON" || "$ISSUE_JSON" == "null" ]]; then
        echo "ERROR: No PR or issue found with number $NUMBER" >&2
        exit 3
    fi

    # Try to find a PR linked to this issue
    # Method 1: Look for a branch named issue-<number> with an open PR
    PR_JSON=$(gh pr list "${REPO_ARGS[@]}" --head "issue-$NUMBER" --json number,title,headRefName,baseRefName,url,mergeable,state --limit 1 2>/dev/null | jq '.[0] // empty' 2>/dev/null || true)

    # Method 2: Search PR body/title for issue reference
    if [[ -z "$PR_JSON" || "$PR_JSON" == "null" ]]; then
        PR_JSON=$(gh pr list "${REPO_ARGS[@]}" --search "#$NUMBER" --json number,title,headRefName,baseRefName,url,mergeable,state --limit 1 2>/dev/null | jq '.[0] // empty' 2>/dev/null || true)
    fi

    if [[ -z "$PR_JSON" || "$PR_JSON" == "null" ]]; then
        ISSUE_TITLE=$(echo "$ISSUE_JSON" | jq -r '.title')
        echo "ERROR: Issue #$NUMBER ($ISSUE_TITLE) has no linked PR" >&2
        exit 4
    fi
fi

# Extract fields from PR JSON
PR_NUMBER=$(echo "$PR_JSON" | jq -r '.number')
PR_TITLE=$(echo "$PR_JSON" | jq -r '.title')
PR_HEAD=$(echo "$PR_JSON" | jq -r '.headRefName')
PR_BASE=$(echo "$PR_JSON" | jq -r '.baseRefName')
PR_URL=$(echo "$PR_JSON" | jq -r '.url')
PR_MERGEABLE=$(echo "$PR_JSON" | jq -r '.mergeable')
PR_STATE=$(echo "$PR_JSON" | jq -r '.state')

# Determine mergeable state
# gh returns: MERGEABLE, CONFLICTING, or UNKNOWN
MERGEABLE_STATE="unknown"
case "$PR_MERGEABLE" in
    MERGEABLE)  MERGEABLE_STATE="clean" ;;
    CONFLICTING) MERGEABLE_STATE="dirty" ;;
    *)          MERGEABLE_STATE="unknown" ;;
esac

# If PR has no conflicts, exit with code 5
if [[ "$MERGEABLE_STATE" == "clean" ]]; then
    echo "type=pr"
    echo "number=$PR_NUMBER"
    echo "title=$PR_TITLE"
    echo "head=$PR_HEAD"
    echo "base=$PR_BASE"
    echo "url=$PR_URL"
    echo "state=$PR_STATE"
    echo "mergeable_state=$MERGEABLE_STATE"
    exit 5
fi

# Output PR info
echo "type=pr"
echo "number=$PR_NUMBER"
echo "title=$PR_TITLE"
echo "head=$PR_HEAD"
echo "base=$PR_BASE"
echo "url=$PR_URL"
echo "state=$PR_STATE"
echo "mergeable_state=$MERGEABLE_STATE"
