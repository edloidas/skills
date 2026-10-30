#!/bin/bash
# update-issue.sh
# Updates an existing GitHub issue
# Usage: update-issue.sh --issue <number> [--title "New title"] [--body "New body"] [--body-file file] [--add-label "label"] [--remove-label "label"] [--attach path[#alt text]]

set -e

# Parse arguments
ISSUE=""
TITLE=""
BODY=""
BODY_FILE=""
ADD_LABELS=()
REMOVE_LABELS=()
ATTACHMENTS=()

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
        --attach)
            ATTACHMENTS+=("$2")
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
    echo "Usage: update-issue.sh --issue <number> [--title \"Title\"] [--body \"Body\"] [--add-label \"label\"] [--remove-label \"label\"] [--attach \"path#alt\"]"
    exit 1
fi

# Check that at least one modification is specified
if [ -z "$TITLE" ] && [ -z "$BODY" ] && [ -z "$BODY_FILE" ] && [ ${#ADD_LABELS[@]} -eq 0 ] && [ ${#REMOVE_LABELS[@]} -eq 0 ] && [ ${#ATTACHMENTS[@]} -eq 0 ]; then
    echo "ERROR: At least one modification required (--title, --body, --body-file, --add-label, --remove-label, or --attach)"
    exit 1
fi

# An attachment path must exist locally; gh reports this late and after other edits land
if [ ${#ATTACHMENTS[@]} -gt 0 ]; then
    for attachment in "${ATTACHMENTS[@]}"; do
        if [ ! -f "${attachment%%#*}" ]; then
            echo "ERROR: --attach file not found: ${attachment%%#*}"
            exit 1
        fi
    done
fi

# Check environment
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo "ERROR: Not in a git repository. Navigate to a git repository and try again."
    exit 1
fi

if ! command -v gh &> /dev/null; then
    echo "ERROR: GitHub CLI not installed. Install with: brew install gh"
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

for attachment in "${ATTACHMENTS[@]}"; do
    GH_ARGS+=("--attach" "$attachment")
    echo "Attach: ${attachment%%#*}"
done

echo ""

# Execute the update.
# gh exits nonzero when some attachments fail to upload even though the edit landed,
# so the output is reported either way and the status is passed through.
set +e
RESULT=$(gh "${GH_ARGS[@]}" 2>&1)
STATUS=$?
set -e

if [ "$STATUS" -eq 0 ]; then
    echo "=== Issue Updated ==="
else
    echo "=== Issue Update Incomplete (gh exit $STATUS) ==="
    echo "The edit may have landed with only some attachments uploaded."
    echo "Open the issue and see which images rendered before retrying. A retry that also"
    echo "passes --body rewrites the referenced paths and is safe; an attach-only retry"
    echo "appends again, so pass only the paths that did not upload."
fi
echo ""
echo "$RESULT"

exit "$STATUS"
