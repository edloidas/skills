# Fetching a pull request's conversation

One query, up front. Everything the posture step and the verdict step need has to be in it, because
a second round trip per thread on a pull request with fifteen comments is the difference between a
run and a stall.

## What the old query could not do

The previous version of this skill fetched `isResolved`, `path`, `line`, `diffSide`, and each
comment's `author.login`, `body` and `createdAt`. That is enough to print a triage list and nothing
else. It carried **no thread id and no comment id**, so neither `resolveReviewThread` nor the reply
endpoint was reachable from what it collected — the two actions this skill exists to perform. Add
them first; everything else below is refinement.

## The query

```bash
gh api graphql -f query='
query($owner: String!, $repo: String!, $pr: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $pr) {
      author { login }
      baseRefName
      headRefOid
      viewerCanUpdate
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          originalLine
          diffSide
          subjectType
          comments(first: 50) {
            nodes {
              id
              databaseId
              author { login __typename }
              authorAssociation
              viewerDidAuthor
              body
              createdAt
              diffHunk
            }
          }
        }
      }
    }
  }
}' -f owner='<owner>' -f repo='<repo>' -F pr='<number>'
```

Why each addition earns its place:

| Field | What it decides |
| ----- | --------------- |
| `reviewThreads.nodes.id` | The `resolveReviewThread` target. Without it, resolving is impossible |
| `comments.nodes.databaseId` | The REST reply endpoint's `comment_id`. The GraphQL `id` will not work there |
| `author.__typename` | `Bot` vs `User` — the posture axis, and more reliable than the login |
| `authorAssociation` | `OWNER`, `MEMBER`, `CONTRIBUTOR`, `NONE`. A drive-by is weighted differently from a maintainer |
| `viewerDidAuthor` | Whether the last word in the thread is already yours |
| `createdAt` | Orders the thread. The **last** comment's author matters as much as the root's |
| `diffHunk` | The code as the commenter saw it, which is not necessarily the code now |
| `originalLine` | `line` is null on an outdated thread, so without this the location is lost exactly when `isOutdated` makes it interesting |
| `subjectType` | `LINE` or `FILE`. A file-level comment has no line to anchor a reply to |
| `pullRequest.author.login` | Against `gh api user --jq .login`, this decides which side you are on |
| `viewerCanUpdate` | Whether resolving is permitted. Check before attempting, not after failing |

**Do not filter `isResolved` out of the fetch.** Fetch everything and filter in the posture step. A
resolved thread is still evidence — it is how `already-addressed` gets established, and under
`--full` resolved threads are back in scope.

## General comments

```bash
gh api "repos/<owner>/<repo>/issues/<number>/comments?per_page=100" \
  --jq '[.[] | {id, login: .user.login, type: .user.type, body, created_at}]'
```

`user.type` is `Bot` or `User`, the REST equivalent of `__typename`. Each general comment is a
standalone item with no file or line context, so it can never receive an inline reply — only a new
general comment.

**Never exclude bot comments here.** The previous version did, and bots write most of the inline
findings on a modern pull request, so filtering them discards this skill's primary input.

## Detecting a bot

Two tests, either one sufficient:

1. `author.__typename == "Bot"` (GraphQL) or `user.type == "Bot"` (REST).
2. The login appears in a known list.

The `[bot]` suffix alone is **not** a test. `copilot-pull-request-reviewer` carries no suffix and
passes a suffix check as a human, which inverts its posture and gets its claims treated as a
colleague's.

Known logins worth carrying, suffix or not: `copilot-pull-request-reviewer`, `copilot`,
`github-actions`, `dependabot`, `renovate`, `coderabbitai`, `sourcery-ai`, `sonarcloud`, `codecov`,
`deepsource-autofix`, `snyk-bot`.

A bot's own follow-up — "I've addressed this", "Good catch" — **does not** count as a human reply for
posture purposes. Only a `User` moves a thread's last-comment axis.

## Replying and resolving

Reply into an existing inline thread, REST, using `databaseId`:

```bash
gh api "repos/<owner>/<repo>/pulls/<pr>/comments/<databaseId>/replies" \
  -X POST -f body="<text>"
```

Resolve a thread, GraphQL, using the thread's node `id`:

```bash
gh api graphql -f query='
mutation($threadId: ID!) {
  resolveReviewThread(input: { threadId: $threadId }) {
    thread { id isResolved }
  }
}' -f threadId='<thread node id>'
```

A general comment gets a new general comment, not a reply: `gh pr comment <pr> --body-file <file>`.

**A thread reply cannot carry an image.** `--attach` is a `gh pr comment` flag, and both replying
and resolving go through `gh api`, which has no equivalent. So a finding settled by looking at a
rendered frame replies with its measurement, and the frame stays in the operator report. Do not
post a general comment to host the image and link it from the reply — that puts an unthreaded
comment on the pull request for every reader, to serve one thread.

Resolving requires write access. `viewerCanUpdate` answers that before the attempt — a failed
mutation after a posted reply leaves the thread half-answered.
