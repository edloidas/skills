---
name: issue-flow
description: >
  Full GitHub issue lifecycle: create issue, branch, commit, push, PR, merge.
  Handles project board integration, base branch detection (main/master/epic-*),
  and compact step reports. Use when asked to create issues, start work on issues,
  create PRs, push changes, or merge PRs. Supports entering at any step.
license: MIT
compatibility: Claude Code
model: claude-sonnet-4-6
allowed-tools: Bash(gh:*) Bash(git:*) Bash(bash:*) Read Glob Grep AskUserQuestion
arguments: "issue-number description"
argument-hint: "[issue-number or description]"
metadata:
  author: edloidas
---

# Issue Flow

Manages the full GitHub issue lifecycle: issue → branch → commits → PR → merge → close. Supports entering at any step and advancing forward. Reads the target repo's CLAUDE.md for project-specific conventions.

## Bundled Scripts

Located in `scripts/` relative to this skill:

| Script                     | Purpose                                         |
| -------------------------- | ----------------------------------------------- |
| `check-env.sh`             | Validate git repo, gh CLI, authentication       |
| `detect-base.sh`           | Detect base branch (main/master/epic-*)         |
| `repo-context.sh`          | Fetch labels, collaborators, projects           |
| `resolve-project-token.sh` | Resolve token: GH_PROJECTS_TOKEN → gh auth      |
| `add-to-project.sh`        | Add issue to GitHub Projects V2                 |
| `project-status.sh`        | Update project board status                     |
| `wait-checks.sh`          | Poll PR check status until complete or timeout   |

Run scripts from the skill directory:

```bash
bash "<skill-dir>/scripts/check-env.sh"
bash "<skill-dir>/scripts/detect-base.sh"
bash "<skill-dir>/scripts/repo-context.sh"
bash "<skill-dir>/scripts/add-to-project.sh" <issue-number> <project-title> [status]
bash "<skill-dir>/scripts/project-status.sh" <issue-number> <status>
bash "<skill-dir>/scripts/wait-checks.sh" <pr-number> [timeout-seconds]
```

## Step Router

Determine entry step from user intent, check prerequisites, then proceed forward. Do NOT re-run earlier completed steps.

| User intent                          | Entry step | Prerequisite             |
| ------------------------------------ | ---------- | ------------------------ |
| No arguments / empty invocation      | Step 1     | Staged or changed files  |
| "create issue", "new issue"          | Step 1     | gh authenticated         |
| "add sub-issues to #N", "link issues to #N" | Sub-issues | Parent issue exists |
| "X blocks #N", "block #N with #M", "unblock #N" | Blocked-by | Both issues exist |
| "start work on #N", "branch for #N"  | Step 2     | Issue exists             |
| "commit", "commit changes"           | Step 3     | On issue-* branch        |
| "push", "push changes"               | Step 4     | Commits ahead of remote  |
| "create PR", "open PR"               | Step 5     | Branch pushed            |
| "merge", "merge PR"                  | Step 6     | PR exists                |

### No Arguments (Full Flow from Changes)

When invoked without arguments, assume a full flow based on current working tree changes:

1. Check for staged files: `git diff --cached --name-only`
2. If no staged files, check for all changed/untracked files: `git diff --name-only` and `git ls-files --others --exclude-standard`
3. If no changes found at all, stop and tell the user there's nothing to commit
4. Analyze the changes (diff content) to infer issue type and description
5. Run the full flow (Steps 1–6) using the detected files — stage only the identified files in Step 3

When the user says "full flow" or asks to go from issue to merge, run all steps sequentially. Otherwise, start at the detected step and ask whether to continue to the next step after each one completes.

## Conventions

Read the target repo's CLAUDE.md for project-specific formatting. Use these defaults when no override is found:

- **Issue titles**: `<type>: <description>` (conventional commit format)
- **Commit subjects**: `<Issue Title> #<number>`
- **PR titles**: `<Issue Title> #<number>`
- **PR body**: concise change list + `Closes #<number>` + `<sub>*Drafted with AI assistance*</sub>`

Common types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `style`, `ci`

## Step 1: Create Issue

Run `check-env.sh` to validate environment. Run `repo-context.sh` to fetch labels, collaborators, and projects.

### Title

Use conventional commit format: `<type>: <description>`. Defer to CLAUDE.md conventions if they differ.

### Epic Detection

Before writing the body or picking a label, determine if this is an **epic issue** — one that coordinates work without containing implementation itself. Signals:

- User mentions "epic", "umbrella", "tracking issue", or "aggregated issue"
- Issue groups multiple child issues or feature areas
- No concrete implementation details — only scope or coordination

If it is an epic, and the repo has an `epic` label (check `repo-context.sh` output), apply `epic` as the label without asking. Skip the normal type-based label inference. If `epic` label does not exist in the repo, fall through to normal label selection.

### Body

Write a brief 2-4 sentence description. No markdown headers. Add the AI footer at the very bottom:

```
<sub>*Drafted with AI assistance*</sub>
```

For epic issues: **do NOT list child issue numbers in the body.** Sub-issue relationships are managed via the GitHub sub-issues API (see **## Sub-Issues**), not via body text.

### Labels

Auto-detect label from the issue type (e.g., `feat` → `feature` or `enhancement`). Match against labels fetched by `repo-context.sh`. Use `AskUserQuestion` to confirm with the user — show top 3 matching labels + "No label".

### Assignee

Use `AskUserQuestion` with options:
1. `@me` (Recommended)
2. Up to 2 collaborators from `repo-context.sh`
3. "No assignee"

### Type

Check if the repository supports issue types: `gh issue create --type bug --dry-run 2>&1`. If types are supported, map the conventional commit type to an issue type. If not supported, skip silently.

### Project

If `repo-context.sh` found projects, use `AskUserQuestion` to ask which project (if any). If no projects found, skip silently. On selection, run `add-to-project.sh`.

### Milestone

Check the target repo's CLAUDE.md for milestone configuration:

- If CLAUDE.md specifies a milestone name → use it directly with `--milestone "<name>"`
- If CLAUDE.md says milestones should be used but no specific name → fetch active milestones via `gh api repos/<owner>/<repo>/milestones?state=open --jq '.[].title'` (`<owner>/<repo>` from `repo-context.sh` first line), then `AskUserQuestion` to pick one
- If CLAUDE.md says nothing about milestones → skip silently

### Create

```bash
gh issue create --title "<title>" --body "<body>" --label "<label>" --assignee "<assignee>" [--milestone "<name>"]
```

Print the Step 1 report (see `references/report-format.md`).

### Sub-Issues (Optional)

If the user mentioned other issue numbers to include in this aggregated issue, add them as sub-issues immediately after the parent is created — before printing the Step 1 report. See **## Sub-Issues** for the procedure.

## Sub-Issues

Use when an aggregated (parent) issue should group related child issues. Needs the **integer** `.id`, not the issue number — they are different things. See `references/github-relationships.md` for ID type details.

### Procedure

Fetch each child's integer ID, then POST it. Use `<owner>/<repo>` from `repo-context.sh` first line.

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

## Blocked-By

Use when child issues have dependencies between them — e.g., issue B cannot start until issue A is done. Requires GraphQL **node IDs** (not issue numbers or integer IDs) — see `references/github-relationships.md`. Use `<owner>/<repo>` from `repo-context.sh` first line.

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

Use `removeBlockedBy` with the same signature to undo. See `references/github-relationships.md` for full details and ID type reference.

## Step 2: Create Branch

Run `detect-base.sh` to find the correct base branch.

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

Print the Step 2 report.

## Step 3: Commit

### Subject

Use `<Issue Title> #<number>` as the commit subject. The issue title is already in conventional commit format from Step 1.

If there is no linked issue (e.g., entered at Step 3 directly), use the repo's CLAUDE.md commit format or fall back to `<type>: <description>`.

### Body

Invoke `/commit-summary` via the Skill tool to generate the commit body. If `/commit-summary` is not available, generate inline: past-tense summary, one line per logical change, 2-6 lines, backticks for code references.

### Execute

Stage relevant files (prefer specific files over `git add -A`), then commit:

```bash
git add <files>
git commit -m "<subject>" -m "<body>"
```

Print the Step 3 report.

## Step 4: Push

Push the branch to remote:

```bash
git push -u origin issue-<number>
```

### Rebase if needed

If push fails because the remote has diverged, or if the user asks to rebase:

```bash
git fetch origin <base>
git rebase origin/<base>
git push --force-with-lease
```

### Amend

If the user asks to amend the last commit:

```bash
git commit --amend
git push --force-with-lease
```

Print the Step 4 report.

## Step 5: Create PR

Run `detect-base.sh` to determine the PR base.

### Pre-PR: Squash Commits

Check commit history: `git log <base>..HEAD --oneline`.

- **Single commit**: No action needed.
- **Multiple commits, same subject**: Squash silently — `git reset --soft <base>` → `git commit` with merged body → `git push --force-with-lease`.
- **Multiple commits, different subjects**: `AskUserQuestion` with options:
  1. "Squash all into one commit" — after squash: `git reset --soft <base>` → `git commit` with user message → `git push --force-with-lease`
  2. "Keep as-is" (Recommended)

This must happen before PR body generation since squashing changes the commit log.

### Title and Body

- **Title**: `<Issue Title> #<number>`
- **Body**: Generate from `git log <base>..HEAD --oneline`, add `Closes #<number>`, add AI footer

```markdown
## Changes

- <change 1>
- <change 2>

Closes #<number>

<sub>*Drafted with AI assistance*</sub>
```

### Assignee and Reviewer

Check the target repo's CLAUDE.md for reviewer rules (e.g., "PRs to main should be reviewed by @username", default reviewer for specific branches). If a matching rule exists, use that reviewer directly. If no rules found, fall back to `AskUserQuestion`:

1. Up to 2 collaborators from `repo-context.sh`
2. "No reviewer"

Check if the selected reviewer is the same as the PR creator:

```bash
gh api user --jq .login
```

If same, skip `--reviewer` flag (GitHub doesn't allow self-review).

### Create

```bash
gh pr create --title "<title>" --body "<body>" --base <base> --assignee @me --reviewer <reviewer>
```

Update project status to "Review":

```bash
bash "<skill-dir>/scripts/project-status.sh" <number> "Review"
```

Print the Step 5 report.

## Step 6: Merge PR

### Skip Condition

Determine the current user: `gh api user --jq .login`. If the PR reviewer OR assignee is someone **other than** the current user, **skip Step 6**:

```
PR #<number> is ready for review by @<reviewer>. Merge skipped — awaiting external review.
```

If reviewer AND assignee are the current user (self-review), or user explicitly asked to merge, proceed below.

### Suggest Merge (Full Flow)

When **all** of these are true:
- Full flow was performed (entered at Step 1 and ran through Step 5)
- Issue assignee is the current user
- PR assignee is the current user
- No external reviewer was set on the PR

Then suggest merging via `AskUserQuestion`:
1. "Merge now" (Recommended) — wait for checks and merge
2. "Skip" — leave PR open, end flow

If user picks "Skip", print the skip message and stop. If "Merge now", continue to Pre-checks below. Mark that the user has **already confirmed** merge intent (skip the pre-merge confirmation later).

### Pre-merge Confirmation (Direct Entry Only)

When the user entered **directly at Step 6** (not via the full-flow suggestion above), **MUST stop and confirm before merging.** Show the user:
- Target branch and commit count
- Linked issue that will be closed
- CI check status

Print the Step 6 pre-merge report and wait for confirmation.

### Pre-checks

1. Check PR state:

```bash
gh pr view <pr-number> --json state,mergeable
```

- If PR is not open: report current state and **stop**.
- If there are conflicts: rebase onto base, force-push, then continue to step 2.

2. Wait for CI checks:

```bash
bash "<skill-dir>/scripts/wait-checks.sh" <pr-number> 300
```

- Exit 0 (all passed/skipped) → proceed to step 3
- Exit 1 (failure) → report failed checks, **stop**. Do not merge.
- Exit 2 (timeout) → report timeout, ask user via `AskUserQuestion`:
  1. "Merge anyway" — proceed to step 3
  2. "Wait longer" — re-run `wait-checks.sh` with another 300s
  3. "Abort" — stop

Print the "Waiting for Checks" report while polling (see `references/report-format.md`).

3. After checks pass, verify mergeability one more time:

```bash
gh pr view <pr-number> --json mergeable --jq '.mergeable'
```

If conflicts appeared, rebase and re-run checks.

### Merge

```bash
gh pr merge --rebase --delete-branch
```

Close the issue if not auto-closed by `Closes #<number>`:

```bash
gh issue close <number>
```

Update project status to "Done":

```bash
bash "<skill-dir>/scripts/project-status.sh" <number> "Done"
```

Print the Step 6 merged report.

## Error Handling

- **Projects V2 fails**: Warn once, then skip all project operations for the rest of the flow. The core lifecycle works without project integration.
- **gh not authenticated**: Stop immediately, tell user to run `gh auth login`.
- **Branch already exists**: Ask user via `AskUserQuestion` (switch vs. recreate).
- **CI checks failing**: Report failed checks, do not attempt merge.
- **No CLAUDE.md**: Use the default conventions listed above.
- **No remote**: Stop at push step, tell user to add a remote.

## Integration

- For commit message body → invoke `/commit-summary` via Skill tool; fall back to inline if unavailable
- For project token setup → see `references/project-integration.md`
- For report templates → see `references/report-format.md`
- For sub-issues and blocked-by relationships → see `references/github-relationships.md`
