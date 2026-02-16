#!/bin/bash
# get-repo-info.sh
# Retrieves repository information useful for issue creation
# Outputs labels, assignees, and repo details

set -e

# Check if we're in a git repo
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo '{"error": "Not in a git repository"}'
    exit 1
fi

# Check if gh is available
if ! command -v gh &> /dev/null; then
    echo '{"error": "GitHub CLI not installed"}'
    exit 1
fi

echo "=== Repository Information ==="
echo ""

# Get repo details
echo "Fetching repository details..."
gh repo view --json name,owner,description,url 2>/dev/null || echo "Could not fetch repo details"

echo ""
echo "=== Available Labels (filtered) ==="
echo ""

# Allowed labels (case-insensitive matching)
ALLOWED_LABELS="feature|improvement|bug|epic|critical|refactoring|r&d|won't fix"

# Get available labels and filter to allowed ones
ALL_LABELS=$(gh label list --json name,description 2>/dev/null)
if [ -n "$ALL_LABELS" ]; then
    echo "$ALL_LABELS" | jq -r --arg pattern "$ALLOWED_LABELS" '
        [.[] | select(.name | ascii_downcase | test($pattern; "i"))]
    '
else
    echo "Could not fetch labels"
fi

echo ""
echo "=== Recent Issues (for reference) ==="
echo ""

# Show recent issues for context
gh issue list --limit 5 --json number,title,labels,state 2>/dev/null || echo "Could not fetch issues"

echo ""
echo "=== Assignable Users ==="
echo ""

# Get assignable users (collaborators)
gh api repos/{owner}/{repo}/collaborators --jq '.[].login' 2>/dev/null | head -10 || echo "Could not fetch collaborators"

echo ""
echo "=== Top Contributors ==="
echo ""

# Get top 10 contributors
gh api repos/{owner}/{repo}/contributors --jq '.[0:10] | .[].login' 2>/dev/null || echo "Could not fetch contributors"

echo ""
echo "=== Suggested Assignees ==="
echo ""

# Get contributors and collaborators
CONTRIBUTORS=$(gh api repos/{owner}/{repo}/contributors --jq '.[0:10] | .[].login' 2>/dev/null || echo "")
COLLABORATORS=$(gh api repos/{owner}/{repo}/collaborators --jq '.[].login' 2>/dev/null || echo "")

echo "Collaborators:"
echo "$COLLABORATORS" | head -5 | tr '\n' ' '
echo ""
echo "Top contributors:"
echo "$CONTRIBUTORS" | head -5 | tr '\n' ' '
echo ""
