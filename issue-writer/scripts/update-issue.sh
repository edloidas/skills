#!/bin/bash
# update-issue.sh
# Updates an existing GitHub issue
# Usage: update-issue.sh --issue <number> [--title "New title"] [--body "New body"] [--body-file file] [--add-label "label"] [--remove-label "label"]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Parse arguments
ISSUE=""
TITLE=""
BODY=""
BODY_FILE=""
ADD_LABELS=()
REMOVE_LABELS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --issue)
            ISSUE="$2"
            shift 2
            ;;
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
        --add-label)
            ADD_LABELS+=("$2")
            shift 2
            ;;
        --remove-label)
            REMOVE_LABELS+=("$2")
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Validate required arguments
if [ -z "$ISSUE" ]; then
    echo "ERROR: --issue is required"
    echo "Usage: update-issue.sh --issue <number> [--title \"Title\"] [--body \"Body\"] [--add-label \"label\"] [--remove-label \"label\"]"
    exit 1
fi

# Check that at least one modification is specified
if [ -z "$TITLE" ] && [ -z "$BODY" ] && [ -z "$BODY_FILE" ] && [ ${#ADD_LABELS[@]} -eq 0 ] && [ ${#REMOVE_LABELS[@]} -eq 0 ]; then
    echo "ERROR: At least one modification required (--title, --body, --body-file, --add-label, or --remove-label)"
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

# Extract issue number from URL if provided
if [[ "$ISSUE" =~ ^#?([0-9]+)$ ]]; then
    ISSUE_NUM="${BASH_REMATCH[1]}"
elif [[ "$ISSUE" =~ github\.com/[^/]+/[^/]+/issues/([0-9]+) ]]; then
    ISSUE_NUM="${BASH_REMATCH[1]}"
elif [[ "$ISSUE" =~ ^[^/]+/[^#]+#([0-9]+)$ ]]; then
    ISSUE_NUM="${BASH_REMATCH[1]}"
else
    ISSUE_NUM="$ISSUE"
fi

echo "=== Updating Issue #$ISSUE_NUM ==="
echo ""

# Build arguments array
GH_ARGS=("issue" "edit" "$ISSUE_NUM")

if [ -n "$TITLE" ]; then
    GH_ARGS+=("--title" "$TITLE")
    echo "Title: $TITLE"
fi

if [ -n "$BODY_FILE" ]; then
    GH_ARGS+=("--body-file" "$BODY_FILE")
    echo "Body: (from file $BODY_FILE)"
elif [ -n "$BODY" ]; then
    GH_ARGS+=("--body" "$BODY")
    echo "Body: (updated)"
fi

for label in "${ADD_LABELS[@]}"; do
    GH_ARGS+=("--add-label" "$label")
    echo "Add label: $label"
done

for label in "${REMOVE_LABELS[@]}"; do
    GH_ARGS+=("--remove-label" "$label")
    echo "Remove label: $label"
done

echo ""

# Execute the update
RESULT=$(gh "${GH_ARGS[@]}" 2>&1)

echo "=== Issue Updated ==="
echo ""
echo "$RESULT"
