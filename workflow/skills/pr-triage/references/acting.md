# Acting on a pull request

The only home of this skill's write mechanics. Composition of a review — attribution, length,
anchoring, the `APPROVE` shape, the no-footer rule — belongs to changes-review's
`references/publishing-a-review.md`; follow it and do not restate it here. Where that file is not
installed: one inline comment per finding on a line the diff touches, everything else in the body,
`REQUEST_CHANGES` when a blocker or major survived and `COMMENT` otherwise, and no attribution or
generated-by footer.

Every write below runs only for a plan row the reviewer approved.

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
   that changed meaning goes back to a gate.

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

Only for AUTO-FIX items — small, certain, inside the change's own scope — and only when the
repository has a clean clone (`local-repos.md`), the head branch lives in the base repository or
`gh pr view <N> -R <repo> --json maintainerCanModify` is true, and the head branch does not
require signed commits — amending drops the author's signature:

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
   needs its own gate.
6. Green: reply one line on each of the reviewer's own threads — fixed, or what was adjusted —
   resolve those that are fixed, then approve. The approval body names the folded fixes in one
   clause. Merge only on a row that says merge.

## Request changes or comment

Compose per the publishing reference, then post once. Write `review.json` and `reply.md` in a
scratch directory outside every clone, so no clone's tree gets dirty:

```bash
gh api repos/<owner>/<repo>/pulls/<N>/reviews --method POST --input review.json
# review.json: {"commit_id": "<head sha>", "event": "REQUEST_CHANGES"|"COMMENT",
#               "body": "...", "comments": [{"path": "...", "line": <n>, "side": "RIGHT", "body": "..."}]}
```

- A follow-up after the reviewer already requested changes is a `COMMENT` review: the request
  stands, and a second `REQUEST_CHANGES` adds nothing.
- Reply inside an existing thread with
  `gh api repos/<owner>/<repo>/pulls/<N>/comments/<comment id>/replies -F body=@reply.md`.
  Resolve only the reviewer's own threads, and only when fixed.
- A point that belongs to another repository — a platform issue, a companion pull request — is
  raised there on a row that lists it, linked from here, and carries the same reading rule as
  above.
