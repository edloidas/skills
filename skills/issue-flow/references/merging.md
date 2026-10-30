# Merging

Step 6 reads this file twice: **Method** at the start of **Confirm exactly once**, and **Refused**
only if `gh pr merge` refuses.

## Method

A method stated in the target repo's instruction file (`CLAUDE.md`, `AGENTS.md`) wins. Otherwise
read what the repo allows:

```bash
gh repo view --json rebaseMergeAllowed,squashMergeAllowed,mergeCommitAllowed --jq '[.rebaseMergeAllowed, .squashMergeAllowed, .mergeCommitAllowed] | @tsv'
```

| Allowed | `<method>` |
| ------- | ---------- |
| rebase | `rebase` — the preference: Consolidate already left one commit, so it lands as written |
| squash, not rebase, PR carries one commit | `squash` |
| squash, not rebase, PR carries several (**Slice Delivery**, or Consolidate's `Keep as-is`) | Ask, per **Asking the User**: `Stop without merging` (Recommended) — squash would fold the kept commits into one; `Squash anyway`; `Merge commit`, only when allowed |
| merge commit only | Ask, per **Asking the User**: `Stop without merging` (Recommended) — the repo allows neither rebase nor squash; `Merge commit` — lands the branch under a merge commit |
| nothing readable (the call failed) | Stop and report the error — never default to a method the repo may refuse |

Count the PR's commits with `gh pr view <pr-number> --json commits --jq '.commits | length'`.
`<method>` is the flag word: `Squash anyway` sets `squash`, `Merge commit` sets `merge`,
`Stop without merging` ends the flow with the PR open. A merge intent from the caller does not
answer a question here, so an unattended caller takes `Stop without merging`.

The pre-merge summary and the merged report name `<method>`.

## Refused

`gh pr merge` exits non-zero and prints why. Read that text, act on the row it matches, and never
retry with another method, `--admin`, or a direct push to the base — each of those gets around the
rule that refused it.

| `gh` says | Then |
| --------- | ---- |
| a review is required, changes were requested, or required checks are failing or pending | Stop. Report what is missing — `gh pr view <pr-number> --json reviewDecision,statusCheckRollup` names it — and leave the PR open |
| the base requires a merge queue | The user asked to merge: re-run the same command, every flag kept, with `--auto` added, which enqueues the PR rather than merging it. Print the Step 6 queued report and stop — no issue close, no stash pop, no `Done` status, since nothing has landed. A merge only suggested, never asked for: report it and stop |
| the PR is part of a stack and must merge through it | Stop. Report the refusal and name GitHub's stack merge, run from the stack's bottom pull request, as the user's action |
| permission denied, or the host refused to run the command | Stop. Print the exact `gh pr merge` command for the user to run themselves |
| the head moved (`--match-head-commit` mismatch) | Re-run **Pre-checks** from step 2 once — someone pushed after the last check. A second mismatch stops and reports it |
| anything else | Stop and quote `gh`'s error, unedited, in a fenced block |

Every row but the head-moved one ends the flow; the merged report is printed only after a merge
that `gh pr view <pr-number> --json state` reads as `MERGED`.
