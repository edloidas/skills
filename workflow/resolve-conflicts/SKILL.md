---
name: resolve-conflicts
description: >
  Resolve git merge and rebase conflicts semi-automatically. Classifies conflicts
  by type (DU/UD/UU/AA/DD), auto-resolves trivial ones, and applies context-aware
  resolution for complex conflicts. Use when given a PR number/link to rebase,
  when local conflicts exist, or when another skill hits conflicts during rebase/merge.
license: MIT
allowed-tools: Bash(git:*) Bash(gh:*) Read Edit Agent
arguments: source
argument-hint: [PR number, PR URL, issue number, or issue URL]
metadata:
  author: edloidas
---

# Resolve Conflicts

Semi-automatic merge and rebase conflict resolution.

## Entry Point Detection

Determine mode from arguments:

| Input | Mode |
|-------|------|
| PR number, PR URL, issue number, issue URL | PR mode |
| No arguments + active conflicts in working tree | Local mode |
| Invoked by another skill during rebase/merge | Conditional mode |
| No arguments + no active conflicts | Error: nothing to resolve |

## PR Mode

### Step 1: Fetch PR Info

Run `scripts/fetch-pr-info.sh $ARGUMENTS` from the skill directory.

Parse the key=value output. Handle exit codes:

| Exit | Meaning | Action |
|------|---------|--------|
| 0 | PR found with conflicts | Continue to Step 2 |
| 1 | Input parsing failed | Show error, stop |
| 2 | gh not authenticated | Show error, stop |
| 3 | PR/issue not found | Show error, stop |
| 4 | Issue has no linked PR | Show context, stop |
| 5 | PR has no conflicts | Show context, stop |

**Always display context header** (even when stopping):

```
PR: <title>
Branches: <base> ← <head>
Link: <url>
```

### Step 2: Prepare Working Directory

1. Check if working tree is dirty (`git status --porcelain`)
2. If dirty OR user included "worktree" in the invocation → use `/git-worktree create <head-branch>` to work in isolation
3. If clean → work in current repo

### Step 3: Fetch and Rebase

```bash
git fetch origin <base>
git fetch origin <head>
git checkout <head>
git reset --hard origin/<head>
git rebase origin/<base>
```

If rebase produces conflicts → proceed to Resolution Pipeline.
If rebase completes cleanly → show "No conflicts after rebase" and stop.

### Step 4: Resolution Pipeline

Run the Resolution Pipeline (see below). This may loop multiple times during rebase — each `git rebase --continue` can produce new conflicts.

### Step 5: Completion

After all conflicts resolved and rebase complete:

1. Run verification (see Verification section)
2. Show final report
3. AskUserQuestion: "Force-push `<head>` to remote?"
   - Yes → `git push --force-with-lease origin <head>`
   - No → skip

If unresolved conflicts remain:
1. Show final report with remaining files
2. Stop and wait for user input

## Local Mode

1. Detect active merge/rebase state:
   - `.git/rebase-merge/` or `.git/rebase-apply/` → rebase in progress
   - `.git/MERGE_HEAD` → merge in progress
   - Neither → error "No active merge or rebase"
2. Run Resolution Pipeline
3. After resolution: `git rebase --continue` or `git merge --continue`
4. Loop if new conflicts appear
5. Show final report when done

## Conditional Mode

Same as Local Mode but:
- No AskUserQuestion prompts
- No push questions
- Return control to calling skill silently after resolution

---

## Resolution Pipeline

### Phase 1: Classify

1. Run `scripts/classify-conflicts.sh` from the skill directory
2. Parse the output — extract counts and file lists per status code
3. If there are UU files: dispatch the `conflict-analyzer` agent with the UU file list
   - The agent reads each UU file and classifies as trivial/simple/complex
   - Parse the agent's output to get the UU subgroups
4. Combine bash output (DU/UD/DD/AA/AU/UA) with agent output (UU trivial/simple/complex)
5. Print the initial report (see `references/report-format.md`)

### Phase 2: Auto-Resolve

Resolve groups that need no LLM analysis:

| Group | Command |
|-------|---------|
| DU | `git rm <file>` for each file |
| UD | `git rm <file>` for each file |
| DD | `git rm <file>` for each file |
| AA | `git checkout --theirs <file> && git add <file>` — but if the analyzer classified it as UU (both have meaningful content), treat as UU |
| AU | `git checkout --theirs <file> && git add <file>` |
| UA | `git checkout --theirs <file> && git add <file>` |
| UU trivial | `git checkout --theirs <file> && git add <file>` |

Batch all trivial UU files into one subagent for parallel execution.

### Phase 3: Context-Aware Resolve

Attempt to resolve all remaining UU files (simple and complex).

**Effort thresholds:**
- ≤3 complex files → spend significant effort on each, read surrounding code for context
- 4–10 complex files → attempt each, move on if stuck after reasonable effort
- 10+ complex files → attempt but don't over-invest; resolve what's feasible

**Parallelization:**
- Dispatch one subagent per file for parallel resolution
- Cap at ~5 concurrent subagents
- Subagents: read the conflicted file → understand both sides → write the resolved version → `git add`
- Subagents must NOT run lint, build, typecheck, or any verification commands

**For each file, the subagent should:**
1. Read the file to find all conflict markers
2. For each conflict block, understand what "ours" changed and what "theirs" changed
3. Decide how to combine both changes (or pick one side if they're truly incompatible)
4. Write the resolved file (no conflict markers remaining)
5. `git add <file>`

**If a subagent cannot resolve a file:** Leave the conflict markers in place. Do not `git add` it. The file will appear in the final report as unresolved.

### Phase 4: Continue Loop

After all resolvable conflicts are handled:

1. Check for remaining conflict markers: `git status --short | grep -E '^(UU|DU|UD|AU|UA|AA|DD) '`
2. If none remain:
   - For rebase: `git rebase --continue`
   - For merge: `git merge --continue`
   - If the continue produces new conflicts → go back to Phase 1
   - If the continue succeeds → proceed to Verification
3. If conflicts remain:
   - Show final report with unresolved files
   - In PR/Local mode: stop and wait for user
   - In Conditional mode: return with status indicating unresolved conflicts

---

## Verification

Run after all conflicts are resolved and rebase/merge is complete.

1. `git status` — confirm clean working tree
2. Check for project-specific lint/typecheck commands:
   - Read `CLAUDE.md` or `package.json` scripts for available commands
   - Run fast checks only: `tsc --noEmit`, `eslint`, `biome check`, etc.
   - Do NOT run slow builds or integration tests at this stage
3. If issues found (broken imports, type errors from deleted files):
   - Attempt to fix them
   - Re-run the check to confirm
4. Run build only at the very end if the project has a fast build (typical for JS projects)
5. If issues cannot be fixed → report them alongside any unresolved conflicts

---

## Keywords

merge conflicts, rebase conflicts, resolve conflicts, conflict resolution, git merge, git rebase, PR conflicts, pull request conflicts
