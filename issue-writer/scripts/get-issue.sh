#!/bin/bash
# get-issue.sh
# Fetches current issue data for viewing or editing
# Usage: get-issue.sh <issue-number-or-url>
# Returns: JSON with title, body, labels, state, number, url

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    echo "ERROR: Not in a git repository"
    exit 1
fi

# Check if gh is available
if ! command -v gh &> /dev/null; then
    echo "ERROR: GitHub CLI not installed"
    exit 1
fi

# Extract issue number from URL if provided
# Supports formats:
#   123
#   #123
#   https://github.com/owner/repo/issues/123
#   owner/repo#123
if [[ "$ISSUE" =~ ^#?([0-9]+)$ ]]; then
    ISSUE_NUM="${BASH_REMATCH[1]}"
elif [[ "$ISSUE" =~ github\.com/[^/]+/[^/]+/issues/([0-9]+) ]]; then
    ISSUE_NUM="${BASH_REMATCH[1]}"
elif [[ "$ISSUE" =~ ^[^/]+/[^#]+#([0-9]+)$ ]]; then
    ISSUE_NUM="${BASH_REMATCH[1]}"
else
    ISSUE_NUM="$ISSUE"
fi

# Fetch issue data
gh issue view "$ISSUE_NUM" --json number,title,body,labels,state,url
