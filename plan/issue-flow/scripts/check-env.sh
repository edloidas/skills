#!/bin/bash
# check-env.sh
# Validates git repo, gh CLI, and gh authentication.
# Exit codes: 0 = ready, 1 = not a git repo, 2 = gh not installed, 3 = gh not authenticated
# Success: single-line status. Failure: verbose actionable message.

set -e

if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo "ERROR: Not inside a git repository" >&2
    echo "  Navigate to a git repository and try again" >&2
    exit 1
fi

if ! command -v gh &> /dev/null; then
    echo "ERROR: GitHub CLI (gh) is not installed" >&2
    echo "  Install with: brew install gh" >&2
    echo "  Or visit: https://cli.github.com/" >&2
    exit 2
fi

if ! gh auth status > /dev/null 2>&1; then
    echo "ERROR: GitHub CLI is not authenticated" >&2
    echo "  Run: gh auth login" >&2
    echo "  Or set GITHUB_TOKEN / GH_TOKEN environment variable" >&2
    exit 3
fi

REPO=""
REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
if [[ -z "$REMOTE_URL" ]]; then
    echo "OK git=yes gh=authed remote=none (add one with: git remote add origin <url>)"
    exit 0
fi

if [[ "$REMOTE_URL" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
    REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
fi

echo "OK git=yes gh=authed repo=${REPO:-$REMOTE_URL}"
