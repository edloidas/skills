#!/bin/bash
# get-issue.sh
# Fetches current issue data for viewing or editing
# Usage: get-issue.sh <issue-number-or-url>
# Returns: JSON with title, body, labels, state, number, url

set -eo pipefail

# Check argument
if [ -z "$1" ]; then
    echo "ERROR: Issue number or URL required"
    echo "Usage: get-issue.sh <issue-number-or-url>"
    echo "Examples:"
    echo "  get-issue.sh 123"
    echo "  get-issue.sh https://github.com/owner/repo/issues/123"
    exit 1
fi

ISSUE="$1"

# Check if we're in a git repo
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo "ERROR: Not in a git repository. Navigate to a git repository and try again."
    exit 1
fi

# Check if gh is available
if ! command -v gh &> /dev/null; then
    echo "ERROR: GitHub CLI not installed. Install it from https://cli.github.com"
    exit 1
fi

# Extract issue number from URL if provided
# Supports formats:
#   123
#   #123
#   https://github.com/owner/repo/issues/123
#   owner/repo#123
REPO=""
if [[ "$ISSUE" =~ ^#?([0-9]+)$ ]]; then
    ISSUE_NUM="${BASH_REMATCH[1]}"
elif [[ "$ISSUE" =~ github\.com/([^/]+/[^/]+)/issues/([0-9]+) ]]; then
    REPO="${BASH_REMATCH[1]}"
    ISSUE_NUM="${BASH_REMATCH[2]}"
elif [[ "$ISSUE" =~ ^([^/]+/[^#]+)#([0-9]+)$ ]]; then
    REPO="${BASH_REMATCH[1]}"
    ISSUE_NUM="${BASH_REMATCH[2]}"
else
    echo "ERROR: Not an issue reference: $ISSUE (expected 123, #123, owner/repo#123, or an issue URL)"
    exit 1
fi

# Fetch issue data
GH_ARGS=("issue" "view" "$ISSUE_NUM" "--json" "number,title,body,labels,state,url")
[ -n "$REPO" ] && GH_ARGS+=("--repo" "$REPO")
gh "${GH_ARGS[@]}"
