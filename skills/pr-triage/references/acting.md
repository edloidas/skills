# Acting on a pull request

The home of this skill's write mechanics, except approving, folding and merging, which live in
pr-review — see this file's **Approve, fold, and merge** section. Another skill's reference sits in
that skill's installed directory; where it cannot be found, use the fallback given at its pointer.
Composition of a review — attribution, length,
anchoring, the `APPROVE` shape, the no-footer rule — belongs to changes-review's
`references/publishing-a-review.md`; follow it and do not restate it here. Where that file is not
installed: one inline comment per finding on a line the diff touches, everything else in the body,
`REQUEST_CHANGES` when a blocker or major survived and `COMMENT` otherwise, and no attribution or
generated-by footer. How it sounds is set under **Request changes, comment, or approve with
suggestions**.

Every write below runs only for a proposed row the reviewer's reply named.

**A reply approves the points; the text is shown before it posts.** A review is composed from
exactly the points the reply lists, and a point added later needs a new reply. Show the composed
text — body and inline comments, as they will post — and post after the next reply, with its edits.
Skip showing only when the reply says to publish now ("send it"), or in a run invoked by another
skill or told up front not to stop. Either skips the showing only: a row still runs only as a
reply, or that up-front instruction, named it.

## Before any write

1. **Verify first, publish after.** Every verdict a dispatched reviewer owes is in the
   orchestrator's hands, as that reviewer's own output, before anything is posted. A result
   written on a reviewer's behalf while it is still running is a fabricated verdict, however
   likely it looked.
2. **A claim that contradicts a person is read by the orchestrator itself** — the file and lines,
   or the platform source at the resolved version — before it is posted. Two agents agreeing is
   not that reading.
3. **The head has not moved.** `gh pr view <N> -R <repo> --json headRefOid`. If it moved since the
   findings were made, re-check each one against the new head and drop or adjust it; a finding
   that changed meaning goes back to the reviewer.
4. **The reviewer's own draft review.** GitHub allows one pending review per person, and shows it
   only to them:

   ```bash
   gh api repos/<owner>/<repo>/pulls/<N>/reviews --paginate --jq '.[] | select(.state == "PENDING" and .user.login == "<reviewer login>") | {node_id, body}'
   ```

   When one exists, every review this skill posts on that pull request goes through it, per
   [Into a pending review](#into-a-pending-review): the reviewer's draft comments stay as written,
   and the text shown before posting includes them, marked as theirs.

## Approve, fold, and merge

The commands and rules are pr-review's `references/landing.md`, the one home of approving, folding
fixes into, and merging someone else's pull request; read it before the first such write. The
approved plan it speaks of is the row a reply named. What is pr-triage's own:

- A fold is for AUTO-FIX items only, never a SUGGEST item, and only in a repository with a clean
  clone recorded in Phase 0 (`local-repos.md`). The orchestrator holds that clone's checkout lease
  for it, fork heads included.
- After a fold, landing's one-line reply goes on each of the reviewer's threads the fold fixed or
  adjusted; **Resolve settled threads** covers every other thread.
- The `COMMENT` landing has pr-triage post after a failed check is shown before it posts, per the
  rule at the top of this file.
- A `FOLD` row that fails a condition becomes a `COMMENT` review with the fixes as suggestions, with
  no `APPROVE` and no `MERGE`, and its report row says what changed and why.
- Where pr-review is not installed, a `FOLD` row becomes that `COMMENT`, an `APPROVE` row posts with
  `gh pr review --approve`, and a `MERGE` row runs only on green required checks when GitHub would
  merge the branch as it is: `gh pr merge <N> -R <repo> --<method> --match-head-commit <full headRefOid>` from the head check above, the method the
  base's recent history shows, never `--admin`. Anything else holds the row.

## Request changes, comment, or approve with suggestions

Compose per the publishing reference, in the voice pr-review's `references/review-voice.md` sets —
read it before drafting the first review, approval body or thread reply of the run. Where it is not
installed: talk to the author, never report to the reviewer; put what is the author's call as a
question; write in the language the repository's reviews use. Show it as above, then post once.
Write `review.json` and `reply.md` in a scratch directory outside every clone, so no clone's tree
gets dirty:

```bash
gh api repos/<owner>/<repo>/pulls/<N>/reviews --method POST --input review.json
# review.json: {"commit_id": "<head sha>", "event": "REQUEST_CHANGES"|"COMMENT"|"APPROVE",
#               "body": "...", "comments": [{"path": "...", "line": <n>, "side": "RIGHT", "body": "..."}]}
```

- A follow-up after the reviewer already requested changes is a `COMMENT` review: the request
  stands, and a second `REQUEST_CHANGES` adds nothing.
- Withdrawing that request without approving is a dismissal of the review, then the `COMMENT`.
  A row that softens a block says which it does — keep the request, or dismiss it — and a
  proposal to soften one names both:

  ```bash
  gh api repos/<owner>/<repo>/pulls/<N>/reviews/<review id>/dismissals --method PUT \
    -f event=DISMISS -f message="<one line: what changed>"
  ```

  Branch protection can restrict who may dismiss; a refusal is reported on the row, not retried.
- Reply inside an existing thread with
  `gh api repos/<owner>/<repo>/pulls/<N>/comments/<comment id>/replies -F body=@reply.md`.
- A point that belongs to another repository — a platform issue, a companion pull request — is
  raised there on a row that lists it, linked from here, and carries the same reading rule as
  above.

## Into a pending review

Add each inline comment as a thread of the pending review, then submit it with the event and the
body — the reviewer's draft body first, the composed one after it:

```bash
gh api graphql -f query='mutation($r:ID!,$p:String!,$l:Int!,$b:String!){addPullRequestReviewThread(input:{pullRequestReviewId:$r,path:$p,line:$l,side:RIGHT,body:$b}){thread{id}}}' -f r=<node_id> -f p=<path> -F l=<line> -F b=@comment.md
gh api graphql -f query='mutation($r:ID!,$e:PullRequestReviewEvent!,$b:String!){submitPullRequestReview(input:{pullRequestReviewId:$r,event:$e,body:$b}){pullRequestReview{url}}}' -f r=<node_id> -f e=<APPROVE|COMMENT|REQUEST_CHANGES> -F b=@body.md
```

`gh pr review` and the REST review endpoint are not used while a pending review exists.

## Resolve settled threads

A thread the reviewer opened is settled when its point is `FIXED`, `ALREADY-SO`, or
`AUTHOR-DECLINED` with an argument that held, and nothing in it waits on the reviewer — no
question, no new point after the author's last reply. Every row that runs on a pull request
resolves its settled threads, with no reply unless the author asked something. A thread that is
not settled stays open, and the report says why. Another person's thread is never resolved.

```bash
gh api graphql -f query='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){reviewThreads(first:100){nodes{id isResolved path line opener:comments(first:1){nodes{author{login}}} latest:comments(last:1){nodes{author{login} body}}}}}}}' -f o=<owner> -f r=<repo> -F n=<N>
gh api graphql -f query='mutation($id:ID!){resolveReviewThread(input:{threadId:$id}){thread{isResolved}}}' -f id=<thread id>
```
