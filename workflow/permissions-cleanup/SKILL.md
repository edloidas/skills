---
name: permissions-cleanup
description: >
  Clean up stale and one-off permission entries from Claude Code settings files.
  Use when the user asks to clean permissions, remove stale entries, audit
  settings, or tidy up settings.local.json / settings.json.
license: MIT
compatibility: Claude Code
allowed-tools: Read Write Edit AskUserQuestion
arguments: "--dry-run, --project, or --global flags, space-separated"
argument-hint: "[--flags]"
metadata:
  author: edloidas
---

Clean up stale, one-off, and redundant permission entries from Claude Code settings files.

## Arguments

| Argument     | Description                                                      |
| ------------ | ---------------------------------------------------------------- |
| _(none)_     | Interactive — scan, report, ask before removing                  |
| `--dry-run`  | Show report only, do not modify files                            |
| `--project`  | Only scan project-level `.claude/settings.local.json`            |
| `--global`   | Only scan global `~/.claude/settings.json` and `settings.local.json` |

## Steps

### 1. Parse Arguments

Check the user's invocation for `--dry-run`, `--project`, or `--global` flags.

### 2. Detect Settings Files

Based on scope flags, determine which files to scan:

- **Global**: `~/.claude/settings.json`, `~/.claude/settings.local.json`
- **Project**: `.claude/settings.local.json` (relative to working directory)
- **Default** (no flag): all three

Skip files that do not exist.

### 3. Read and Parse

For each file, read its contents and extract the `permissions.allow` array.
If the array is missing or empty, mark the file as **clean** and move on.

### 4. Classify Entries

Apply the detection heuristics below to each entry. Categorize every entry as **keep** or **stale** with a reason.

#### Detection Heuristics

Test entries against these patterns in order. The first match determines the reason.

| ID | Pattern | Reason | Examples |
|----|---------|--------|----------|
| 1 | Contains `/Users/`, `/home/`, `/tmp/`, or `/var/` | Absolute path — should use relative paths | `Bash(git -C /Users/edloidas/repo/skills log)` |
| 2 | Contains `cat <<` or `EOF` | Embedded commit message — one-time approval | `Bash(git commit -m "$(cat <<'EOF'...")` |
| 3 | Contains `for ` + (`do ` or `; do`) | Inline multi-command script — one-time batch op | `Bash(for f in *.ts; do eslint "$f"; done)` |
| 4 | Contains `GIT_SEQUENCE_EDITOR`, `sed -i`, or `rebase` + `--onto` | Complex sed/awk/rebase — one-time operation | `Bash(GIT_SEQUENCE_EDITOR="sed -i ..." git rebase -i)` |
| 5 | Matches `curl` or `wget` with a URL containing a version number (`/\d+\.\d+/`) | Version-pinned URL fetch — one-off | `Bash(curl -s https://registry.npmjs.org/react-dom/19.2.0)` |
| 6 | Entry is a more specific version of an existing kept entry with a wildcard pattern | Redundant specific — already covered by wildcard | `Bash(git show HEAD~1 --no-stat)` when `Bash(git show:*)` exists |

Entries that match **none** of the above are classified as **keep**.

#### Redundancy Check (Heuristic 6)

For each entry not already flagged by heuristics 1–5:

1. Extract the tool name and command prefix (e.g., `Bash`, `Read`).
2. Look for existing entries with a wildcard pattern (`:*` suffix) that share the same tool and command root.
3. If a wildcard match exists, flag the entry as redundant and note which wildcard covers it.

Example: `Bash(git show HEAD~1 --no-stat)` is redundant if `Bash(git show:*)` is in the same allow list.

### 5. Present Findings

Output a Markdown report grouped by file:

```markdown
## Permissions Cleanup Report

### ~/.claude/settings.json — 3 stale entries

| # | Entry | Reason |
|---|-------|--------|
| 1 | `Bash(curl -s https://registry.npmjs.org/react-dom/19.2.0)` | Version-pinned URL fetch |
| 2 | `Bash(git show HEAD~1 --no-stat)` | Redundant — covered by `Bash(git show:*)` |
| 3 | `Bash(for f in *.ts; do eslint "$f"; done)` | Inline multi-command script |

### .claude/settings.local.json — 12 stale entries

| # | Entry | Reason |
|---|-------|--------|
| 1 | `Bash(git -C /Users/edloidas/repo/skills log ...)` | Absolute path |
| ... | ... | ... |

### ~/.claude/settings.local.json — clean
```

If `--dry-run`, stop here.

### 6. Ask User

For each file with stale entries, ask the user using `AskUserQuestion`:

- **Remove all** — Delete every flagged entry from this file
- **Review individually** — Go through entries one by one for keep/remove decisions
- **Skip** — Leave this file unchanged

If the user picks "Review individually", present each stale entry and ask whether to remove or keep it.

### 7. Apply Cleanup

For each confirmed removal:

1. Read the current file content (re-read to avoid stale data).
2. Remove the confirmed entries from `permissions.allow`.
3. Also remove the same entries from `permissions.deny` if present.
4. Write the updated JSON back, preserving formatting (2-space indent, trailing newline).
5. Report the number of entries removed per file.

## Edge Cases

- **Empty allow list**: Mark as clean, skip.
- **Malformed JSON**: Warn the user and skip the file. Do not attempt to fix it.
- **All entries flagged**: Ask for confirmation before clearing the entire list.
- **Wildcard-only entries** (e.g., `Bash(git:*)`): Always **keep** — never flag wildcards as stale.
- **Deny list entries**: Only remove from `permissions.deny` if the same entry is being removed from `permissions.allow`. Never independently audit the deny list.
