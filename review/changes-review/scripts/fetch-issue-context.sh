#!/usr/bin/env bash
# Fetch minimal review context for the current branch's issue/PR.
#
# Usage: fetch-issue-context.sh [issue-number] [--repo owner/name]
#
# With no issue argument, auto-detects in this order:
#   1. PR open for the current branch (and its linked issue, if any)
#   2. Branch name matching `issue-<N>`
#   3. `#<N>` in the last commit message
#
# Outputs the issue description, linked PR body, unresolved review threads, and
# PR conversation comments to stdout. If nothing is detected and no argument is
# given, exits 0 silently with no output.

set -euo pipefail

usage() {
    echo "Usage: fetch-issue-context.sh [issue-number] [--repo owner/name]" >&2
    exit 2
}

issue=""
repo=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo) repo="${2:-}"; shift 2 ;;
        -h|--help) usage ;;
        --*) usage ;;
        *) [[ -z "$issue" ]] && { issue="$1"; shift; } || usage ;;
    esac
done

if [[ -z "$repo" ]]; then
    repo=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null) || exit 0
fi
owner="${repo%%/*}"
name="${repo##*/}"

pr=""
detected_from=""

if [[ -z "$issue" ]]; then
    pr_json=$(gh pr view --json number,closingIssuesReferences 2>/dev/null) || pr_json=""
    if [[ -n "$pr_json" ]]; then
        pr=$(jq -r '.number // empty' <<<"$pr_json")
        issue=$(jq -r '.closingIssuesReferences[0].number // empty' <<<"$pr_json")
        [[ -n "$pr" || -n "$issue" ]] && detected_from="current branch PR"
    fi

    if [[ -z "$issue" && -z "$pr" ]]; then
        branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
        if [[ "$branch" =~ issue-([0-9]+) ]]; then
            issue="${BASH_REMATCH[1]}"
            detected_from="branch name"
        fi
    fi

    if [[ -z "$issue" && -z "$pr" ]]; then
        commit_msg=$(git log -1 --pretty=%B 2>/dev/null || true)
        if [[ "$commit_msg" =~ \#([0-9]+) ]]; then
            issue="${BASH_REMATCH[1]}"
            detected_from="last commit message"
        fi
    fi

    if [[ -z "$issue" && -z "$pr" ]]; then
        exit 0
    fi
fi

if [[ -n "$detected_from" ]]; then
    echo "_Detected from: ${detected_from}_"
    echo
fi

if [[ -n "$issue" ]]; then
    issue_json=$(gh issue view "$issue" --repo "$repo" --json title,body,comments,url 2>/dev/null) || issue_json=""
    if [[ -n "$issue_json" ]]; then
        title=$(jq -r '.title' <<<"$issue_json")
        body=$(jq -r '.body // ""' <<<"$issue_json")
        url=$(jq -r '.url' <<<"$issue_json")

        echo "# Issue #$issue: $title"
        echo
        echo "$url"
        echo
        echo "## Description"
        echo
        [[ -n "$body" ]] && echo "$body" || echo "_(empty)_"
        echo

        issue_comment_count=$(jq '.comments | length' <<<"$issue_json")
        if [[ "$issue_comment_count" -gt 0 ]]; then
            echo "## Issue Comments"
            echo
            jq -r '.comments[] | "**@\(.author.login):**\n\n\(.body)\n"' <<<"$issue_json"
        fi
    fi

    if [[ -z "$pr" ]]; then
        prs_json=$(gh api graphql -f query="{
          repository(owner: \"$owner\", name: \"$name\") {
            issue(number: $issue) {
              closedByPullRequestsReferences(first: 10, includeClosedPrs: true) {
                nodes { number state }
              }
            }
          }
        }" 2>/dev/null || echo '{}')

        pr=$(jq -r '
          .data.repository.issue.closedByPullRequestsReferences.nodes // [] as $nodes |
          ([$nodes[] | select(.state == "OPEN")] +
           [$nodes[] | select(.state == "MERGED")] +
           [$nodes[] | select(.state == "CLOSED")]) |
          first | .number // empty
        ' <<<"$prs_json")
    fi
fi

if [[ -z "$pr" ]]; then
    [[ -n "$issue" ]] && { echo "## Linked PR"; echo; echo "_No linked PR found._"; }
    exit 0
fi

pr_json=$(gh api graphql -f query="{
  repository(owner: \"$owner\", name: \"$name\") {
    pullRequest(number: $pr) {
      title body state url
      reviewThreads(first: 100) {
        nodes {
          isResolved
          path
          line
          comments(first: 20) { nodes { author { login } body } }
        }
      }
      comments(first: 100) {
        nodes { author { login } body }
      }
    }
  }
}" 2>/dev/null) || exit 0

pr_title=$(jq -r '.data.repository.pullRequest.title' <<<"$pr_json")
pr_state=$(jq -r '.data.repository.pullRequest.state' <<<"$pr_json")
pr_url=$(jq -r '.data.repository.pullRequest.url' <<<"$pr_json")
pr_body=$(jq -r '.data.repository.pullRequest.body // ""' <<<"$pr_json")

echo "## Linked PR #$pr ($pr_state): $pr_title"
echo
echo "$pr_url"
echo
[[ -n "$pr_body" ]] && echo "$pr_body" || echo "_(empty body)_"
echo

unresolved_count=$(jq '[.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] | length' <<<"$pr_json")
if [[ "$unresolved_count" -gt 0 ]]; then
    echo "## Unresolved Review Threads ($unresolved_count)"
    echo
    jq -r '
      .data.repository.pullRequest.reviewThreads.nodes
      | map(select(.isResolved == false))
      | .[]
      | "**\(.path):\(.line // "?")**\n\n" +
        (.comments.nodes | map("@\(.author.login): \(.body)") | join("\n\n---\n\n")) + "\n"
    ' <<<"$pr_json"
fi

pr_comment_count=$(jq '.data.repository.pullRequest.comments.nodes | length' <<<"$pr_json")
if [[ "$pr_comment_count" -gt 0 ]]; then
    echo "## PR Conversation"
    echo
    jq -r '.data.repository.pullRequest.comments.nodes[] | "**@\(.author.login):**\n\n\(.body)\n"' <<<"$pr_json"
fi
