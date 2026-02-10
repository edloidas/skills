#!/bin/bash
# check-environment.sh
# Validates that the environment is ready for GitHub issue creation
# Exit codes: 0 = ready, 1 = not a git repo, 2 = gh not installed, 3 = gh not authenticated

set -e

echo "=== Environment Check ==="
echo ""

# Check if we're in a git repository
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo "ERROR: Not inside a git repository"
    echo "  - Issues can only be created from within a git repository"
    echo "  - Navigate to a git repository and try again"
    exit 1
fi

echo "Git repository: YES"
echo "  Location: $(git rev-parse --show-toplevel)"

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    echo ""
    echo "ERROR: GitHub CLI (gh) is not installed"
    echo "  - Install with: brew install gh"
    echo "  - Or visit: https://cli.github.com/"
    exit 2
fi

echo "GitHub CLI: INSTALLED"
echo "  Version: $(gh --version | head -n 1)"

# Check authentication
if ! gh auth status > /dev/null 2>&1; then
    echo ""
    echo "ERROR: GitHub CLI is not authenticated"
    echo "  - Run: gh auth login"
    echo "  - Or set GITHUB_TOKEN / GH_TOKEN environment variable"
    exit 3
fi

echo "GitHub Auth: authenticated"

# Display remote info
REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")

if [ -z "$REMOTE_URL" ]; then
    echo ""
    echo "WARNING: No 'origin' remote found"
    echo "  - Issues require a GitHub remote"
    echo "  - Add one with: git remote add origin <url>"
else
    echo ""
    echo "Remote origin: $REMOTE_URL"

    # Extract owner/repo from URL
    if [[ "$REMOTE_URL" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
        OWNER="${BASH_REMATCH[1]}"
        REPO="${BASH_REMATCH[2]}"
        echo "Repository: $OWNER/$REPO"
    fi
fi

echo ""
echo "=== Environment Ready ==="
