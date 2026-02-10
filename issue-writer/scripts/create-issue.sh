#!/bin/bash
# create-issue.sh
# Creates a GitHub issue with the provided title and body
# Usage: create-issue.sh --title "Title" --body "Body" [--label "label1,label2"] [--assignee "@me"]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse arguments
TITLE=""
BODY=""
LABELS=""
ASSIGNEE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --title)
            TITLE="$2"
            shift 2
            ;;
        --body)
            BODY="$2"
            shift 2
            ;;
        --body-file)
            BODY_FILE="$2"
            shift 2
            ;;
        --label)
            LABELS="$2"
            shift 2
            ;;
        --assignee)
            ASSIGNEE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate required arguments
if [ -z "$TITLE" ]; then
    echo "ERROR: --title is required"
    echo "Usage: create-issue.sh --title \"Title\" --body \"Body\" [--label \"label\"] [--assignee \"@me\"]"
    exit 1
fi

if [ -z "$BODY" ] && [ -z "$BODY_FILE" ]; then
    echo "ERROR: --body or --body-file is required"
    exit 1
fi

# Check environment
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo "ERROR: Not in a git repository"
    exit 1
fi

if ! command -v gh &> /dev/null; then
    echo "ERROR: GitHub CLI not installed"
    exit 1
fi

echo "=== Creating Issue ==="
echo ""
echo "Title: $TITLE"
echo "Labels: ${LABELS:-none}"
echo "Assignee: ${ASSIGNEE:-none}"
echo ""

# Create the issue
if [ -n "$BODY_FILE" ]; then
    RESULT=$(gh issue create --title "$TITLE" --body-file "$BODY_FILE" ${LABELS:+--label "$LABELS"} ${ASSIGNEE:+--assignee "$ASSIGNEE"} 2>&1)
else
    RESULT=$(gh issue create --title "$TITLE" --body "$BODY" ${LABELS:+--label "$LABELS"} ${ASSIGNEE:+--assignee "$ASSIGNEE"} 2>&1)
fi

echo "=== Issue Created ==="
echo ""
echo "$RESULT"
