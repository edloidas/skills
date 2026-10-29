---
name: issue-flow
description: >
  Full GitHub issue lifecycle: pick an issue, create it, branch, commit, squash, push, PR,
  merge. Owns every git and gh write in the pipeline. Handles project board integration, base
  branch detection (main/master/epic-*), and compact step reports. Supports entering at any
  step.
when_to_use: >
  On "pick an issue", "create an issue", "start work on #N", "commit this",
  "open a PR", or "merge that PR" — and for any single step of the issue pipeline.
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash(gh:*) Bash(git:*) Bash(bash:*) Bash(mktemp:*) Read Write Glob Grep Skill AskUserQuestion
argument-hint: "[issue-number or description]"
metadata:
  author: edloidas
---

# Issue Flow

Manages the full GitHub issue lifecycle: select → issue → branch → commits → PR → merge → close. Supports entering at any step and advancing forward. Reads the target repo's CLAUDE.md for project-specific conventions.

Mutation class: **writes and pushes, and writes to external services (GitHub)** — branch creation, snapshots, commits, squashing, pushes, PRs, merges. This skill owns every one of them; `next-issue` owns ranking. Skills that orchestrate the pipeline (`solve-issue`) delegate those actions here rather than reimplementing them, so the commit subject format and the squash rules exist in exactly one place.

## Bundled Scripts

Located in `scripts/` relative to this skill:

| Script                     | Purpose                                         |
| -------------------------- | ----------------------------------------------- |
| `check-env.sh`             | Validate git repo, gh CLI, jq, authentication   |
| `detect-base.sh`           | Detect base branch name (main/master/next/epic-*, or a recorded stack parent) |
| `stack-sync.sh`            | Keep a stacked branch on its parent; print its fork point |
| `repo-context.sh`          | Fetch labels, collaborators, projects           |
| `repo-ownership.sh`        | Classify repo as personal / org / external      |
| `pr-reviewers.sh`          | Rank top PR reviewers by recent review activity |
| `issue-assignees.sh`       | Rank top issue assignees by recent assignments  |
| `issue-types.sh`           | List GraphQL-supported issue types              |
| `create-issue.sh`          | Create one issue and reconcile partial success  |
| `add-to-project.sh`        | Add issue to GitHub Projects V2                 |
| `get-issue-projects.sh`    | List projects an issue is already a member of   |
| `suggest-projects.sh`      | Rank up to 4 likely projects (USED + RELATED)   |
| `project-status.sh`        | Update project board status                     |

`detect-base.sh` prints a **branch name, not a rev.** An epic branch can exist only on
the remote, so `git log <base>..HEAD` fails with `unknown revision` on a name that has no
local branch. Use it as-is where a name is wanted (`git checkout`, `git pull origin`,
`gh pr create --base`); resolve it first wherever a rev is wanted:

```bash
baseref=$(git rev-parse --verify --quiet "origin/$base" || git rev-parse --verify --quiet "$base")
```

It exits `2` when the repo has no remote, in which case there is no base to detect —
Steps 2, 3, 5 and 6 stop on it and tell the user to add a remote rather than guessing `main`.

The name can also be missing in the *other* direction: it scans local `epic-*` branches
too, so the base may be a branch the remote has never seen. Anything that talks to the
remote with it — `git pull origin <base>`, `git rebase origin/<base>`,
`gh pr create --base <base>` — fails on such a base. Check before those steps and stop
with `Base branch <base> is not on the remote — push it first.` Detection is still right
to find it: falling back to the default branch would make Consolidate treat the whole
epic as commits ahead and squash it.

Run scripts from the skill directory as `bash "<skill-dir>/scripts/<name>.sh"`; each call site
gives its arguments.

## Step Router

Before routing, detect current state in parallel:

```bash
# Run all three in parallel (independent calls)
git branch --show-current                    # → current branch name
git status --short                           # → working tree state (staged, unstaged, untracked)
git log --oneline -1                         # → latest commit context
```

Use the current branch name to determine which steps are already done:
- On `issue-<N>` branch → Steps 1-2 are done, detect entry from there
- On base branch (main/master/etc.) with no changes → nothing to do
- On base branch with changes → full flow from Step 1

Determine entry step from user intent, check prerequisites, then proceed forward. Do not re-run earlier completed steps.

| User intent                          | Entry step | Prerequisite             |
| ------------------------------------ | ---------- | ------------------------ |
| "what's next", "pick an issue", "which issue" | Step 0 | gh authenticated       |
| Work intent with no issue number given | Step 0  | gh authenticated         |
| No arguments / empty invocation      | Step 1 (`references/creating-issues.md`) | Staged or changed files |
| "create issue", "new issue", several issues at once | Step 1 (`references/creating-issues.md`; Batch for several) | gh authenticated |
| "create issue linked to #N", "create sub-issue of #N" | Step 1 + Project Inheritance (`references/creating-issues.md`) | Parent #N exists |
| "add sub-issues to #N", "link issues to #N" | Sub-Issues (`references/creating-issues.md`) | Parent issue exists |
| "X blocks #N", "block #N with #M", "unblock #N" | Blocked-By (`references/creating-issues.md`) | Both issues exist |
| "start work on #N", "branch for #N"  | Step 2     | Issue exists             |
| "commit", "commit changes"           | Step 3     | On issue-* branch        |
| "snapshot", "wip snapshot"           | Step 3 snapshot | Dirty tree        |
| "push", "push changes"               | Step 4     | Commits ahead of remote  |
| "amend", "amend and push"            | Step 4 → Amend | Finished commit at the tip of issue-* |
| "create PR", "open PR"               | Step 5     | Branch pushed            |
| "merge", "merge PR"                  | Step 6     | PR exists                |

### No Arguments (Full Flow from Changes)

When invoked without arguments, use the state detected above:

1. If `git status --short` shows no output, stop — nothing to commit
2. If there are changes, analyze the diff content to infer issue type and description
3. Run the full flow (Steps 1–6) — stage only the identified files in Step 3

When the user says "full flow" or asks to go from issue to merge, run all steps sequentially. Otherwise, start at the detected step and ask whether to continue to the next step after each one completes.

Done means: every step the intent named has printed its report, or a gate is waiting on the user.
A step's `Then stop` ends the run only where the intent ends; a step the intent still names runs in
the same turn.

## Conventions

Read the target repo's CLAUDE.md for project-specific formatting. Use these defaults when no override is found:

- **Issue titles**: `<type>: <description>` (conventional commit format)
- **Commit subjects**: `<Issue Title> #<number>`
- **PR titles**: `<Issue Title> #<number>`
- **PR body**: one bullet per change, then `Closes #<number>`, one per line. GitHub links only the first reference after a keyword, so `Closes #1 #2 #3` closes #1 and leaves #2 and #3 open

Common types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `style`, `ci`

### Temp Files and Command Shape

Resolve one `<TMPDIR>` per flow with `mktemp -d` — at the first step that writes a file, if Step 1
did not — and spell it as the literal absolute path in
every command (e.g. `--body-file /var/folders/.../tmp.AbCdEf/body.md`). Do not set `TMPDIR=` as an
env var prefix — that changes the command pattern and triggers permission prompts. Never pass a
body as `--body "$(cat <<'EOF'...)"`: the `$()` makes the command unmatchable against any
pre-approval rule, so hosts that gate shell commands re-prompt every time. Write a file and pass
`--body-file`.

### Slice Delivery

Off unless the caller's intent names a slice (`"commit slice <k> of #<N>: <subject>"`) or says `slice delivery`, or the target repo's instruction file says a pull request carries one commit per slice. Off, nothing in this file changes. On, the branch holds one commit per finished slice: Step 3 commits only the current slice, under that slice's subject, and every finished slice commit survives Consolidate and Step 5. An intent with no slice subject (`"commit this"`) gets one derived from the staged diff as `<type>: <description>`, confirmed with the user.

### Asking the User

Every question in this skill is written as `AskUserQuestion` options. Use that tool where
the host offers it, or the host's nearest structured-choice equivalent. Where the host has
neither, ask the same question in normal chat as a numbered list of 2–5 options —
recommended first, one short line of description each — and wait for the user to reply
with a number.

Never silently pick for the user at a gate that changes git or GitHub state.

### Skip Interactive Prompts

When the user explicitly provides values for labels, assignee, project, or other options in their request, use those values directly — do not ask to confirm what was already stated. Only ask about fields the user left unspecified.

### Assignment Defaults

**Nothing this skill creates is ever left unassigned by default.** Every issue and PR gets an assignee unless the user explicitly asked for none.

"The current user" always means the authenticated `gh` account — resolve it, never assume a hardcoded login:

```bash
gh api user --jq .login
```

Prefer the literal `@me` in `gh` flags; use the resolved login only when a report or comparison needs the actual name.

Classify the repo once per flow — at whichever step the flow is entered, if not already done:

```bash
bash "<skill-dir>/scripts/repo-ownership.sh"
```

`KIND` drives the default:

| `KIND`     | Meaning                            | Default behaviour                                                     |
| ---------- | ---------------------------------- | --------------------------------------------------------------------- |
| `personal` | Owned by the current user          | Assign the current user (`@me`) silently — do **not** prompt           |
| `org`      | Owned by an organization           | Ask, per **Asking the User**; the current user is the recommended default |
| `external` | Another user's personal repo       | Same as `org` — ask, current user recommended                          |

In every case the fallback is the current user: if the user skips the question, the prompt cannot be shown, or `repo-ownership.sh` fails, assign `@me` rather than nothing.

An explicit instruction always wins — "assign to @octocat", "leave it unassigned", or a reviewer/assignee rule in the target repo's CLAUDE.md overrides everything above, in personal repos too.

People to offer come only from `issue-assignees.sh` and `pr-reviewers.sh`. When one returns nothing, offer no one else: the generic `repo-context.sh` collaborator list is repo members ranked by nothing meaningful, and inventing labels like "Frequent collaborator" misleads the user.

## Step 0: Select Issue

Use when no issue number was given and the intent is to work on something — "what's
next", "pick an issue", or a bare work intent with nothing to work on named.

Invoke the `next-issue` skill, passing on any narrowing the user stated ("something
small", "a bug"). It checks the repo and auth, ranks the backlog, and prints its report;
Step 0 owns only the question after it. If `next-issue` cannot be chained, ask the user
for an issue number — do not rank the backlog here.

With no entry above **Not now**, stop. Otherwise ask, per **Asking the User**,
one option per such entry in report order, at most three, then `None`:

- **Header**: `Issue #<N>`, or `#<N>` past four digits
- **Label**: the title, cut to five words; a `Recommended` entry gets `(Recommended)`
- **Description**: the entry's tag line, then its `Why:` line
- **`None`**: `Skip issue selection`

On a pick, invoke `issue-analyze` on `<N>` with no summary first; if it cannot be chained,
print the number, title, and `Why:` line. Continue to Step 2 only when the caller's intent
named it; otherwise stop after the analysis. Step 0 only reads.

On `None`, stop — do not fall through to Step 1 and create an issue nobody asked for.

## Step 1: Create Issue

Entered from the router's create rows — a new issue, a sub-issue or linked issue, sub-issue
links, blocked-by links, and batch creation. Read `references/creating-issues.md` and follow
the section for the intent: it owns the setup batch, title, epic detection, body, labels,
assignee, type, project, milestone, the create wrapper and its exit codes, media, and the
relationship paths.

Print one report: the Step 1 report (`references/report-format.md`) for a created issue, the batch
summary for a batch, or the one line **Sub-Issues** or **Blocked-By** names for a link. Then stop: no branch exists — Step 2 runs only when the intent named it or the user says to continue.

## Step 2: Create Branch

Run `detect-base.sh` to find the correct base branch — unless the user named one, as a stacked
pull request does ("start work on #N from issue-41"). Then `<base>` is that branch, and
`references/stacking.md` → **Step 2** owns its checks and the record it leaves.

A dirty tree in the full flow from uncommitted changes is the work itself. Carry it over — checkout and pull would fail on it, and you're already on the base:

```bash
git checkout -b issue-<number>
```

A dirty tree the caller asked to stash (`"start work on #N, stash local changes"`) is not the work. Stash it, naming the branch the Step Router read, then take the clean path. Report `Stashed:` only if `git stash list` now shows the entry:

```bash
git stash push -u -m "issue-<number> from <current-branch>"
```

A clean tree (entered at Step 2 directly, e.g. "start work on #N"):

```bash
git checkout <base> && git pull origin <base>
git checkout -b issue-<number>
```

If `issue-<number>` already exists, ask, per **Asking the User**:
1. "Switch to existing branch" (Recommended)
2. "Delete and create fresh"

Update project status to "In Progress" (if project integration is available):

```bash
bash "<skill-dir>/scripts/project-status.sh" <number> "In Progress"
```

Resolve the fork point for the report, so callers never have to turn the base name back
into a rev:

```bash
baseref=$(git rev-parse --verify --quiet "origin/$base" || git rev-parse --verify --quiet "$base")
git merge-base "$baseref" HEAD
```

Print the Step 2 report, including both `Base:` and `Fork:`. Then stop: do not commit and do not start implementing — the branch is this step's whole deliverable.

## Step 3: Commit

**This step owns the commit subject format, the commit body, and the squash rules for
the whole pipeline.** Nothing else defines them — callers delegate here.

### Subject

Use `<Issue Title> #<number>` as the commit subject. The issue title is already in conventional commit format from Step 1 or from the `issue-analyze` skill.

If there is no linked issue (e.g., entered at Step 3 directly), use the repo's CLAUDE.md commit format or fall back to `<type>: <description>`.

Under **Slice Delivery**, the subject is the slice's own conventional subject plus ` #<number>`, so each slice commit names what it did. `<Issue Title> #<number>` stays the subject of an issue delivered in one commit.

No `wip:` subject may survive into the final history.

### Body

Invoke the `commit-summary` skill to generate the commit body.

If the host cannot invoke another skill, or `commit-summary` is not installed, do the same inline.
For a change to behaviour, a contract, a public type, or a default, or a defect fix, answer in
blank-line-separated paragraphs wrapped at 80 — what forces the change, which call paths reach it,
how it failed, what breaks on update, what the tests pin — dropping any with no real answer.
Otherwise write two or three past-tense lines. Cite a hash only if a command returned it here.

When the caller supplies design rationale pulled out of source comments (the `code-cleanup`
skill produces this), it answers the first question — fold it into that paragraph. It is not
a block to append at the end of the body.

### No attribution

This step runs the `git commit`, so it is the last place an attribution footer can be caught.
Read the assembled message before committing and **remove** any of these, wherever they came
from — a body another skill returned, text a caller passed in, a message being amended:

- "Drafted with AI", "Generated with", or any line naming a model, an assistant, or a tool
- a session, chat, or transcript link
- a `<sub>` attribution line, a trailing `---` rule, a badge, or a promotional line
- a `Co-Authored-By` trailer crediting an assistant

Do not add one, and **do not copy one forward from the previous commit** — mirroring the last
footer is how one reproduces itself. A trailer crediting a *human* is fine where the repo asks for
one. The only exception is an explicit request in the repo's instruction file, the user's
configuration, or the prompt; finding one in `git log` is not that.

### Consolidate

The branch must end this step at **exactly one commit past `$from`** — the whole branch, or under **Slice Delivery** the current slice — and this section owns the only gate that can decide otherwise.

#### Resolve the fork point

Count and reset must use the **same** ref, and it must be an ancestor of `HEAD`. Resolve it once.
On a stacked branch (`branch.<current>.issueFlowBase` set), run `stack-sync.sh` first, stop on a
non-zero exit per `references/stacking.md`, and take `base` and `fork` from its `BASE=` and `FORK=`:

```bash
base=$(bash "<skill-dir>/scripts/detect-base.sh" 2>/dev/null | tail -n1) || base=""
[ -n "$base" ] || { echo "No base branch — add a remote first."; exit 1; }
baseref=$(git rev-parse --verify --quiet "origin/$base" || git rev-parse --verify --quiet "$base")
fork=$(git merge-base "$baseref" HEAD)
from=$fork
slice_delivery=<on|off>   # per Conventions → Slice Delivery
if [ "$slice_delivery" = on ]; then
  last=$(git log --format='%H %s' "$fork"..HEAD | awk '$2 != "wip:" { print $1; exit }')
  [ -n "$last" ] && from=$last
fi
git log "$from"..HEAD --oneline
```

Under **Slice Delivery**, a `last` whose subject equals the composed subject this call commits (`<subject> #<number>`) is the current slice entered again — set `from` to its parent so the canonical row below amends it instead of stacking a second commit.

**Never reset to `origin/<base>`, and never to a branch name.** `origin/<base>` moves whenever anything fetches, and `detect-base.sh` fetches on its own. Reset to it and the new commit's parent is *newer* than the point the branch was cut from, so the commit silently reverts every upstream change made since — and Step 5 force-pushes that, and Step 6 merges it. `$fork`, and every commit after it that `$from` can name, is an ancestor of `HEAD` by construction, so neither can have that effect.

#### Choose the action

| Commits ahead of `$from` | Action |
| ------------------------ | ------ |
| **0** | Nothing to unwind — go to **Execute**. |
| **1**, subject already canonical | Keep the commit. If the tree is dirty (a caller's comment trim or cruft deletion usually leaves it that way), stage the remaining edits and rewrite the message from **Subject** and **Body**: `git commit --amend -m "<subject>" -m "<body>"`. Do **not** use `--amend --no-edit` — it keeps the old message and discards the body this step just generated, including any rationale the caller passed in. |
| **1**, a `wip:` snapshot | `git reset --soft "$from"`, then **Execute**. |
| **2+**, one shared subject, or any `wip:` among them | `git reset --soft "$from"`, then **Execute** — one commit with the combined changes. |
| **2+**, genuinely different subjects | Ask before rewriting deliberate history: option 1 `Squash into one commit` `(Recommended)`, option 2 `Keep as-is`. Squash → `git reset --soft "$from"`, then **Execute**. Keep → skip **Execute** and report the commits as they stand; this is the one outcome that leaves more than one commit. |

A caller that asked for a single commit (`"commit #<N>"` from an orchestrating skill) has already answered that question — squash without prompting.

#### Check the index before committing

`git reset --soft` leaves **the entire difference between `$from` and the last commit staged** — every file from every commit it unwound, including anything a `wip:` snapshot swept in. Read that as *committed* difference: the reset restores the index to `HEAD`'s content, so it captures nothing you edited after the last commit. Naming files in **Execute** *adds* to that index; it does not narrow it. So after any reset, read the index and remove what must not ship:

```bash
git diff --cached --name-only
git restore --staged <path>      # per file that does not belong in the commit
```

Deleting the file from disk is not enough once it is staged — unstage it. Untracked files are the one thing the reset does not capture; they stay untracked unless something adds them.

### Execute

Stage what belongs in the commit, then commit:

```bash
git add <files>
git commit -m "<subject>" -m "<body>"
```

Two different states reach this point, and the staging rule differs:

- **No reset happened** (the `0` row). The index starts empty, so `git add <files>` fully determines the commit. Prefer naming files over `git add -A` — here it genuinely is the check that keeps scratch files out.
- **A reset happened.** The index already holds everything Consolidate unwound, so `git add` here is for whatever it does **not** already carry — two sets, not one. Stage both, then read the index one last time, in this order:

  ```bash
  git add -u                      # edits to tracked files made after the last commit
  git add <files>                 # files that were never committed
  git diff --cached --name-status # re-read: staging may have undone Consolidate's check
  git restore --staged <path>     # per stray that came back
  ```

  `git add -u` is the one that is easy to miss and silent when missed. The reset restores the index to `HEAD`'s content, so an edit made after the last `wip:` snapshot sits unstaged and the commit ships the tree as it was *before* it, with no error. This is the mainline path, not an edge case: a caller that trims comments or applies review fixes after its last snapshot lands here every time.

  **The re-read is not optional, and it reads status, not just names.** `git restore --staged` never touches the working tree, so a stray Consolidate unstaged still differs from the index — and `git add -u` puts it straight back. Consolidate's check runs before staging; only this one sees what will actually be committed. Read the letter beside each path: a file that was `M` in the first check and is `D` in this one was deleted from the working tree after Consolidate vetted it, and `git add -u` has just staged its removal. A path you already cleared is not a path you can skip.

Finish with `git status --short`. A **modified tracked file** still listed is the missed-`git add -u` bug, not a leftover — stage it and amend. Untracked files you deliberately left out may still be listed; that is expected, and Step 3 has no authority to delete them.

Print the Step 3 report. Then stop: do not push and do not open a PR — Step 4 runs only when the intent named it or the user says to continue.

### Snapshot Mode

Entered on intent "snapshot" — a caller needs the working tree frozen into a commit
without finishing the work. Used to give reviewers a stable diff, or to checkpoint
during a long implementation.

```bash
git status --short          # confirm nothing scratch is about to be staged
git add -A && git commit -m "wip: snapshot"
```

Snapshot mode skips the Subject, Body, and Consolidate sections entirely:

- The subject is content-free. A snapshot message describing the work leaks the
  implementer's reasoning into a place reviewers can read.
- No `commit-summary` call — there is no body.
- No report. Print one line: `Snapshot: <short-sha>`.

Snapshots are not final commits. A later Step 3 run squashes them away via
**Consolidate**.

## Step 4: Push

On a stacked branch, run `stack-sync.sh` first, per `references/stacking.md`. Push the branch to remote:

```bash
git push -u origin issue-<number>
```

### Rebase if needed

If push fails because the remote has diverged, or if the user asks to rebase — capture
`before` **first**, rebase, then push, both per [Leasing a force-push](#leasing-a-force-push).
On a stacked branch `stack-sync.sh` does the rebase instead (`references/stacking.md`):

```bash
git fetch origin <base>
git rebase origin/<base>
```

### Amend

If the user asks to amend the last commit — including when another skill enters here to
fold post-review fixes back into a commit that is already pushed.

**Stage the fixes you were called here to fold in first** — a caller entering this path (post-review fixes, a comment trim) leaves its edits in the working tree, not the index, and `git commit --amend` commits the index. Skip this and the amend rewrites the message, force-pushes, re-triggers CI and the reviewers, and lands **none of the fixes** — while reporting success.

```bash
git add -u                      # edits to tracked files
git add <files>                 # anything new that belongs in the commit
git diff --cached --name-status # now read what will actually ship
```

Read that last list before committing. This path rewrites published history and force-pushes it, so a stray staged file is not a bad commit that can be followed by a better one — `git restore --staged <path>` anything that must not ship, exactly as Step 3 requires before an ordinary commit. An empty list means there was nothing to amend: stop rather than force-pushing an identical tree.

Then check the branch really is at one commit — `git log --oneline <base>..HEAD` — or, under **Slice Delivery**, that the tip is a finished slice, which the amend lands on; say so in the report. Amending
only rewrites the tip, so a branch carrying `wip:` snapshots needs Step 3 → Consolidate
first; amending it would push the snapshots along with the fix.

Capture `before`, amend, then push, per [Leasing a force-push](#leasing-a-force-push):

```bash
git commit --amend -m "<subject>" -m "<body>"
```

Never a bare `git commit --amend`: it opens `$EDITOR`, which hangs a non-interactive shell.
`--no-edit` belongs here only — folding fixes the kept message already describes, which is what
a caller's "message verbatim" means — and never in Consolidate, which writes a new body.

Print the `Pushed (amended)` report.

### Leasing a force-push

Every force-push in this pipeline pins the SHA it expects the remote to be at, captured
**before** anything fetches:

```bash
before=$(git rev-parse "origin/issue-<number>" 2>/dev/null || true)
# ... rebase, amend, or consolidate ...
if [ -n "$before" ]; then
  git push --force-with-lease="issue-<number>:$before"
else
  git push -u origin issue-<number>
fi
```

`rev-parse` is guarded because the branch may not be on the remote yet: a bare one exits 128,
which under `set -e` aborts the step instead of pushing. An empty `$before` has nothing to
lease against, so it is a plain push.

A bare `--force-with-lease` leases against `refs/remotes/origin/issue-<number>`, which any fetch
refreshes — `detect-base.sh` runs one inside Consolidate — and a refreshed lease permits exactly
the overwrite it exists to prevent. `--force-if-includes` is no substitute: `git help push` calls
it a no-op with an explicit `<expect>`. Pin the SHA.

If the push is rejected, the remote moved: fetch, rebase onto the new tip, and re-run
rather than escalating to `--force`.

Print the Step 4 report. Then stop: do not create a PR — Step 5 runs only when the intent named it or the user says to continue.

## Step 5: Create PR

Run `detect-base.sh` to determine the PR base.

### Pre-PR: Squash Commits

Under **Slice Delivery**, resolve `$from` first. If `git log "$from"..HEAD` is non-empty or the tree is dirty, stop with `Unfinished slice on top of <short-sha> — commit it first.`; otherwise there is nothing to consolidate — go to **Title and Body**.

Apply **Step 3 → Consolidate** as-is. It owns the fork point, the count, the squash rules, and the one gate that may leave several commits — including the case where the single commit on the branch is a `wip:` snapshot, which must not reach a PR title. Do not restate any of those rules here; a second copy is how the two drift.

The only thing this step adds is that the branch is already on the remote, so the rewrite has to be force-pushed: capture `before` **before** consolidating, then push, per [Leasing a force-push](#leasing-a-force-push).

This must happen before PR body generation, since consolidating changes the commit log.

### Title and Body

- **Title**: `<Issue Title> #<number>`
- **Body**: Generate from `git log "$fork"..HEAD --oneline` — reuse the `$fork` that
  **Step 3 → Consolidate** just resolved. Do not write `git log <base>..HEAD`: `<base>`
  is a branch name, and an epic branch that exists only on the remote fails there with
  `unknown revision`. Add `Closes #<number>`.

```markdown
## Changes

- <change 1>
- <change 2>

Closes #<number>
```

### Assignee and Reviewer

Pick reviewers here. **### Assignees** derives the PR's assignees from them; the `KIND` prompt is for issues only.

In a `KIND=personal` repo, skip the reviewer prompt unless the repo's CLAUDE.md sets a reviewer rule or the user asked for one — a solo repo has no one else to review.

Check the target repo's CLAUDE.md for reviewer rules (e.g., "PRs to main should be reviewed by @username"). If one matches, use that reviewer directly.

Otherwise, run `pr-reviewers.sh` to find users with actual recent PR review activity:

```bash
bash "<skill-dir>/scripts/pr-reviewers.sh"
```

Output: `<user>\t<count>` per row, up to 3 rows (excludes self and bots; counts reviews and review requests across the last 100 PRs in any state).

- **0 results**: skip the prompt entirely and create the PR without `--reviewer` — no collaborator-list fallback, per **Assignment Defaults**.
- **1+ results**: ask, per **Asking the User**:
  1. First result (Recommended), description: `"<count> review events across the last 100 PRs"`
  2. Second result (if any), description: `"<count> review events across the last 100 PRs"`
  3. "No reviewer"

Drop the creator from the reviewers (the login from **### Assignment Defaults**) — GitHub rejects self-review.

### Assignees

A reviewer approves; assignees own the merge and the PR's work. So the creator (`@me`) is always an assignee, in every repo kind, and so is every human reviewer, on top of the review request. A bot reviewer (Copilot, any `[bot]` login) is only requested, never assigned. With no reviewer, `@me` alone — never zero assignees. Explicit instructions still win, per **### Assignment Defaults**.

e.g. creator `alice`, reviewers `octocat` and Copilot → Reviewers: `octocat`, Copilot; Assignees: `alice`, `octocat`.

### Create

Write the PR body to `<TMPDIR>/pr-body.md` with the host's file-write tool, per **Temp Files and Command Shape**, then create the PR — `--assignee` for each human reviewer, `--reviewer` for every reviewer, both omitted with none:

```bash
gh pr create --title "<title>" --body-file <TMPDIR>/pr-body.md --base <base> --assignee @me [--assignee <reviewer>] [--reviewer <reviewer>]...
```

No media in a PR body, though `gh pr create` accepts `--attach`: release notes read it after the old behaviour is gone — the before-state belongs on the issue, an after-state in a PR comment.

Update project status to "Review":

```bash
bash "<skill-dir>/scripts/project-status.sh" <number> "Review"
```

### Verify mergeability

**Always run this after creating a PR**, whether or not Step 6 will follow. A PR that cannot merge is not a finished step, and reporting "PR created" without checking hides that.

GitHub computes `mergeable` asynchronously, so it returns `UNKNOWN` for the first second or two — poll until it settles:

```bash
for i in 1 2 3; do
  state=$(gh pr view <pr-number> --json mergeable,mergeStateStatus --jq '.mergeable + " " + .mergeStateStatus')
  case "$state" in UNKNOWN*) sleep 3 ;; *) break ;; esac
done
echo "$state"
```

| Result | Action |
| ------ | ------ |
| `MERGEABLE` | Report `Mergeable: yes` on the Step 5 report and continue. |
| `CONFLICTING` | **Rebase and re-check**: `git fetch origin && git rebase origin/<base>` (a stacked branch runs `stack-sync.sh`), force-push per [Leasing a force-push](#leasing-a-force-push), re-run the poll. If conflicts are not mechanical, invoke the `resolve-conflicts` skill; if still unresolved, report `Mergeable: no — conflicts with <base>` and **stop before Step 6**. |
| `UNKNOWN` after 3 polls | Report `Mergeable: unknown (GitHub still computing)`. Do not treat as failure. |

`mergeStateStatus` adds context worth reporting when it is not `CLEAN`:
- `BEHIND` — base moved ahead; **Rebase and re-check**.
- `BLOCKED` — branch protection or a required review is pending. Not a conflict; report it as-is.
- `UNSTABLE` — checks are failing or still running.

Do **not** run `gh pr checks --watch` here. Check monitoring belongs to Step 6; a PR-only flow reports the mergeability state and ends.

Print the Step 5 report, including the `Mergeable:` line. Then stop: Step 6 runs only on the entry conditions in **### Entering Step 6 at all**, and reaching Step 5 is not one of them.

## Step 6: Merge PR

### Skip Condition

Determine the current user: `gh api user --jq .login`. If a human PR reviewer OR assignee is someone **other than** the current user, **skip Step 6**; a bot reviewer does not count:

```
PR #<number> is ready for review by @<reviewer> (mergeable: <state from Step 5>). Merge skipped — awaiting external review.
Stashed: <stash message>        (only when the entry below exists)
```

If reviewer AND assignee are the current user (self-review), or user explicitly asked to merge, proceed below.

### Entering Step 6 at all

Step 6 is entered on exactly three things: an intent naming the merge
(`"merge #<N>"`, `"push, PR, and merge #<N>"`), the user answering the suggestion below,
or the user asking to merge in conversation. Otherwise stop after Step 5 — never suggest a merge to an intent that ended there.

### Confirm exactly once

The merge is confirmed **once per flow**, and this section decides where that happens.
Classify the entry, then take one branch and skip the other.

| Entry | Confirmation |
| ----- | ------------ |
| **The intent already names the merge** — `"push, PR, and merge #<N>"`, `"merge #<N>"` from an orchestrating skill that already put the question to the user | Already confirmed. Print the pre-merge summary for the record and go straight to **Pre-checks**. Asking again is the duplicate prompt callers are told not to create. |
| **A full flow that entered at Step 1 and was never told what to do about merging** | Not yet confirmed. Print the pre-merge summary and suggest merging (below). |
| **Direct entry at Step 6 by the user**, no earlier step in this flow | Not yet confirmed. Merging closes the PR and writes to the base branch. Print the pre-merge summary, show the PR number, the base branch, and the merge method, and wait for approval before merging. |

When confirmation is still needed, ask, per **Asking the User**:
1. "Merge now" (Recommended) — wait for checks and merge
2. "Skip" — leave PR open, end flow

"Skip" → print the skip message and stop. "Merge now" → continue to **Pre-checks**.

Either way the pre-merge summary is printed (see `references/report-format.md`) — it is
the record of what is about to be merged, not the prompt itself.

### Pre-checks

1. Check PR state:

```bash
gh pr view <pr-number> --json state,mergeable
```

- If PR is not open: report current state and **stop**.
- If there are conflicts: **Rebase and re-check** (Step 5), then continue to step 2.

2. Wait for CI checks with a 5-minute timeout (`timeout` on Linux, `gtimeout` from coreutils on macOS):

```bash
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN=timeout
else
  TIMEOUT_BIN=gtimeout
fi
"$TIMEOUT_BIN" 5m gh pr checks <pr-number> --watch --fail-fast
```

- Exit 0 (all passed/skipped) → proceed to step 3
- Exit 1 (failure) → report failed checks, **stop**. Do not merge.
- Exit 124 (timeout) → report timeout, then ask, per **Asking the User** — a merge intent or an earlier merge confirmation does not answer this question, so an unattended caller takes option 1:
  1. "Stop without merging" (Recommended) — leave the PR open, report `Checks: not confirmed (watch timed out)`, stop
  2. "Wait longer" — re-run the same timeout command
  3. "Merge anyway" — proceed to step 3; the merged report carries `Checks: not confirmed (watch timed out)`
- Exit 127 (`gtimeout` missing) → report the missing timeout binary and **stop**.

3. After checks pass, verify mergeability one more time:

```bash
gh pr view <pr-number> --json mergeable --jq '.mergeable'
```

If conflicts appeared, **Rebase and re-check**, then re-run step 2.

### Merge

```bash
gh pr merge --rebase --delete-branch
```

Find Step 2's stash in `git stash list` by its `issue-<number> from <current-branch>` message — a fresh invocation has no other record of it. If the merge left you on that `<current-branch>`, run `git stash pop "stash@{<n>}"` with `<n>` from the entry's line — never a bare `stash@{0}`. On any other branch, leave it. A conflicted pop keeps the entry: stop, list the conflicted files, and never reset. Both add `Stashed:` to the report.

`Closes #<number>` fires only on the default branch. On any other base (epic-*, next, a stack parent), confirm `gh pr view <pr-number> --json state,mergeCommit` reads `MERGED` (otherwise report the state and stop), then close each `Closes` issue with exactly this, `<short-sha>` = `mergeCommit.oid` cut to 7:

```bash
gh issue close <number> --comment 'Landed on `<base>` in <short-sha> via #<pr-number>.'
```

On an `epic-*` base, then link it on the epic's PR per `references/github-relationships.md` → **Landed Sub-Issues**.

Update project status to "Done":

```bash
bash "<skill-dir>/scripts/project-status.sh" <number> "Done"
```

Print the Step 6 merged report.

## Error Handling

- **Projects V2 fails**: Warn once, then skip all project operations for the rest of the flow — the core lifecycle works without them. Carry `Project: skipped (Projects V2 unavailable)` on every later step report that would have updated the board. Token setup is in `references/project-integration.md`.
- **Assignment rejected** (`gh` reports the assignee is not a valid collaborator): report which assignee was dropped, then continue. Do not abort the flow or retry with a different user.
- **gh not authenticated**: Stop immediately, tell user to run `gh auth login`.
