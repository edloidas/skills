#!/bin/bash
# wait-checks.sh
# Polls PR check status until all checks resolve or timeout.
# Usage: wait-checks.sh <pr-number> [timeout-seconds]
# Exit codes: 0 = all passed/skipped, 1 = failure, 2 = timeout

set -e

PR_NUMBER="${1:-}"
TIMEOUT="${2:-300}"
POLL_INTERVAL=10

if [ -z "$PR_NUMBER" ]; then
    echo "Usage: wait-checks.sh <pr-number> [timeout-seconds]"
    echo "  Default timeout: 300s"
    exit 1
fi

elapsed=0

while true; do
    # Get check statuses as tab-separated: name\tbucket
    checks=$(gh pr checks "$PR_NUMBER" --json name,bucket --jq '.[] | [.name, .bucket] | @tsv' 2>/dev/null || true)

    if [ -z "$checks" ]; then
        echo "No checks found for PR #${PR_NUMBER}."
        exit 0
    fi

    total=0
    passed=0
    failed=0
    pending=0
    failed_names=""

    while IFS=$'\t' read -r name bucket; do
        total=$((total + 1))
        case "$bucket" in
            pass|skipping)
                passed=$((passed + 1))
                ;;
            fail)
                failed=$((failed + 1))
                failed_names="${failed_names}  - ${name}\n"
                ;;
            *)
                pending=$((pending + 1))
                ;;
        esac
    done <<< "$checks"

    # All passed or skipped
    if [ "$failed" -eq 0 ] && [ "$pending" -eq 0 ]; then
        echo "All checks passed. (${passed} passed) [${elapsed}s]"
        exit 0
    fi

    # Any failed
    if [ "$failed" -gt 0 ]; then
        echo "Checks failed (${failed} failed, ${passed} passed, ${pending} pending):"
        echo -e "$failed_names"
        exit 1
    fi

    # Timeout
    if [ "$elapsed" -ge "$TIMEOUT" ]; then
        echo "Timeout after ${TIMEOUT}s. (${pending} pending, ${passed} passed)"
        exit 2
    fi

    echo "Waiting for checks... (${pending} pending, ${passed} passed) [${elapsed}s]"
    sleep "$POLL_INTERVAL"
    elapsed=$((elapsed + POLL_INTERVAL))
done
