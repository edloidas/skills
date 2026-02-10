---
name: git-worktree
description: Manage Git worktrees - create, remove, list, and clean worktrees stored in ~/worktrees/<repo>/<branch>
license: MIT
compatibility: Claude Code
allowed-tools: Bash, Read, Glob, Grep
---

# Git Worktree Manager

Manage Git worktrees for the current repository with a consistent storage location.

## Purpose

This skill provides commands to manage Git worktrees, storing them in a centralized location (`~/worktrees/<repo-name>/<branch-name>`) for easy navigation and cleanup.

## When to Use This Skill

Use this skill when the user asks to:
- Create a worktree for a branch
- Work on multiple branches simultaneously
- Remove or clean up worktrees
- List existing worktrees
- Set up a worktree for PR review or parallel development

Trigger phrases: "create worktree", "add worktree", "remove worktree", "list worktrees", "clean worktrees", "worktree for branch"

## Commands

| Command | Description |
|---------|-------------|
| `/git-worktree create <branch>` | Create worktree for existing branch |
| `/git-worktree create -b <new-branch> <start-point>` | Create worktree with new branch |
| `/git-worktree remove <branch>` | Remove worktree by branch name |
| `/git-worktree list` | List all worktrees for current repo |
| `/git-worktree clean` | Remove all worktrees for current repo |

## Configuration

- **Storage Location**: `~/worktrees/<repo-name>/<branch-name>`
- **Auto-fetch**: Always fetches before creating worktree

## Workflow

### Path Computation

For all operations, compute paths as follows:

```bash
# Get repository name
REPO_ROOT=$(git rev-parse --show-toplevel)
REPO_NAME=$(basename "$REPO_ROOT")

# Compute worktree paths
WORKTREE_BASE="$HOME/worktrees/$REPO_NAME"
WORKTREE_PATH="$WORKTREE_BASE/<branch-name>"
```

### Create Worktree

1. **Verify git repository**
   ```bash
   git rev-parse --show-toplevel
   ```
   If this fails, inform user they must be in a git repository.

2. **Get repository name**
   ```bash
   REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
   ```

3. **Fetch all remotes** (ensures branch is available)
   ```bash
   git fetch --all
   ```

4. **Create base directory**
   ```bash
   mkdir -p ~/worktrees/$REPO_NAME
   ```

5. **Create worktree**

   For existing branch:
   ```bash
   git worktree add ~/worktrees/$REPO_NAME/<branch> <branch>
   ```

   For new branch from start point:
   ```bash
   git worktree add -b <new-branch> ~/worktrees/$REPO_NAME/<new-branch> <start-point>
   ```

6. **Report success**
   Tell user the worktree path and how to navigate to it:
   ```
   Worktree created at: ~/worktrees/<repo>/<branch>
   cd ~/worktrees/<repo>/<branch>
   ```

### Remove Worktree

1. **Verify git repository**

2. **Get repository name**

3. **Compute worktree path**
   ```bash
   WORKTREE_PATH="$HOME/worktrees/$REPO_NAME/<branch>"
   ```

4. **Check if worktree exists**
   ```bash
   git worktree list | grep "$WORKTREE_PATH"
   ```

5. **Remove worktree**
   ```bash
   git worktree remove ~/worktrees/$REPO_NAME/<branch>
   ```

   If there are uncommitted changes, ask user if they want to force:
   ```bash
   git worktree remove --force ~/worktrees/$REPO_NAME/<branch>
   ```

6. **Clean up empty directory** (if no worktrees remain)
   ```bash
   # Check if directory is empty
   if [ -z "$(ls -A ~/worktrees/$REPO_NAME 2>/dev/null)" ]; then
     rmdir ~/worktrees/$REPO_NAME
   fi
   ```

### List Worktrees

1. **Verify git repository**

2. **List all worktrees**
   ```bash
   git worktree list
   ```

3. **Format output** showing:
   - Path
   - Branch name
   - Commit hash

### Clean All Worktrees

1. **Verify git repository**

2. **Get repository name**

3. **Prune stale worktree references**
   ```bash
   git worktree prune
   ```

4. **List worktrees to be removed**
   ```bash
   git worktree list
   ```

5. **Ask user for confirmation** before removing

6. **Remove each worktree**
   ```bash
   git worktree remove <path>
   ```

7. **Remove base directory**
   ```bash
   rm -rf ~/worktrees/$REPO_NAME
   ```

## Error Handling

| Error | Solution |
|-------|----------|
| Not in a git repository | Inform user to navigate to a git repository first |
| Branch doesn't exist | Suggest: `git fetch --all` or create new branch with `-b` |
| Worktree already exists | Show existing path, ask if user wants to navigate there |
| Uncommitted changes on remove | Ask user if they want to force remove |
| Permission denied | Check directory permissions |

## Examples

### Create worktree for feature branch
```
User: Create a worktree for the feature/new-ui branch
Assistant: I'll create a worktree for the feature/new-ui branch.

[Runs git fetch --all]
[Runs git worktree add ~/worktrees/my-repo/feature-new-ui feature/new-ui]

Worktree created at: ~/worktrees/my-repo/feature-new-ui
To start working: cd ~/worktrees/my-repo/feature-new-ui
```

### Create worktree with new branch
```
User: Create a worktree with a new branch fix/bug-123 from main
Assistant: I'll create a new branch fix/bug-123 based on main in a worktree.

[Runs git fetch --all]
[Runs git worktree add -b fix/bug-123 ~/worktrees/my-repo/fix-bug-123 main]

Worktree created at: ~/worktrees/my-repo/fix-bug-123
Branch fix/bug-123 created from main
To start working: cd ~/worktrees/my-repo/fix-bug-123
```

### Remove worktree
```
User: Remove the worktree for feature/old-feature
Assistant: I'll remove the worktree for feature/old-feature.

[Runs git worktree remove ~/worktrees/my-repo/feature-old-feature]

Worktree removed successfully.
```

### List worktrees
```
User: List all worktrees
Assistant: Here are the worktrees for this repository:

/Users/user/repo/my-repo         abc1234 [main]
/Users/user/worktrees/my-repo/feature-new-ui  def5678 [feature/new-ui]
/Users/user/worktrees/my-repo/fix-bug-123     ghi9012 [fix/bug-123]
```

## Keywords

git, worktree, branch, parallel development, multiple branches, workspace, checkout
