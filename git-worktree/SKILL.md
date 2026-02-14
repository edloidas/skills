---
name: git-worktree
description: >
  Manage Git worktrees — create, remove, list, and clean worktrees stored in
  a configurable location (default ~/.worktrees/<repo>/<branch>). Copies agent
  settings (.claude/, .codex/, .agents/) to new worktrees so permissions carry
  over. Use when the user asks to create a worktree, work on multiple branches,
  or clean up worktrees.
license: MIT
allowed-tools: Bash Read Glob Grep
arguments: "subcommand: create, remove, list, or clean, followed by branch name"
argument-hint: "[command] [branch]"
---

# Git Worktree Manager

Manage Git worktrees for the current repository with a centralized, configurable storage location.

## When to Use This Skill

Use when the user asks to:
- Create a worktree for a branch
- Work on multiple branches simultaneously
- Remove or clean up worktrees
- List existing worktrees
- Set up a worktree for PR review or parallel development

Trigger phrases: "create worktree", "add worktree", "remove worktree", "list worktrees", "clean worktrees", "worktree for branch"

## Configuration

| Setting | Env Var | Default |
|---------|---------|---------|
| Storage root | `GIT_WORKTREES_DIR` | `~/.worktrees` |

Worktree path: `$GIT_WORKTREES_DIR/<repo-name>/<sanitized-branch>`

Branch names are sanitized: `/` → `-` (e.g. `feature/new-ui` → `feature-new-ui`).

## Important: Working Directory

Claude Code **cannot change its own working directory** during a session. After creating a worktree, show the user a ready-to-copy command:

```
cd ~/.worktrees/repo/branch && claude
```

The user must open a new terminal or Claude Code session to work in the worktree.

## Bundled Scripts

All scripts live in the `scripts/` directory. Execute them from the skill directory:

```bash
bash scripts/create.sh --branch <branch>
bash scripts/remove.sh --branch <branch>
bash scripts/list.sh
bash scripts/clean.sh
```

### scripts/create.sh

Creates a worktree, fetches remotes, and copies agent settings.

**Usage:**
```
create.sh --branch <branch>
create.sh --new-branch <branch> --start-point <ref>
```

**Flags:**
| Flag | Description |
|------|-------------|
| `--branch <branch>` | Checkout existing branch |
| `--new-branch <branch>` | Create new branch |
| `--start-point <ref>` | Base ref for new branch (required with `--new-branch`) |
| `--no-fetch` | Skip `git fetch --all` |
| `--no-copy-settings` | Skip agent settings copying |

**Behavior:**
- Fetches all remotes before creating (unless `--no-fetch`)
- Copies `.claude/`, `.codex/`, `.agents/` from source repo (if they exist) so permissions carry over
- `CLAUDE.md` arrives via git checkout automatically
- Outputs a `cd ... && claude` command for the user

**Exit codes:** 0=success, 1=not git repo, 2=bad args, 3=branch not found, 4=already exists, 5=git error

### scripts/remove.sh

Removes a worktree in a single pass — no double-deletion.

**Usage:**
```
remove.sh --branch <branch>
remove.sh --path <path>
```

**Flags:**
| Flag | Description |
|------|-------------|
| `--branch <branch>` | Remove by branch name (resolves path automatically) |
| `--path <path>` | Remove by explicit path |
| `--force` | Force remove with uncommitted changes |

**Behavior:**
- Single `git worktree remove` call (handles git unlinking and directory deletion)
- Runs `git worktree prune` after removal
- Cleans empty parent directories

**Exit codes:** 0=success, 1=not git repo, 2=bad args, 3=not found, 4=has uncommitted changes

### scripts/list.sh

Lists worktrees for the current repository.

**Usage:**
```
list.sh [--all]
```

**Flags:**
| Flag | Description |
|------|-------------|
| `--all` | Include main repo working directory |

**Behavior:**
- Default: shows only worktrees under the storage directory
- Formatted output: path, commit hash, branch
- Shows total count

### scripts/clean.sh

Removes all worktrees for the current repository.

**Usage:**
```
clean.sh              # dry-run (default)
clean.sh --apply      # actually remove
clean.sh --force      # force remove (implies --apply)
```

**Behavior:**
- Prunes stale references first
- Default is dry-run — shows what would be removed
- `--apply` performs actual removal
- Cleans empty directories after removal

> **Always run dry-run first**, show results to the user, and ask for confirmation before running `--apply`.

## Commands

| Command | Script Call |
|---------|------------|
| `/git-worktree create <branch>` | `create.sh --branch <branch>` |
| `/git-worktree create -b <new-branch> <start-point>` | `create.sh --new-branch <branch> --start-point <ref>` |
| `/git-worktree remove <branch>` | `remove.sh --branch <branch>` |
| `/git-worktree list` | `list.sh` |
| `/git-worktree clean` | `clean.sh` (then `clean.sh --apply` after confirmation) |

## Workflow

### Creating a Worktree

1. Run `create.sh` with the appropriate flags
2. Show the user the output path and the `cd ... && claude` command
3. Remind them to open a new terminal or session

### Removing a Worktree

1. Run `remove.sh` with `--branch` or `--path`
2. If it fails with exit code 4 (uncommitted changes), ask the user if they want to `--force`

### Cleaning All Worktrees

1. Run `clean.sh` (dry-run) and show results
2. Ask user for confirmation
3. Run `clean.sh --apply` (or `--force` if needed)

## Error Handling

| Error | Solution |
|-------|----------|
| Not in a git repository | Inform user to navigate to a git repository first |
| Branch doesn't exist | Suggest `git fetch --all` or use `--new-branch` to create |
| Worktree already exists | Show existing path, ask if user wants to navigate there |
| Uncommitted changes on remove | Ask user if they want to force remove |

## Examples

### Create worktree for feature branch
```
User: Create a worktree for the feature/new-ui branch

[Runs: bash scripts/create.sh --branch feature/new-ui]

Worktree created at: ~/.worktrees/my-repo/feature-new-ui
To start working:
  cd ~/.worktrees/my-repo/feature-new-ui && claude
```

### Create worktree with new branch
```
User: Create a worktree with a new branch fix/bug-123 from main

[Runs: bash scripts/create.sh --new-branch fix/bug-123 --start-point main]

Worktree created at: ~/.worktrees/my-repo/fix-bug-123
Branch fix/bug-123 created from main
To start working:
  cd ~/.worktrees/my-repo/fix-bug-123 && claude
```

### Remove a worktree
```
User: Remove the worktree for feature/old-feature

[Runs: bash scripts/remove.sh --branch feature/old-feature]

Worktree removed successfully.
```

### List worktrees
```
User: List all worktrees

[Runs: bash scripts/list.sh]

~/.worktrees/my-repo/feature-new-ui  def5678  [feature/new-ui]
~/.worktrees/my-repo/fix-bug-123     ghi9012  [fix/bug-123]

Total: 2 worktree(s)
```

## Keywords

git, worktree, branch, parallel development, multiple branches, workspace, checkout
