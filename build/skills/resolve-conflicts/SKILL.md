---
name: resolve-conflicts
description: >
  Resolve git merge and rebase conflicts semi-automatically. Classifies conflicts by type
  (DU/UD/UU/AA/DD), auto-resolves trivial ones, and applies context-aware resolution for the
  rest.
when_to_use: >
  When given a PR number or link to rebase, when a working tree already has conflicts, or when
  another skill hits conflicts mid-rebase or mid-merge. Also on "resolve conflicts", "fix the
  merge conflicts", or "rebase this PR".
license: MIT
compatibility: Claude Code, Codex, OpenCode, Pi
allowed-tools: Bash(git:*) Bash(gh:*) Read Edit Task AskUserQuestion
argument-hint: "[PR number, PR URL, issue number, or issue URL]"
metadata:
  author: edloidas
---

# Resolve Conflicts

Semi-automatic merge and rebase conflict resolution.

**Writes and pushes.** It rewrites the working tree, rewrites branch history through a rebase, and
in PR mode offers a force-push. The push is the only step that leaves the machine, and it is gated
on approval.

## Asking the User

Every question in this skill is written as `AskUserQuestion` options. Use that tool where
the host offers it, or the host's nearest structured-choice equivalent. Where the host has
neither, ask the same question in normal chat as a numbered list of 2–5 options —
recommended first, one short line of description each — and wait for the user to reply
with a number.

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

Display the context header, including when stopping:

```
PR: <title>
Branches: <base> ← <head>
Link: <url>
```

### Step 2: Prepare Working Directory

1. Check if working tree is dirty (`git status --porcelain`)
2. If dirty OR user included "worktree" in the invocation → create an isolated
   worktree for `<head-branch>` using whatever mechanism the host provides
   (a built-in worktree tool, or `git worktree add`). If the host cannot
   continue in the new worktree automatically, show the resulting
   `cd <path>` command and stop so the user can resume there.
3. If clean → work in current repo

### Step 3: Fetch and Rebase

```bash
git fetch origin <base>
git fetch origin <head>
before=$(git rev-parse "origin/<head>")
git checkout <head>
git reset --hard origin/<head>
git rebase origin/<base>
```

Keep `$before` for Step 5. It is the remote tip this rebase started from, and the only
value a force-push may safely lease against.

If rebase produces conflicts → proceed to Resolution Pipeline.
If rebase completes cleanly → show "No conflicts after rebase" and stop.

### Step 4: Resolution Pipeline

Run the Resolution Pipeline (see below). This may loop multiple times during rebase — each `git rebase --continue` can produce new conflicts.

### Step 5: Completion

After all conflicts resolved and rebase complete:

1. Run verification (see Verification section)
2. Show final report
3. Ask whether to force-push `<head>` to remote, per **Asking the User**:
   1. `Force push` (Recommended) — update the PR branch after the resolved rebase
   2. `Skip push` — keep the rebased branch local only
   - Yes → `git push --force-with-lease="<head>:$before" origin <head>`
   - No → skip
4. Then stop. Do not merge the PR, do not update its description, and do not start another
   rebase.

A bare `--force-with-lease` leases against the remote-tracking ref, which any `git fetch`
refreshes — and resolution loops for as long as the conflicts take, so a fetch in between turns
the lease into a no-op and lets the push discard a commit someone else added. `$before`, captured
in Step 3, is the tip the rebase was built on. A rejected push means the remote moved: re-run from
Step 3, never `--force`.

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

1. `cd "$(git rev-parse --show-toplevel)"`, then run `scripts/classify-conflicts.sh`.
   Its paths are relative to the repository root, so every resolution command below
   has to run from there too. Exit 3 means a conflicted path contains a newline, which
   a line-oriented report cannot represent — surface the message and stop; do not
   resolve a partial list.
2. Parse the output — extract counts and file lists per status code
3. If there are UU files, classify them by difficulty:
   - Read `references/conflict-analyzer-prompt.md` and dispatch a read-only
     subagent with it as the prompt body plus the UU file list. It classifies
     each file trivial / simple / complex and resolves nothing.
   - If the host has no subagent facility, classify inline using the same prompt.
   - Parse the classifier output to get the UU trivial/simple/complex subgroups
4. Combine bash output (DU/UD/DD/AA/AU/UA) with classifier output
5. Print the initial report (see `references/report-format.md`)

### Phase 2: Auto-Resolve

Resolve groups that need no LLM analysis:

| Group | Command |
|-------|---------|
| DU | `git rm "<file>"` for each file |
| UD | `git rm "<file>"` for each file |
| DD | `git rm "<file>"` for each file |
| AA | `git checkout --theirs "<file>" && git add "<file>"` — but if the classifier treated it as UU (both have meaningful content), treat as UU |
| AU | `git checkout --theirs "<file>" && git add "<file>"` |
| UA | `git checkout --theirs "<file>" && git add "<file>"` |
| UU trivial | `git checkout --theirs "<file>" && git add "<file>"` |

`classify-conflicts.sh` prints each path verbatim — unquoted and unescaped, so a name
with a space or a non-ASCII character arrives intact. Two consequences: always quote it
when passing it back to git, because the report does not escape it for you; and run from
the repository root, because the paths are relative to it.

Batch all trivial UU files into one resolver subagent for parallel execution.

When the group is done, print one line: `Auto-resolved <N> of <T> conflicts (DU <n>, UD <n>, DD <n>,
AA <n>, UU trivial <n>)`.

### Phase 3: Context-Aware Resolve

Attempt to resolve all remaining UU files (simple and complex). Before dispatching, print one line:
`Resolving <N> UU files (<S> simple, <C> complex) in <R> resolvers`.

**How far to read per complex file:**

| Complex files in this batch | Read before resolving |
|-----------------------------|-----------------------|
| ≤3 | The conflicted file, its imports, and the callers of anything either side changed |
| 4–10 | The conflicted file and its imports. Leave a file unresolved rather than widening the read |
| >10 | The conflicted file only, one pass each. Whatever that pass cannot settle stays unresolved |

**Parallelization:**
- Dispatch one resolver subagent per file, at most 5 running concurrently
- Resolver subagents run no lint, build, typecheck, or verification commands. Verification is one
  pass at the end, over the whole tree.

**Each resolver subagent does this:**
1. Read the file to find all conflict markers
2. For each conflict block, work out what "ours" changed and what "theirs" changed
3. Combine both changes, or pick one side where they are genuinely incompatible
4. Replace each conflict block in place, markers and all. Do not regenerate the file from its
   two sides — a rewrite changes lines neither branch touched and buries the resolution in noise
5. `git add "<file>"` once no markers remain

**If a resolver subagent cannot resolve a file:** Leave the conflict markers in
place. Do not `git add` it. The file will appear in the final report as
unresolved.

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

A filled final report:

```
Resolved 9/12 conflicts automatically. 3 remaining need review.

### UU — complex (3)

- `src/scene/init.ts` — both sides restructured the mount sequence
- `src/net/socket.ts` — same `reconnect()` retry loop modified by both sides
- `pnpm-lock.yaml` — regenerated on both branches

Checks: `pnpm typecheck` — 2 errors in `src/scene/init.ts`, both from the unresolved markers.
```
