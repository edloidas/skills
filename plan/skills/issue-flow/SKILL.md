---
name: issue-flow
description: >
  Full GitHub issue lifecycle: pick an issue, create it, branch, commit, squash, push, PR,
  merge. Owns every git and gh write in the pipeline. Handles project board integration, base
  branch detection (main/master/epic-*), and compact step reports. Supports entering at any
  step.
when_to_use: >
  On "which issue should I work on", "create an issue", "start work on #N", "commit this",
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

Mutation class: **writes and pushes, and writes to external services (GitHub)** — branch creation, snapshots, commits, squashing, pushes, PRs, merges. This skill owns every one of them, plus issue selection. Skills that orchestrate the pipeline (`solve-issue`) delegate those actions here rather than reimplementing them, so the commit subject format and the squash rules exist in exactly one place.

## Bundled Scripts

Located in `scripts/` relative to this skill:

| Script                     | Purpose                                         |
| -------------------------- | ----------------------------------------------- |
| `check-env.sh`             | Validate git repo, gh CLI, jq, authentication   |
| `detect-base.sh`           | Detect base branch name (main/master/next/epic-*) |
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
stop and tell the user to add a remote rather than guessing `main`.

The name can also be missing in the *other* direction: it scans local `epic-*` branches
too, so the base may be a branch the remote has never seen. Anything that talks to the
remote with it — `git pull origin <base>`, `git rebase origin/<base>`,
`gh pr create --base <base>` — fails on such a base. Check before those steps and stop
with `Base branch <base> is not on the remote — push it first.` Detection is still right
to find it: falling back to the default branch would make Consolidate treat the whole
epic as commits ahead and squash it.

Run scripts from the skill directory:

```bash
bash "<skill-dir>/scripts/check-env.sh"
bash "<skill-dir>/scripts/detect-base.sh"
bash "<skill-dir>/scripts/repo-context.sh"
bash "<skill-dir>/scripts/repo-ownership.sh" [<owner>/<repo>]
bash "<skill-dir>/scripts/pr-reviewers.sh" [<owner>/<repo>] [<limit>]
bash "<skill-dir>/scripts/issue-assignees.sh" [<owner>/<repo>] [<limit>]
bash "<skill-dir>/scripts/issue-types.sh" [<owner>/<repo>]
bash "<skill-dir>/scripts/create-issue.sh" -- --title "<title>" --body-file <path> [...]
bash "<skill-dir>/scripts/add-to-project.sh" <issue-number> <project-title> [status]
bash "<skill-dir>/scripts/get-issue-projects.sh" <issue-number>
bash "<skill-dir>/scripts/suggest-projects.sh" [<owner>/<repo>]
bash "<skill-dir>/scripts/project-status.sh" <issue-number> <status>
```

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
| No arguments / empty invocation      | Step 1     | Staged or changed files  |
| "create issue", "new issue"          | Step 1     | gh authenticated         |
| "create issue linked to #N", "create sub-issue of #N" | Step 1 + Project Inheritance | Parent #N exists |
| "add sub-issues to #N", "link issues to #N" | Sub-issues | Parent issue exists |
| "X blocks #N", "block #N with #M", "unblock #N" | Blocked-by | Both issues exist |
| "start work on #N", "branch for #N"  | Step 2     | Issue exists             |
| "commit", "commit changes"           | Step 3     | On issue-* branch        |
| "snapshot", "wip snapshot"           | Step 3 snapshot | Dirty tree        |
| "push", "push changes"               | Step 4     | Commits ahead of remote  |
| "amend", "amend and push"            | Step 4 → Amend | One commit on issue-* branch |
| "create PR", "open PR"               | Step 5     | Branch pushed            |
| "merge", "merge PR"                  | Step 6     | PR exists                |

### No Arguments (Full Flow from Changes)

When invoked without arguments, use the state detected above:

1. If `git status --short` shows no output, stop — nothing to commit
2. If there are changes, analyze the diff content to infer issue type and description
3. Run the full flow (Steps 1–6) — stage only the identified files in Step 3

When the user says "full flow" or asks to go from issue to merge, run all steps sequentially. Otherwise, start at the detected step and ask whether to continue to the next step after each one completes.

## Conventions

Read the target repo's CLAUDE.md for project-specific formatting. Use these defaults when no override is found:

- **Issue titles**: `<type>: <description>` (conventional commit format)
- **Commit subjects**: `<Issue Title> #<number>`
- **PR titles**: `<Issue Title> #<number>`
- **PR body**: one bullet per change, then `Closes #<number>`, one per line. GitHub links only the first reference after a keyword, so `Closes #1 #2 #3` closes #1 and leaves #2 and #3 open

Common types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `style`, `ci`

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
| `org`      | Owned by an organization           | Ask via `AskUserQuestion`; the current user is the recommended default |
| `external` | Another user's personal repo       | Same as `org` — ask, current user recommended                          |

In every case the fallback is the current user: if the user skips the question, the prompt cannot be shown, or `repo-ownership.sh` fails, assign `@me` rather than nothing.

An explicit instruction always wins — "assign to @octocat", "leave it unassigned", or a reviewer/assignee rule in the target repo's CLAUDE.md overrides everything above, in personal repos too.

## Step 0: Select Issue

Use when no issue number was given and the intent is to work on something — "what's
next", "pick an issue", or a bare work intent with nothing to work on named.

Validate the environment and resolve the repo first:

```bash
bash "<skill-dir>/scripts/check-env.sh"
gh repo view --json nameWithOwner --jq '.nameWithOwner'
gh api user --jq .login
```

If `gh repo view` fails, stop: `Not inside a GitHub repository.`

Then run the ranking pipeline in `references/issue-selection.md`. It reads local git
state, plan files, open PRs, and the backlog, ranks candidates into five tiers, and
presents up to four picks via `AskUserQuestion`. Every command it runs is a read — Step
0 never writes.

On selection it hands off to the `issue-analyze` skill for the full implementation
analysis. Continue to Step 2 with the selected number when the flow is meant to keep
going; stop after the analysis when the user only asked what to work on next.

If the user picks `None`, stop — do not fall through to Step 1 and create an issue
nobody asked for.

## Step 1: Create Issue

Run these in parallel (they are independent):

```bash
# Parallel batch
bash "<skill-dir>/scripts/check-env.sh"
mktemp -d                                       # → save output as <TMPDIR>
bash "<skill-dir>/scripts/repo-context.sh"
bash "<skill-dir>/scripts/repo-ownership.sh"
```

Wait for all four before proceeding. `detect-base.sh` is not needed until Step 2.

### Title

Use conventional commit format: `<type>: <description>`. Defer to CLAUDE.md conventions if they differ.

### Epic Detection

Before writing the body or picking a label, determine if this is an **epic issue** — one that coordinates work without containing implementation itself. Signals:

- User mentions "epic", "umbrella", "tracking issue", or "aggregated issue"
- Issue groups multiple child issues or feature areas
- No concrete implementation details — only scope or coordination

If it is an epic, and the repo has an `epic` label (check `repo-context.sh` output), apply `epic` as the label without asking. Skip the normal type-based label inference. If `epic` label does not exist in the repo, fall through to normal label selection.

### Body

Write a 2-4 sentence description. No markdown headers.

For epic issues: **do not list child issue numbers in the body.** Sub-issue relationships are managed via the GitHub sub-issues API (see **## Sub-Issues**), not via body text.

### Labels

Auto-detect label from the issue type (e.g., `feat` → `feature` or `enhancement`). Match against labels fetched by `repo-context.sh`. Use `AskUserQuestion` to confirm with the user — show top 3 matching labels + "No label".

### Assignee

Follow **### Assignment Defaults**.

**`KIND=personal`** — assign `@me` via `--assignee "@me"` without prompting. Skip `issue-assignees.sh` entirely.

**`KIND=org` or `KIND=external`** — run `issue-assignees.sh` to find users with actual recent assignment activity:

```bash
bash "<skill-dir>/scripts/issue-assignees.sh"
```

Output: `<user>\t<count>` per row, up to 3 rows (excludes self and bots). Compose `AskUserQuestion`:

1. `@me` (Recommended)
2. First result, description: `"Assigned to <count> of last 100 issues"`
3. Second result, description: `"Assigned to <count> of last 100 issues"`
4. "No assignee"

If `issue-assignees.sh` returns nothing, show only `@me` and "No assignee". Do **not** fall back to the generic `repo-context.sh` collaborator list — those are repo members ranked by nothing meaningful, and inventing labels like "Frequent collaborator" misleads the user.

If the question is skipped or unanswered, default to `@me` — never create the issue with no assignee.

### Type

Issue types are an organization-level feature. Probe through the same GraphQL field `gh issue create` depends on:

```bash
bash "<skill-dir>/scripts/issue-types.sh"
```

- Names returned → map the conventional commit type onto the closest one and pass
  `--type "<name>"` to the create wrapper.
- Empty output → the repo has no assignable issue types. This is the normal answer for a
  personal repo. Skip silently.

Do **not** probe with the REST `repos/<owner>/<repo>/issue-types` catalog: it can list type names for a personal repository even though GraphQL `repository.issueTypes` is `null`, and `gh issue create --type` will fail after creating the issue. Do **not** probe with `gh issue create --type bug --dry-run`; there is no `--dry-run` flag.

### Project

If creating a child of an existing parent (linked, attached, or sub-issue of #N), follow **## Project Inheritance From Parent** instead.

Otherwise, rank candidates via `suggest-projects.sh` (output: `<bucket>\t<id>\t<title>\t<note>` per row; `USED` = projects from your recent issues, `RELATED` = other active projects):

```bash
bash "<skill-dir>/scripts/suggest-projects.sh"
```

Compose `AskUserQuestion`: slot 1 (Recommended) = first row, slots 2–4 = next rows, with `<note>` as each option's description. Backfill the last slot with "No project" when fewer than 4 rows exist; skip silently when zero rows. On selection, run `add-to-project.sh <issue-number> "<project-title>"`.

### Milestone

**Trigger:** Check milestones when either:
- The user explicitly asks to assign a milestone
- The target repo's CLAUDE.md mentions milestones (any mention — section headers, instructions, config)

If neither trigger matches, skip silently.

**When triggered**, fetch open milestones:

```bash
gh api "repos/<owner>/<repo>/milestones?state=open" --jq '.[] | {number, title, state, open_issues, closed_issues, due_on}'
```

Then apply:
- **0 milestones**: skip silently
- **1 milestone**: assign automatically — inform the user which milestone was used
- **2+ milestones**: use `AskUserQuestion` to pick one:

```
Which milestone for this issue?
1. "<title1>" (Recommended) — X open / Y closed, due YYYY-MM-DD
2. "<title2>" — X open / Y closed, due YYYY-MM-DD
3. No milestone
```

Order by due date (soonest first). The first non-closed milestone is recommended.

Assign via `--milestone "<title>"` in the create-wrapper command.

### Create

Use the `<TMPDIR>` from the parallel setup batch. Write the issue body to `<TMPDIR>/body.md` with the host's file-write tool, then create the issue through the wrapper:

```bash
bash "<skill-dir>/scripts/create-issue.sh" -- --title "<title>" --body-file <TMPDIR>/body.md --label "<label>" --assignee "<assignee>" [--type "<name>"] [--milestone "<name>"]
```

The wrapper runs `gh issue create` once. If `gh` returns nonzero after creating the issue, it checks recent issues by exact title, current author, and the creation window; when exactly one match exists, reuse that URL and continue. If it exits nonzero, stop and reconcile manually. Do not retry issue creation until that reconciliation finds no created issue.

When creating multiple issues, use unique filenames per issue: `<TMPDIR>/<slug>-body.md` (e.g. `auth-body.md`, `settings-body.md`). Resolve `<TMPDIR>` once and reuse it for all issues.

**Media the body references.** Where the body carries a local image or video path — a screenshot of the bug, a mockup — pass it through the wrapper once per file. Alt text follows the path after a `#`, on images only: a video renders as a player and cannot carry any, so a `#` on one is a mistake.

```bash
bash "<skill-dir>/scripts/create-issue.sh" -- --title "<title>" --body-file <TMPDIR>/body.md --attach "<path>#<alt text>"
```

`gh` uploads the file and rewrites that path in place, so the image lands where the body put it. A path passed without being referenced is appended to the end of the issue instead. Needs `gh` 2.99.0 or newer and does not work on GitHub Enterprise Server: check `gh --version` first, and where either is missing, create the issue with the image reference stripped from the body and report that it could not be uploaded.

**A failed upload does not fail the issue, and this wrapper hides that.** When some attachments upload and others do not, `gh` still creates the issue with the ones that worked, prints its URL to stdout, and exits nonzero. The wrapper reads that nonzero as "create failed", ignores the URL it was handed, finds the issue again by title, and reports `reusing <url>` — so the step succeeds while the published body still carries a local path that resolves to nothing. Confirm every referenced path exists before running the wrapper, and on a `reusing` warning open the issue and check each image rendered before printing the Step 1 report.

**Important:** Replace `<TMPDIR>` with the literal absolute path in all commands (e.g. `--body-file /var/folders/.../issue-flow-AbCdEf/body.md`). Do not set `TMPDIR=` as an env var prefix on commands — that changes the command pattern and triggers permission prompts.

Do not use `--body "$(cat <<'EOF'...)"` — the `$()` command substitution makes the command unmatchable against any pre-approval rule, so hosts that gate shell commands re-prompt every time.

Print the Step 1 report (see `references/report-format.md`). Then stop: an issue exists and no branch does — Step 2 runs only when the intent named it or the user says to continue.

### Sub-Issues (Optional)

If the user mentioned other issue numbers to include in this aggregated issue, add them as sub-issues immediately after the parent is created — before printing the Step 1 report. See **## Sub-Issues** for the procedure.

## Sub-Issues

Use when an aggregated (parent) issue should group related child issues. Needs the **integer** `.id`, not the issue number — they are different things. See `references/github-relationships.md` for ID type details.

### Procedure

Fetch each child's integer ID, then POST it. Use the `<owner>/<repo>` value from `repo-context.sh` — it is the line *after* the `=== Repository ===` header, not the first line of output.

```bash
PARENT=<parent_number>
for num in <child1> <child2> <child3>; do
  id=$(gh api repos/<owner>/<repo>/issues/$num --jq '.id')
  gh api repos/<owner>/<repo>/issues/$PARENT/sub_issues \
    --method POST \
    -F sub_issue_id="$id"
done
```

`-F` (form field) is required — `-f` sends a string, causing `422`. The POST returns the parent issue object — parent title in response means success. Verify:

```bash
gh api repos/<owner>/<repo>/issues/<parent_number>/sub_issues --jq '.[].number'
```

Print one line: `Linked <N> sub-issues to #<parent>`.

When a **newly created** issue is being linked as a child of an existing parent, also follow **## Project Inheritance From Parent** so the child lands on the same project board(s) as the parent.

## Project Inheritance From Parent

When a new issue is being created as a child of an existing parent (sub-issue link, "attach to #N", "linked to #N"), inherit the parent's project membership instead of using the generic Project picker.

Fetch the parent's projects (output: `<id>\t<title>`):

```bash
bash "<skill-dir>/scripts/get-issue-projects.sh" <parent_number>
```

Apply based on count:

- **0** — fall through to the generic Project subsection.
- **1** — add automatically and tell the user which project was inherited.
- **2+** — `AskUserQuestion`:
  1. "Add to all <N> parent projects" (Recommended)
  2. "Pick individually" — follow-up yes/no per project
  3. "Skip projects"

Run `add-to-project.sh <child_number> "<title>"` sequentially per selected project (parallel calls hit Projects V2 rate limits).

When linking many children to the same parent (see **## Batch Issue Creation**), fetch the parent's projects once and reuse the decision for every child — do not prompt per child.

## Blocked-By

Use when child issues have dependencies between them — e.g., issue B cannot start until issue A is done. Requires GraphQL **node IDs** (not issue numbers or integer IDs) — see `references/github-relationships.md`. Use the `<owner>/<repo>` value from `repo-context.sh` — it is the line *after* the `=== Repository ===` header, not the first line of output.

### Procedure

Step 1 — Fetch **node IDs** in one batch query:

```bash
gh api graphql -f query='{
  repository(owner: "<owner>", name: "<repo>") {
    a: issue(number: <blocking-num>) { id }
    b: issue(number: <blocked-num>) { id }
  }
}'
```

Step 2 — Add relationship ("b is blocked by a"):

```bash
gh api graphql -f query='mutation {
  addBlockedBy(input: {
    issueId: "<node-id-of-b>",
    blockingIssueId: "<node-id-of-a>"
  }) { issue { number } blockingIssue { number } }
}'
```

Use `removeBlockedBy` with the same signature to undo. See `references/github-relationships.md` for full details and ID type reference. Print one line per pair: `#<blocked> is now blocked by #<blocking>`.

## Batch Issue Creation

When the user asks to create multiple issues at once (e.g., an epic with child issues, or a set of related issues):

### Workflow

1. Resolve `<TMPDIR>` once via `mktemp -d`
2. Create the parent/epic issue first (if applicable)
3. Write all child issue body files with unique slugs: `<TMPDIR>/<slug>-body.md`
4. Create all child issues in parallel (one create-wrapper call per issue) — apply **### Assignment Defaults** once and reuse the same assignee for every issue in the batch, including the parent. Do not prompt per issue.
5. Batch-link sub-issues to parent (if applicable) — use the for loop from **## Sub-Issues**
6. Add all issues to project sequentially — run `add-to-project.sh` in a for loop, one at a time (parallel calls cause API rate-limit failures and require retries). When children are linked to an **existing** parent, resolve the project set via **## Project Inheritance From Parent** instead of asking generically.
7. Ask about initial project status (e.g., "Backlog", "Current Sprint") via `AskUserQuestion` — then batch-update via `project-status.sh`
8. Print a summary table at the end instead of per-issue Step 1 reports

### Summary Table Format

```
| Issue | Title                   | Milestone   |
| ----- | ----------------------- | ----------- |
| [#10023](https://github.com/owner/repo/issues/10023) | AnchorDialog for Editor | Alpha (MVP) |
| [#10024](https://github.com/owner/repo/issues/10024) | Toolbar refactor        | Alpha (MVP) |
```

Omit the Milestone column if no milestone was assigned to any issue.

## Step 2: Create Branch

Run `detect-base.sh` to find the correct base branch.

If the working tree is dirty (full flow from uncommitted changes):

```bash
git checkout -b issue-<number>
```

Changes carry over to the new branch automatically. Skip checkout and pull — pulling on a dirty tree fails, and you're already on the base.

If the working tree is clean (entered at Step 2 directly, e.g. "start work on #N"):

```bash
git checkout <base> && git pull origin <base>
git checkout -b issue-<number>
```

If `issue-<number>` already exists, use `AskUserQuestion`:
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

No `wip:` subject may survive into the final history.

### Body

Invoke the `commit-summary` skill to generate the commit body. It weighs the change and
either derives a body from the code — what the running code does that forced the change,
which call paths reach it, what breaks on update, when it broke, what was deliberately left
alone — or returns two to three lines for a mechanical or generated change.

If the host cannot invoke another skill, or `commit-summary` is not installed, do the same inline:
derive when the change alters behaviour, a contract, a public type, or a default, or fixes a defect;
otherwise write two or three past-tense lines and stop. To derive, answer in blank-line-separated
paragraphs wrapped at 80, dropping any with no real answer — what the running code does that forces
the change, which call paths reach it, how it failed observably, what breaks on update, what the
tests pin. Cite a hash only if a command returned it in this session.

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

Do not add one either, and **do not copy one forward from the previous commit.** A trailer
already in the log is not licence to repeat it; mirroring the last commit's footer is how one
reproduces itself indefinitely.

A trailer crediting a *human* is fine where the repo's convention asks for one. The only
exception is an explicit request — the repo's instruction file, the user's configuration, or
the user's prompt asking for attribution outright. Finding one in `git log` is not that.

### Consolidate

The branch must end this step at **exactly one commit**, and this section owns the only gate that can decide otherwise.

#### Resolve the fork point

Count and reset must use the **same** ref, and it must be an ancestor of `HEAD`. Resolve it once:

```bash
base=$(bash "<skill-dir>/scripts/detect-base.sh" 2>/dev/null | tail -n1) || base=""
[ -n "$base" ] || { echo "No base branch — add a remote first."; exit 1; }
baseref=$(git rev-parse --verify --quiet "origin/$base" || git rev-parse --verify --quiet "$base")
fork=$(git merge-base "$baseref" HEAD)
git log "$fork"..HEAD --oneline
```

Stop if `base` is empty. `detect-base.sh` exits 2 with no output when the repo has no
remote, and `git merge-base "" HEAD` just errors — there is no base to consolidate against.

**Never reset to `origin/<base>`, and never to a branch name.** `origin/<base>` moves whenever anything fetches, and `detect-base.sh` fetches on its own. Reset to it and the new commit's parent is *newer* than the point the branch was cut from, so the commit silently reverts every upstream change made since — and Step 5 force-pushes that, and Step 6 merges it. `$fork` is an ancestor of `HEAD` by construction, so it cannot have that effect.

#### Choose the action

| Commits ahead of `$fork` | Action |
| ------------------------ | ------ |
| **0** | Nothing to unwind — go to **Execute**. |
| **1**, subject already canonical | Keep the commit. If the tree is dirty (a caller's comment trim or cruft deletion usually leaves it that way), stage the remaining edits and rewrite the message from **Subject** and **Body**: `git commit --amend -m "<subject>" -m "<body>"`. Do **not** use `--amend --no-edit` — it keeps the old message and discards the body this step just generated, including any rationale the caller passed in. |
| **1**, a `wip:` snapshot | `git reset --soft "$fork"`, then **Execute**. |
| **2+**, one shared subject, or any `wip:` among them | `git reset --soft "$fork"`, then **Execute** — one commit with the combined changes. |
| **2+**, genuinely different subjects | Ask before rewriting deliberate history: option 1 `Squash into one commit` `(Recommended)`, option 2 `Keep as-is`. Squash → `git reset --soft "$fork"`, then **Execute**. Keep → skip **Execute** and report the commits as they stand; this is the one outcome that leaves more than one commit. |

A caller that asked for a single commit (`"commit #<N>"` from an orchestrating skill) has already answered that question — squash without prompting.

#### Check the index before committing

`git reset --soft` leaves **the entire difference between `$fork` and the last commit staged** — every file from every commit it unwound, including anything a `wip:` snapshot swept in. Read that as *committed* difference: the reset restores the index to `HEAD`'s content, so it captures nothing you edited after the last commit. Naming files in **Execute** *adds* to that index; it does not narrow it. So after any reset, read the index and remove what must not ship:

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

Push the branch to remote:

```bash
git push -u origin issue-<number>
```

### Rebase if needed

If push fails because the remote has diverged, or if the user asks to rebase — capture the
remote tip **first**, per [Leasing a force-push](#leasing-a-force-push):

```bash
before=$(git rev-parse "origin/issue-<number>" 2>/dev/null || true)
git fetch origin <base>
git rebase origin/<base>
if [ -n "$before" ]; then
  git push --force-with-lease="issue-<number>:$before"
else
  git push -u origin issue-<number>
fi
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

Then check the branch really is at one commit — `git log --oneline <base>..HEAD`. Amending
only rewrites the tip, so a branch carrying `wip:` snapshots needs Step 3 → Consolidate
first; amending it would push the snapshots along with the fix.

```bash
before=$(git rev-parse "origin/issue-<number>" 2>/dev/null || true)
git commit --amend -m "<subject>" -m "<body>"
if [ -n "$before" ]; then
  git push --force-with-lease="issue-<number>:$before"
else
  git push -u origin issue-<number>
fi
```

Always pass the message. A bare `git commit --amend` opens `$EDITOR`, which hangs a
non-interactive shell. Use `--no-edit` only when the existing message is being kept
verbatim and nothing new needs to land in it — which is the case when the amend only
folds in fixes and the subject and body still describe them.

Print the `Pushed (amended)` report.

### Leasing a force-push

Every force-push in this pipeline pins the SHA it expects the remote to be at, captured
**before** anything fetches:

```bash
before=$(git rev-parse "origin/issue-<number>" 2>/dev/null || true)
# ... rebase, amend, or consolidate ...
git push --force-with-lease="issue-<number>:$before"
```

`rev-parse` is guarded because the branch may not be on the remote yet, and a bare
`git rev-parse origin/issue-<number>` exits 128 with `unknown revision` — which under
`set -e` aborts the step instead of pushing. An empty `$before` means there is nothing to
lease against, so that case is a plain `git push -u origin issue-<number>`.

A bare `git push --force-with-lease` leases against `refs/remotes/origin/issue-<number>`.
Any fetch that refreshes that ref makes the lease describe where the remote is *now*
rather than where it was when you started — at which point it permits exactly the
overwrite it exists to prevent. `detect-base.sh` runs a bare `git fetch origin`, which
refreshes every branch, inside Step 3 → Consolidate; and nothing stops an unrelated fetch
landing between the rewrite and the push. Reading the SHA before any of that is what makes
the lease mean anything.

`--force-if-includes` (git 2.30+) is not a substitute here. `git help push` is explicit
that when it is combined with `--force-with-lease=<refname>:<expect>` it is a **no-op** —
so alongside the pinned form above it does literally nothing. It is the right tool for the
*valueless* `--force-with-lease`, since it consults the local reflog rather than the
remote-tracking ref; but it needs git 2.30+, it fails oddly after a `gc` or in a fresh
clone where the reflog is thin, and it would diverge from the pinned idiom used
everywhere else in this file. Pin the SHA instead.

If the push is rejected, the remote moved: fetch, rebase onto the new tip, and re-run
rather than escalating to `--force`.

Print the Step 4 report. Then stop: do not create a PR — Step 5 runs only when the intent named it or the user says to continue.

## Step 5: Create PR

Run `detect-base.sh` to determine the PR base.

### Pre-PR: Squash Commits

Apply **Step 3 → Consolidate** as-is. It owns the fork point, the count, the squash rules, and the one gate that may leave several commits — including the case where the single commit on the branch is a `wip:` snapshot, which must not reach a PR title. Do not restate any of those rules here; a second copy is how the two drift.

The only thing this step adds is that the branch is already on the remote, so the rewrite has to be force-pushed. Capture the remote tip **before** consolidating and lease against it explicitly, per [Leasing a force-push](#leasing-a-force-push):

```bash
before=$(git rev-parse "origin/issue-<number>")
# ... apply Step 3 -> Consolidate ...
git push --force-with-lease="issue-<number>:$before"
```

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

Follow **### Assignment Defaults**. Reviewer selection is separate from assignment — see **### Assignees** below.

In a `KIND=personal` repo, skip the reviewer prompt entirely unless the repo's CLAUDE.md sets a reviewer rule or the user asked for one — a solo repo has no one else to review, and the reviewer question is the step where assignment silently gets dropped.

Check the target repo's CLAUDE.md for reviewer rules (e.g., "PRs to main should be reviewed by @username", default reviewer for specific branches). If a matching rule exists, use that reviewer directly.

Otherwise, run `pr-reviewers.sh` to find users with actual recent PR review activity:

```bash
bash "<skill-dir>/scripts/pr-reviewers.sh"
```

Output: `<user>\t<count>` per row, up to 3 rows (excludes self and bots; counts both reviews submitted and review-requests received across the last 100 PRs in any state).

- **0 results**: skip the prompt entirely and create the PR without `--reviewer`. Do **not** fall back to the generic `repo-context.sh` collaborator list — repo members with zero review history are not real reviewer candidates, and inventing labels like "Frequent collaborator" misleads the user.
- **1+ results**: compose `AskUserQuestion`:
  1. First result (Recommended), description: `"<count> review events across the last 100 PRs"`
  2. Second result (if any), description: `"<count> review events across the last 100 PRs"`
  3. "No reviewer"

Check if the selected reviewer is the same as the PR creator:

```bash
gh api user --jq .login
```

If same, skip `--reviewer` flag (GitHub doesn't allow self-review).

### Assignees

The PR creator (`@me`, i.e. the current user) is **always** an assignee — in personal and org repos alike, with or without a reviewer. Setting a reviewer never replaces the creator on Assignees; it adds to it.

- **Reviewer set** (and not the creator): assign `@me` **and** the reviewer.
  - e.g. creator `alice` sets `octocat` as reviewer → Reviewers: `octocat`, Assignees: `octocat`, `alice`.
- **No reviewer** (or reviewer is the creator / self-review): assign only `@me`.

There is no branch of this step that produces zero assignees. If a reviewer prompt is skipped or `pr-reviewers.sh` returns nothing, `@me` still goes on `--assignee`.

### Create

Write the PR body to `<TMPDIR>/pr-body.md` with the host's file-write tool, then create the PR with `--body-file`. Replace `<TMPDIR>` with the literal absolute path — do not use `TMPDIR=` as an env var prefix.

With a reviewer (pass `--assignee` once per assignee):

```bash
gh pr create --title "<title>" --body-file <TMPDIR>/pr-body.md --base <base> --assignee @me --assignee <reviewer> --reviewer <reviewer>
```

Without a reviewer (or self-review):

```bash
gh pr create --title "<title>" --body-file <TMPDIR>/pr-body.md --base <base> --assignee @me
```

Do not use `--body "$(cat <<'EOF'...)"` — the `$()` command substitution makes the command unmatchable against any pre-approval rule, so hosts that gate shell commands re-prompt every time.

No media goes in a PR body, even though `gh pr create` accepts `--attach`. A PR body is read at merge time and again in release notes, where a screenshot of the old behaviour is describing something that no longer exists. The before-state belongs on the issue; an after-state, if it is worth showing at all, belongs in a comment on the PR.

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
| `CONFLICTING` | Rebase onto base (`git fetch origin && git rebase origin/<base>`), force-push, re-run the poll. If conflicts are not mechanical, invoke the `resolve-conflicts` skill; if still unresolved, report `Mergeable: no — conflicts with <base>` and **stop before Step 6**. |
| `UNKNOWN` after 3 polls | Report `Mergeable: unknown (GitHub still computing)`. Do not treat as failure. |

`mergeStateStatus` adds context worth reporting when it is not `CLEAN`:
- `BEHIND` — base moved ahead; rebase and force-push.
- `BLOCKED` — branch protection or a required review is pending. Not a conflict; report it as-is.
- `UNSTABLE` — checks are failing or still running.

Do **not** run `gh pr checks --watch` here. Check monitoring belongs to Step 6; a PR-only flow reports the mergeability state and ends.

Print the Step 5 report, including the `Mergeable:` line. Then stop: Step 6 runs only on the entry conditions in **### Entering Step 6 at all**, and reaching Step 5 is not one of them.

## Step 6: Merge PR

### Skip Condition

Determine the current user: `gh api user --jq .login`. If the PR reviewer OR assignee is someone **other than** the current user, **skip Step 6**:

```
PR #<number> is ready for review by @<reviewer> (mergeable: <state from Step 5>). Merge skipped — awaiting external review.
```

If reviewer AND assignee are the current user (self-review), or user explicitly asked to merge, proceed below.

### Entering Step 6 at all

**Step 6 runs only when merging was asked for.** Reaching Step 5 is not an invitation to
merge — a caller whose intent was `"push and open PR for #<N>"` wants the flow to end at
Step 5, and suggesting a merge there overrides a choice the user already made.

Step 6 is entered on exactly three things: an intent naming the merge
(`"merge #<N>"`, `"push, PR, and merge #<N>"`), the user answering the suggestion below,
or the user asking to merge in conversation. Otherwise stop after Step 5.

### Confirm exactly once

The merge is confirmed **once per flow**, and this section decides where that happens.
Classify the entry, then take one branch and skip the other.

| Entry | Confirmation |
| ----- | ------------ |
| **The intent already names the merge** — `"push, PR, and merge #<N>"`, `"merge #<N>"` from an orchestrating skill that already put the question to the user | Already confirmed. Print the pre-merge summary for the record and go straight to **Pre-checks**. Asking again is the duplicate prompt callers are told not to create. |
| **A full flow that entered at Step 1 and was never told what to do about merging** | Not yet confirmed. Print the pre-merge summary and suggest merging (below). |
| **Direct entry at Step 6 by the user**, no earlier step in this flow | Not yet confirmed. Merging closes the PR and writes to the base branch. Print the pre-merge summary, show the PR number, the base branch, and the merge method, and wait for approval before merging. |

When confirmation is still needed, ask via `AskUserQuestion`:
1. "Merge now" (Recommended) — wait for checks and merge
2. "Skip" — leave PR open, end flow

"Skip" → print the skip message and stop. "Merge now" → continue to **Pre-checks**.

Either way the pre-merge summary is printed (see `references/report-format.md`) — it is
the record of what is about to be merged, not the prompt itself.

The suggestion branch additionally requires all of:
- Issue assignee is the current user
- PR assignee is the current user
- No external reviewer was set on the PR

If any of those is false, the **Skip Condition** above already applies and Step 6 ends.

### Pre-checks

1. Check PR state:

```bash
gh pr view <pr-number> --json state,mergeable
```

- If PR is not open: report current state and **stop**.
- If there are conflicts: rebase onto base, force-push, then continue to step 2.

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
- Exit 124 (timeout) → report timeout, ask user via `AskUserQuestion`:
  1. "Merge anyway" — proceed to step 3; the merged report carries `Checks: not confirmed (watch timed out)`
  2. "Wait longer" — re-run the same timeout command
  3. "Abort" — stop
- Exit 127 (`gtimeout` missing) → report the missing timeout binary and **stop**.

3. After checks pass, verify mergeability one more time:

```bash
gh pr view <pr-number> --json mergeable --jq '.mergeable'
```

If conflicts appeared, rebase and re-run checks.

### Merge

```bash
gh pr merge --rebase --delete-branch
```

`Closes #<number>` in the PR body auto-closes the issue when merging into the default branch. Only verify and manually close if the merge target is a non-default branch (e.g., epic-* or next):

```bash
# Only run this if base branch is NOT the default branch
gh issue close <number>
```

Update project status to "Done":

```bash
bash "<skill-dir>/scripts/project-status.sh" <number> "Done"
```

Print the Step 6 merged report.

## Error Handling

- **Projects V2 fails**: Warn once, then skip all project operations for the rest of the flow — the core lifecycle works without them. Carry `Project: skipped (Projects V2 unavailable)` on every later step report that would have updated the board. Token setup is in `references/project-integration.md`.
- **Assignment rejected** (`gh` reports the assignee is not a valid collaborator): report which assignee was dropped, then continue. Do not abort the flow or retry with a different user.
- **gh not authenticated**: Stop immediately, tell user to run `gh auth login`.
- **No remote**: `detect-base.sh` exits 2 and there is no base branch. Steps 2, 3, 5, and 6 all depend on it, so stop at whichever of them was entered and tell the user to add a remote. Do not fall back to `main`.
