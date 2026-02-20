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
arguments: "issue number, step name, or description for new issue"
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

Run scripts from the skill directory:

```bash
bash "<skill-dir>/scripts/check-env.sh"
bash "<skill-dir>/scripts/detect-base.sh"
bash "<skill-dir>/scripts/repo-context.sh"
bash "<skill-dir>/scripts/add-to-project.sh" <issue-number> <project-title> [status]
bash "<skill-dir>/scripts/project-status.sh" <issue-number> <status>
```

## Step Router

Determine entry step from user intent, check prerequisites, then proceed forward. Do NOT re-run earlier completed steps.

| User intent                          | Entry step | Prerequisite             |
| ------------------------------------ | ---------- | ------------------------ |
| "create issue", "new issue"          | Step 1     | gh authenticated         |
| "start work on #N", "branch for #N"  | Step 2     | Issue exists             |
| "commit", "commit changes"           | Step 3     | On issue-* branch        |
| "push", "push changes"               | Step 4     | Commits ahead of remote  |
| "create PR", "open PR"               | Step 5     | Branch pushed            |
| "merge", "merge PR"                  | Step 6     | PR exists                |

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

### Body

Write a brief 2-4 sentence description. No markdown headers. Add the AI footer at the very bottom:

```
<sub>*Drafted with AI assistance*</sub>
```

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

If reviewer AND assignee are the current user (self-review), or user explicitly asked to merge, proceed with merge confirmation below.

**CRITICAL: MUST stop and confirm before merging.** Show the user:
- Target branch and commit count
- Linked issue that will be closed
- CI check status

Print the Step 6 pre-merge report and wait for confirmation.

### Pre-checks

```bash
gh pr view --json state,mergeable,statusCheckRollup
```

- If checks are failing: report which checks failed and **stop**. Do not merge.
- If there are conflicts: rebase onto base, force-push, wait for checks, ask again.
- If PR is not open: report current state and stop.

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
