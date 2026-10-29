# Acting on a pull request

The only home of this skill's write mechanics. Composition of a review — attribution, length,
anchoring, the `APPROVE` shape, the no-footer rule — belongs to changes-review's
`references/publishing-a-review.md`; follow it and do not restate it here. Where that file is not
installed: one inline comment per finding on a line the diff touches, everything else in the body,
`REQUEST_CHANGES` when a blocker or major survived and `COMMENT` otherwise, and no attribution or
generated-by footer. Text posted to GitHub is in the language the repository's reviews use, English
when unclear, whatever language the reviewer talks to this session in.

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

## Approve and merge

```bash
gh pr checks <N> -R <repo> --required --watch --fail-fast   # every required check green
gh pr review <N> -R <repo> --approve --body "<2-4 sentences>"
gh api repos/<owner>/<repo> --jq '{squash: .allow_squash_merge, rebase: .allow_rebase_merge, merge: .allow_merge_commit}'
gh api "repos/<owner>/<repo>/commits?sha=<base>&per_page=10" --jq '.[] | "\(.parents | length) \(.commit.message | split("\n")[0])"'
gh pr merge <N> -R <repo> --<squash|rebase|merge> --match-head-commit <full head sha>
```

- Merge only on a row that says merge. Approval alone never implies it.
- A required check that fails, or is still pending after 30 minutes: approve if the row approves,
  do not merge, and report the check on the row. Bound the wait yourself — run `--watch` in the
  background, or re-run `gh pr checks --required` every few minutes — and treat a tool timeout as
  pending.
- Pick the method the base branch's recent history shows, among those the repository allows:
  single-parent commits with a `(#N)` suffix mean squash, a straight history of the authors' own
  commits means rebase, two-parent commits mean merge. Never pass `--admin`.
- **Stale mergeability**, on a row that lists it: when GitHub reports `CONFLICTING` or `DIRTY` but
  `gh api repos/<owner>/<repo>/compare/<base>...<head sha> --jq .behind_by` is `0`, close and
  reopen the pull request once to recompute, then merge with `--match-head-commit`. The author is
  notified of both; the report says so.
- A branch that is truly behind, with protection requiring it up to date: `gh pr update-branch`,
  wait for CI again, then merge. Never force-push to bring it up to date.

## Fold small fixes and approve

Only for AUTO-FIX items — small, certain fixes of a defect, inside the change's own scope, never a
SUGGEST item — and only when the repository has a clean clone (`local-repos.md`), the head branch
lives in the base repository or `gh pr view <N> -R <repo> --json maintainerCanModify` is true, and
the head branch does not require signed commits — amending drops the author's signature:

```bash
gh api repos/<owner>/<repo>/branches/<head-branch>/protection/required_signatures --jq .enabled   # 404: no rule; 403: unknown, do not fold
```

A last commit that is a merge commit is not folded either. Otherwise the fixes go into a `COMMENT`
review as suggestions. A `FOLD` row that fails one of these conditions in Phase 5 becomes that
`COMMENT`, with no `APPROVE` and no `MERGE`, and its report row says what changed and why.

1. Resolve where the head lives, take the checkout lease (in Phase 5 the orchestrator holds it,
   fork heads included — their code is edited and pushed, never run), and fold on a disposable branch — never
   on a local branch named after the head branch, which for a fork is usually the reviewer's own
   `main` or `master`:

   ```bash
   gh pr view <N> -R <repo> --json headRefName,headRefOid,headRepository,headRepositoryOwner,isCrossRepository
   git fetch <remote> "pull/<N>/head:refs/remotes/<remote>/pr/<N>"   # must now equal headRefOid
   git checkout -B fold/<N> <remote>/pr/<N>
   ```

   `<push-target>` is `<remote>` when `isCrossRepository` is false. When it is true, it is the fork
   in the same form as `git remote get-url <remote>` — `git@github.com:<owner>/<repo>.git` for an
   SSH remote, `https://github.com/<owner>/<repo>.git` otherwise — with `<owner>` from
   `headRepositoryOwner.login` and `<repo>` from `headRepository.name`.
2. Apply each fix as a targeted edit, never a whole-file rewrite. For a head in the base
   repository, run the repository's own checks; a fix whose checks fail is reverted and becomes a
   review comment. A fork's code is not executed locally — its checks are the CI run in step 5.
3. Apply the code-cleanup skill's criteria to the lines just changed, and nothing beyond them.
   Where it is not installed: no comment restating the code, names and style as the file has them.
4. Fold into the pull request's **last** commit, keeping its author and message, with the reviewer
   added as co-author from their git identity. Leave earlier commits alone and add no assistant
   trailer:

   ```bash
   git add <files>
   git commit --amend --no-edit --trailer "Co-Authored-By: $(git config user.name) <$(git config user.email)>"
   git log -1 --format='%an <%ae>%n%(trailers)'   # the original author, then the trailers
   git push --force-with-lease=<head-branch>:<head sha before the fold> <push-target> HEAD:<head-branch>
   ```

5. Wait for every required check on the new head. **Red after the push: no approval.** Post a
   `COMMENT` naming the pushed head and the failing check, and report it; a push to revert the fold
   needs its own reply.
6. Green: reply one line on each of the reviewer's own threads — fixed, or what was adjusted —
   resolve those that are fixed, then approve. The approval body names the folded fixes in one
   clause. Merge only on a row that says merge.

## Request changes, comment, or approve with suggestions

Compose per the publishing reference, show it as above, then post once. Write `review.json` and `reply.md` in a
scratch directory outside every clone, so no clone's tree gets dirty:

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
