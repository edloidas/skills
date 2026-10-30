# Landing someone else's pull request

The one home of the write mechanics for approving, folding fixes into, and merging a pull request
someone else opened. pr-review's `--land` and pr-triage's `FOLD`, `APPROVE` and `MERGE` rows both
run them. Every write here runs only after the caller's own gate approved it — pr-review's land
confirmation, or a pr-triage reply naming the row — and only the writes that approval listed.

## Approve and merge

```bash
gh pr checks <N> -R <repo> --required --watch --fail-fast   # every required check green
gh pr review <N> -R <repo> --approve --body "<2-4 sentences>"
gh api repos/<owner>/<repo> --jq '{squash: .allow_squash_merge, rebase: .allow_rebase_merge, merge: .allow_merge_commit}'
gh api "repos/<owner>/<repo>/commits?sha=<base>&per_page=10" --jq '.[] | "\(.parents | length) \(.commit.message | split("\n")[0])"'
gh pr merge <N> -R <repo> --<squash|rebase|merge> --match-head-commit <full head sha>
```

- Merge only when the approved plan says merge. Approval alone never implies it.
- With a pending review of yours already on the pull request, `gh pr review` fails — GitHub allows
  one per person. Submit that review as the approval instead: GraphQL `submitPullRequestReview` on
  its `node_id`, with `event: APPROVE`.
- A required check that fails, or is still pending after 30 minutes: approve if the plan approves,
  do not merge, and report the check. Bound the wait yourself — run `--watch` in the background,
  or re-run `gh pr checks --required` every few minutes — and treat a tool timeout as pending.
- Pick the method the base branch's recent history shows, among those the repository allows:
  single-parent commits with a `(#N)` suffix mean squash, a straight history of the authors' own
  commits means rebase, two-parent commits mean merge. Never pass `--admin`.
- **Stale mergeability**, on a plan that lists it: when GitHub reports `CONFLICTING` or `DIRTY` but
  `gh api repos/<owner>/<repo>/compare/<base>...<head sha> --jq .behind_by` is `0`, close and
  reopen the pull request once to recompute, then merge with `--match-head-commit`. The author is
  notified of both; the report says so.
- A branch that is truly behind, with protection requiring it up to date, is rebased onto its
  base, never merged with it — a merge commit on the author's branch is not the reviewer's to add.
  Run `gh pr update-branch <N> -R <repo> --rebase`; without `--rebase` it merges. Where GitHub
  refuses that for a reason other than a conflict, rebase locally where a fold could push — a
  clean clone, an editable head, no required signatures — on `fold/<N>` per step 1 below, onto a
  freshly fetched `<remote>/<base>`, and push with step 4's pinned lease, the head SHA before the
  rebase. Then re-read `headRefOid` for `--match-head-commit`, wait for CI again, re-approve if
  the update dismissed the approval, and merge. A conflict holds the merge: resolving it is the
  author's. A branch GitHub would merge as it is is not rebased.
- A rebase or its push that is refused — the host's permission layer, branch protection, a lease
  the remote moved past — stops the landing. Do not merge the base in instead and do not retry
  with `--force`. Report it held, with the refusal as printed and the exact command the reviewer
  can run themselves.

## Fold small fixes and approve

Only for small, certain fixes of a defect inside the change's own scope, each written out as an
exact edit — never the author's own call on wording, naming, UX or scope. Only from a local clone of
the repository whose working tree is clean, when the head branch lives in the base repository or
`gh pr view <N> -R <repo> --json maintainerCanModify` is true, and when the head branch does not
require signed commits — amending drops the author's signature:

```bash
gh api repos/<owner>/<repo>/branches/<head-branch>/protection/required_signatures --jq .enabled   # 404: no rule; 403: unknown, do not fold
```

A last commit that is a merge commit is not folded either. A fold that fails one of these
conditions is not attempted; the caller says what takes its place.

1. Record the branch the clone is on, resolve where the head lives, and fold on a disposable
   branch — never on a local branch named after the head branch, which for a fork is usually the
   reviewer's own `main` or `master`. A fork's code is edited and pushed, never run:

   ```bash
   gh pr view <N> -R <repo> --json headRefName,headRefOid,headRepository,headRepositoryOwner,isCrossRepository
   git fetch <remote> <base> "pull/<N>/head:refs/remotes/<remote>/pr/<N>"   # must now equal headRefOid
   git checkout -B fold/<N> <remote>/pr/<N>
   ```

   `<push-target>` is `<remote>` when `isCrossRepository` is false. When it is true, it is the fork
   in the same form as `git remote get-url <remote>` — `git@github.com:<owner>/<repo>.git` for an
   SSH remote, `https://github.com/<owner>/<repo>.git` otherwise — with `<owner>` from
   `headRepositoryOwner.login` and `<repo>` from `headRepository.name`.
2. Apply each fix as a targeted edit, never a whole-file rewrite. For a head in the base
   repository, run the repository's own checks; a fix whose checks fail is reverted — pr-triage
   posts it as a review comment, pr-review's `--land` reports it and lands nothing. A fork's code is not executed locally — its checks are the CI run in step 5.
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

   **Authorship the user named.** When the user's own words set it — "squash into one, mathias
   author, ashklianko co-author", "you as author, the rest as co-authors" — squash every commit of
   the pull request into one with exactly that author and those co-authors, in place of the amend:

   ```bash
   gh pr view <N> -R <repo> --json commits --jq '[.commits[].authors[] | "\(.login): \(.name) <\(.email)>"] | unique[]'
   git reset --soft "$(git merge-base <remote>/<base> HEAD)"
   git commit --author "<Name> <email>" -F <message file> --trailer "Co-Authored-By: <Name> <email>"
   ```

   Identities come from that list or the reviewer's git identity; a name found in neither is
   asked for at the caller's gate, never guessed. The subject is the pull request's title in the form the base's recent
   commits use. Under pr-review's `--land`, each folded fix gets one body line — `- <path>: <what
   changed>` — above the trailers, written to a message file in a scratch directory outside the
   clone and passed with `-F` (in the amend too, in place of `--no-edit`).

   A plan that also brings the branch up to date rebases `fold/<N>` onto `<remote>/<base>` after
   the commit and before this push, so one push carries both; the lease stays pinned to the head
   SHA before the fold, and a head in the base repository reruns step 2's checks on the rebased
   tree. A refused push follows the refusal rule under [Approve and merge](#approve-and-merge).

5. Wait for every required check on the new head. **Red after the push: no approval and no
   merge.** Report the pushed head and the failing check; pr-triage also posts them as a `COMMENT`.
   A push to revert the fold needs its own approval.
6. Green: reply one line on each of the reviewer's own threads — fixed, or what was adjusted —
   resolve those that are fixed, then approve. The approval body names the folded fixes in one
   clause. Merge only when the plan says merge.
7. Return to the recorded branch and delete `fold/<N>` once its push landed. A `fold/<N>` whose
   commits are on no remote — the push was refused — is kept, and the report names it.
