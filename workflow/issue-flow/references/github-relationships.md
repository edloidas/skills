# GitHub Issue Relationships

Reference for REST and GraphQL APIs used to manage issue relationships.

## Three Identifier Types

GitHub uses three different identifiers for the same issue. Passing the wrong type causes a cryptic `422` error.

| Used for            | Field        | Example              | How to get                                      |
| ------------------- | ------------ | -------------------- | ----------------------------------------------- |
| REST calls / gh CLI | `.number`    | `9920`               | issue URL                                       |
| Sub-issues REST API | `.id` (int)  | `3985940615`         | `gh api .../issues/N --jq '.id'`                |
| GraphQL mutations   | `.id` (node) | `I_kwDOCdbdCs7tlKCH` | `gh api graphql ... issue(number: N) { id }`    |

## Sub-Issues (REST API)

Check availability — returns `[]` if enabled, `404` if not:

```bash
gh api repos/<owner>/<repo>/issues/<parent>/sub_issues
```

Add a child — needs the **integer** `.id`, not the issue number:

```bash
CHILD_ID=$(gh api repos/<owner>/<repo>/issues/<child-number> --jq '.id')
gh api repos/<owner>/<repo>/issues/<parent>/sub_issues \
  --method POST -F sub_issue_id="$CHILD_ID"
```

`-F` (form field) is required — `-f` sends a string, causing `422 - not of type integer`.

The POST returns the parent issue object. Parent title in response = success, not an error.

Verify:

```bash
gh api repos/<owner>/<repo>/issues/<parent>/sub_issues --jq '.[].number'
```

## Blocked-By Relationships (GraphQL Only)

> The REST endpoint `/issues/<n>/relationships` returns `404` — it does not exist.

Fetch **node IDs** for multiple issues in one query (batch-friendly):

```bash
gh api graphql -f query='{
  repository(owner: "<owner>", name: "<repo>") {
    a: issue(number: <num-a>) { id }
    b: issue(number: <num-b>) { id }
  }
}'
```

Add relationship — "b is blocked by a":

```bash
gh api graphql -f query='mutation {
  addBlockedBy(input: {
    issueId: "<node-id-of-b>",
    blockingIssueId: "<node-id-of-a>"
  }) { issue { number } blockingIssue { number } }
}'
```

Remove relationship — same signature:

```bash
gh api graphql -f query='mutation {
  removeBlockedBy(input: {
    issueId: "<node-id-of-b>",
    blockingIssueId: "<node-id-of-a>"
  }) { issue { number } blockingIssue { number } }
}'
```
